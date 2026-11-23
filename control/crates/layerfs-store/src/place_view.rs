//! The bounded place view the control layer builds from its home and the
//! Store's recorded machine homes.
//!
//! Admission on the engine side never reads a home file. The control layer
//! reads the place records it can see once per Store call and hands the engine
//! a bounded map: each machine's current MachineRecord.incarnation, each
//! Sandbox's current generation, and every machine-level sandbox-retired
//! tombstone. The caller's home is read first; then every `machines.<machine>`
//! entry of the Store record that records a `home` path is read and merged
//! into the same view. That is how a shared PostgreSQL Store proves an older
//! placement dead when another home recorded the newer one. A home it cannot
//! read supplies no authority; a name missing from the view is no proof, never
//! death.
//!
//! The view is bounded by the places the homes actually record and by
//! MAXIMUM_PLACES; it never scans a Store, a Workspace or a content pack.
use crate::open_args::OpenArgs;
use crate::record::StoreRecord;
use layerfs_bridge::control::SdkValue;
use layerfs_history::{ordered_token_parts, PlaceView};
use layerfs_home::home::{paths, read_record};
use layerfs_machine::record::MachineRecord;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// The most places one view carries. A home with more is truncated rather
/// than making admission unbounded; a missing name is conservative live.
pub const MAXIMUM_PLACES: usize = 4096;

/// Builds the bounded place view from the caller's home alone.
///
/// A missing home, a machine without a record and a Sandbox without a record
/// all contribute nothing. A read error is treated the same way: the view
/// stays conservative and the call is never refused because a place record
/// could not be read. None means the home carried no place evidence at all.
#[must_use]
pub fn from_home(home: &Path) -> Option<PlaceView> {
    let homes = [home.to_path_buf()];
    from_homes(&homes)
}

/// Builds the merged view from the caller's home and every `home` path the
/// Store record's `machines.<machine>` entries record, in that order.
///
/// An entry without a home, a relative path and an unreachable path all
/// contribute no proof, so a Store whose second home is offline keeps its
/// conservative live answer.
#[must_use]
pub fn from_store(home: &Path, record: &StoreRecord) -> Option<PlaceView> {
    let mut homes = vec![home.to_path_buf()];
    for recorded in record.machine_homes() {
        if !homes.contains(&recorded) {
            homes.push(recorded);
        }
    }
    from_homes(&homes)
}

/// [`from_store`] for a Store call's [`OpenArgs`]: the caller's home and the
/// Store record it carries. A call without a record reads its home alone.
#[must_use]
pub fn from_open(open: &OpenArgs) -> Option<PlaceView> {
    let home = open.home.as_deref()?;
    let (Some(store), Some(record)) = (open.store.as_deref(), open.store_record.as_ref()) else {
        return from_home(home);
    };
    from_store(home, &StoreRecord::from_record(store, record.clone()))
}

/// Builds the merged bounded view from `homes`, in order.
///
/// The same machine or Sandbox recorded by two homes keeps the newer ordered
/// value. Two values that cannot be ordered and differ prove nothing, so that
/// place is left out rather than guessed. The merged places are ordered by
/// their ordered token, newest first, and capped at [`MAXIMUM_PLACES`].
#[must_use]
pub fn from_homes(homes: &[PathBuf]) -> Option<PlaceView> {
    let mut merged = Merged::default();
    for home in homes {
        merged.observe_home(home);
    }
    merged.view(MAXIMUM_PLACES)
}

/// The view as the worker frame carries it, when home has one.
#[must_use]
pub fn encoded_from_home(home: &Path) -> Option<SdkValue> {
    from_home(home).map(|view| layerfs_store_service::history::admission::encode_place_view(&view))
}

/// The merged cross-home view as the worker frame carries it.
#[must_use]
pub fn encoded_from_store(home: &Path, record: &StoreRecord) -> Option<SdkValue> {
    from_store(home, record)
        .map(|view| layerfs_store_service::history::admission::encode_place_view(&view))
}

/// [`encoded_from_store`] for a Store call's [`OpenArgs`].
#[must_use]
pub fn encoded_from_open(open: &OpenArgs) -> Option<SdkValue> {
    from_open(open).map(|view| layerfs_store_service::history::admission::encode_place_view(&view))
}

/// One place value read from one or more homes. A conflict leaves no value.
#[derive(Default)]
struct Field {
    value: Option<String>,
    conflicted: bool,
}

impl Field {
    /// Merges one recorded value. Equal values are one place; two ordered
    /// values keep the newer; an unordered difference (including one side
    /// ordered and the other not) proves nothing.
    fn observe(&mut self, recorded: &str) {
        if self.conflicted {
            return;
        }
        let Some(current) = self.value.as_deref() else {
            self.value = Some(recorded.to_owned());
            return;
        };
        if current == recorded {
            return;
        }
        match (ordered_token_parts(current), ordered_token_parts(recorded)) {
            (Some(current_parts), Some(recorded_parts)) => {
                if recorded_parts > current_parts {
                    self.value = Some(recorded.to_owned());
                }
            }
            _ => {
                self.value = None;
                self.conflicted = true;
            }
        }
    }
}

/// One Sandbox's two place fields.
#[derive(Default)]
struct SandboxFields {
    generation: Field,
    retired: Field,
}

/// The accumulated places of every home read so far.
#[derive(Default)]
struct Merged {
    machines: BTreeMap<String, Field>,
    sandboxes: BTreeMap<(String, String), SandboxFields>,
}

/// One place a view can carry, ordered after the merge.
#[derive(Clone, Debug, Eq, Ord, PartialEq, PartialOrd)]
enum Place {
    Machine(String),
    Generation(String, String),
    Retired(String, String),
}

impl Merged {
    fn sandbox(&mut self, machine: &str, sandbox: &str) -> &mut SandboxFields {
        self.sandboxes
            .entry((machine.to_owned(), sandbox.to_owned()))
            .or_default()
    }

    /// Reads one home's machine records, Sandboxes and tombstones. A folder
    /// or record that cannot be read contributes nothing.
    fn observe_home(&mut self, home: &Path) {
        for machine in paths::names(&home.join("machine")).unwrap_or_default() {
            if let Ok(Some(record)) = MachineRecord::read(home, &machine) {
                if let Some(incarnation) = record.incarnation() {
                    self.machines
                        .entry(machine.clone())
                        .or_default()
                        .observe(incarnation);
                }
            }
            for (name, generation) in tombstones(&paths::sandbox_retired_dir(home, &machine)) {
                self.sandbox(&machine, &name).retired.observe(&generation);
            }
        }
        for sandbox in paths::names(&home.join("sandbox")).unwrap_or_default() {
            let Ok(Some(record)) = read_record(&paths::sandbox_record(home, &sandbox)) else {
                continue;
            };
            let (Some(generation), Some(machine)) =
                (record.get_text("generation"), record.get_text("machine"))
            else {
                continue;
            };
            self.sandbox(machine, &sandbox)
                .generation
                .observe(generation);
        }
    }

    /// The merged view, capped at `cap` places ordered by their token, newest
    /// first and then by name. A place with no value (a conflict) is absent.
    fn view(&self, cap: usize) -> Option<PlaceView> {
        let mut places: Vec<(String, Place)> = Vec::new();
        for (machine, field) in &self.machines {
            if let Some(token) = &field.value {
                places.push((token.clone(), Place::Machine(machine.clone())));
            }
        }
        for ((machine, sandbox), fields) in &self.sandboxes {
            if let Some(token) = &fields.generation.value {
                places.push((
                    token.clone(),
                    Place::Generation(machine.clone(), sandbox.clone()),
                ));
            }
            if let Some(token) = &fields.retired.value {
                places.push((
                    token.clone(),
                    Place::Retired(machine.clone(), sandbox.clone()),
                ));
            }
        }
        // Newest ordered token first; an unordered value has no order and
        // sorts after every ordered one. The name tie-break is stable.
        places.sort_by(|(left, left_place), (right, right_place)| {
            token_order(right)
                .cmp(&token_order(left))
                .then_with(|| left_place.cmp(right_place))
        });
        places.truncate(cap);

        let mut view = PlaceView::new();
        for (_, place) in places {
            match place {
                Place::Machine(machine) => {
                    if let Some(token) = self.machines.get(&machine).and_then(|f| f.value.clone()) {
                        view.set_machine(&machine, token);
                    }
                }
                Place::Generation(machine, sandbox) => {
                    if let Some(token) = self
                        .sandboxes
                        .get(&(machine.clone(), sandbox.clone()))
                        .and_then(|f| f.generation.value.clone())
                    {
                        view.set_sandbox_generation(&machine, &sandbox, token);
                    }
                }
                Place::Retired(machine, sandbox) => {
                    if let Some(token) = self
                        .sandboxes
                        .get(&(machine.clone(), sandbox.clone()))
                        .and_then(|f| f.retired.value.clone())
                    {
                        view.set_sandbox_retired(&machine, &sandbox, token);
                    }
                }
            }
        }
        if view.is_empty() {
            None
        } else {
            Some(view)
        }
    }
}

/// The sort key of one place token: ordered tokens first (newest first in a
/// descending sort), then their milliseconds and nonce; an unordered token
/// has no order and sorts last.
fn token_order(token: &str) -> (u8, u64, &str, &str) {
    match ordered_token_parts(token) {
        Some((milliseconds, nonce)) => (1, milliseconds, nonce, token),
        None => (0, 0, "", token),
    }
}

/// The tombstones dir holds, as (Sandbox name, retired generation). A
/// tombstone without a generation names nothing admission can compare.
fn tombstones(dir: &Path) -> Vec<(String, String)> {
    let mut found = Vec::new();
    let Ok(entries) = std::fs::read_dir(dir) else {
        return found;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }
        let Some(name) = path.file_stem().and_then(|stem| stem.to_str()) else {
            continue;
        };
        let Ok(Some(record)) = read_record(&path) else {
            continue;
        };
        if let Some(generation) = record.get_text("generation") {
            found.push((name.to_owned(), generation.to_owned()));
        }
    }
    found.sort();
    found
}

#[cfg(test)]
mod tests {
    use super::*;
    use layerfs_home::home::write_entity;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT: AtomicU64 = AtomicU64::new(0);

    fn home(tag: &str) -> std::path::PathBuf {
        let path = std::env::temp_dir().join(format!(
            "layerfs-place-view-{tag}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    fn token(label: &str, milliseconds: u64, nonce: &str) -> String {
        format!("p1:{label}:{milliseconds:016}:{nonce}")
    }

    fn record_store(home: &Path, machine: &str, incarnation: &str) {
        MachineRecord::built_in(machine, "home-id")
            .with_incarnation(incarnation)
            .write(home)
            .unwrap();
    }

    /// A Store record whose `machines.<machine>` entry records `extra_home`.
    fn store_record(extra_home: &Path) -> StoreRecord {
        StoreRecord::connected("shared", "postgres://u@db/store", "layerfs", "local", None).with(
            "machines",
            SdkValue::map([(
                "box",
                SdkValue::map([("home", SdkValue::text(extra_home.display().to_string()))]),
            )]),
        )
    }

    #[test]
    fn the_view_names_the_machine_sandbox_and_tombstone() {
        let home = home("records");
        MachineRecord::built_in("box", "home-id")
            .with_incarnation("p1:worker:1:aa")
            .write(&home)
            .unwrap();
        write_entity(
            &paths::sandbox_record(&home, "live"),
            &SdkValue::map([
                ("name", SdkValue::text("live")),
                ("machine", SdkValue::text("box")),
                ("generation", SdkValue::text("p1:sandbox:2:bb")),
            ]),
        )
        .unwrap();
        write_entity(
            &paths::sandbox_tombstone(&home, "box", "gone"),
            &SdkValue::map([
                ("name", SdkValue::text("gone")),
                ("machine", SdkValue::text("box")),
                ("generation", SdkValue::text("p1:sandbox:1:cc")),
                ("retired_ms", SdkValue::Int(1)),
            ]),
        )
        .unwrap();

        let view = from_home(&home).expect("the home's places");
        assert_eq!(
            view.machines().get("box").map(String::as_str),
            Some("p1:worker:1:aa")
        );
        let live = view
            .sandboxes()
            .get(&("box".to_owned(), "live".to_owned()))
            .expect("the live Sandbox");
        assert_eq!(live.generation.as_deref(), Some("p1:sandbox:2:bb"));
        let gone = view
            .sandboxes()
            .get(&("box".to_owned(), "gone".to_owned()))
            .expect("the tombstone");
        assert_eq!(gone.retired.as_deref(), Some("p1:sandbox:1:cc"));
        assert!(encoded_from_home(&home).is_some());
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn a_home_without_place_records_supplies_no_authority() {
        let home = home("empty");
        assert_eq!(from_home(&home), None);
        assert_eq!(encoded_from_home(&home), None);
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn two_homes_keep_the_newer_ordered_incarnation_and_prove_the_older_dead() {
        let caller = home("cross-caller");
        let other = home("cross-other");
        let older = token("worker", 5, "aa");
        let newer = token("worker", 6, "bb");
        record_store(&caller, "box", &older);
        record_store(&other, "box", &newer);
        let record = store_record(&other);

        let view = from_store(&caller, &record).expect("both homes' places");
        assert_eq!(view.machines().get("box"), Some(&newer));
        let current = view.record(Some("box"), None);
        assert_eq!(
            layerfs_history::PlaceAuthority {
                machine_incarnation: Some(older.clone()),
                ..layerfs_history::PlaceAuthority::default()
            }
            .liveness(2_000, Some(&current)),
            layerfs_history::Liveness::Dead,
            "the older incarnation is dead across homes"
        );
        assert_eq!(from_store(&caller, &record), Some(view));
        // The existing worker `place_view` frame carries the merged view: the
        // engine decodes the newer incarnation recorded in the other home.
        let encoded = encoded_from_store(&caller, &record).expect("the frame");
        let decoded = layerfs_store_service::history::admission::decode_place_view(Some(&encoded))
            .expect("the decoded view");
        assert_eq!(decoded.machines().get("box"), Some(&newer));
        std::fs::remove_dir_all(caller).unwrap();
        std::fs::remove_dir_all(other).unwrap();
    }

    #[test]
    fn an_offline_recorded_home_contributes_no_proof() {
        let caller = home("offline-caller");
        let other = home("offline-other");
        let older = token("worker", 5, "aa");
        let newer = token("worker", 6, "bb");
        record_store(&caller, "box", &older);
        record_store(&other, "box", &newer);
        let record = store_record(&other);
        std::fs::remove_dir_all(&other).unwrap();

        let view = from_store(&caller, &record).expect("the caller's places");
        assert_eq!(view.machines().get("box"), Some(&older));
        let current = view.record(Some("box"), None);
        assert_eq!(
            layerfs_history::PlaceAuthority {
                machine_incarnation: Some(older.clone()),
                ..layerfs_history::PlaceAuthority::default()
            }
            .liveness(2_000, Some(&current)),
            layerfs_history::Liveness::Live,
            "an offline home is conservative live, never death"
        );
        std::fs::remove_dir_all(caller).unwrap();
    }

    #[test]
    fn unordered_conflicting_values_prove_nothing() {
        let first = home("unordered-first");
        let second = home("unordered-second");
        MachineRecord::built_in("box", "home-id")
            .with_incarnation("worker:1")
            .write(&first)
            .unwrap();
        MachineRecord::built_in("box", "home-id")
            .with_incarnation("worker:2")
            .write(&second)
            .unwrap();
        // A Sandbox keeps the view non-empty, so the conflict is the only
        // thing missing from it.
        write_entity(
            &paths::sandbox_record(&first, "live"),
            &SdkValue::map([
                ("name", SdkValue::text("live")),
                ("machine", SdkValue::text("box")),
                ("generation", SdkValue::text("p1:sandbox:1:aa")),
            ]),
        )
        .unwrap();
        let view = from_homes(&[first.clone(), second.clone()]).expect("a view");
        assert_eq!(view.record(Some("box"), None).machine_incarnation, None);
        std::fs::remove_dir_all(first).unwrap();
        std::fs::remove_dir_all(second).unwrap();
    }

    #[test]
    fn a_recorded_home_is_read_and_an_unrecorded_one_is_not() {
        let caller = home("recorded-caller");
        let other = home("recorded-other");
        record_store(&caller, "box", &token("worker", 1, "aa"));
        record_store(&other, "box", &token("worker", 2, "bb"));
        let view = from_store(&caller, &store_record(&other)).expect("both");
        assert_eq!(view.machines().get("box"), Some(&token("worker", 2, "bb")));
        // A store record with no `home` reads only the caller's home.
        let without =
            StoreRecord::connected("shared", "postgres://u@db/s", "layerfs", "local", None);
        let view = from_store(&caller, &without).expect("the caller's places");
        assert_eq!(view.machines().get("box"), Some(&token("worker", 1, "aa")));
        std::fs::remove_dir_all(caller).unwrap();
        std::fs::remove_dir_all(other).unwrap();
    }

    #[test]
    fn the_bound_keeps_the_newest_ordered_places() {
        let home = home("bound");
        let retired = paths::sandbox_retired_dir(&home, "box");
        std::fs::create_dir_all(&retired).unwrap();
        let total = MAXIMUM_PLACES + 4;
        for index in 0..total {
            let name = format!("b{index:04}");
            let generation = token("sandbox", index as u64, "n");
            std::fs::write(
                retired.join(format!("{name}.json")),
                format!(
                    "{{\"name\":\"{name}\",\"machine\":\"box\",\"generation\":\"{generation}\",\"retired_ms\":1}}"
                ),
            )
            .unwrap();
        }
        let view = from_home(&home).expect("the bounded view");
        assert_eq!(view.sandboxes().len(), MAXIMUM_PLACES);
        assert_eq!(MAXIMUM_PLACES, 4096);
        let newest = format!("b{:04}", total - 1);
        let oldest = "b0000".to_owned();
        assert!(view.sandboxes().contains_key(&("box".to_owned(), newest)));
        assert!(!view.sandboxes().contains_key(&("box".to_owned(), oldest)));
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn the_ordered_token_decides_a_same_place_across_homes() {
        let first = home("ordered-first");
        let second = home("ordered-second");
        record_store(&first, "box", &token("worker", 9, "aa"));
        record_store(&second, "box", &token("worker", 9, "zz"));
        let view = from_homes(&[first.clone(), second.clone()]).expect("a view");
        assert_eq!(view.machines().get("box"), Some(&token("worker", 9, "zz")));
        std::fs::remove_dir_all(first).unwrap();
        std::fs::remove_dir_all(second).unwrap();
    }
}
