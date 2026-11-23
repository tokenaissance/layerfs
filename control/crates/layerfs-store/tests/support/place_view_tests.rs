#![cfg(test)]
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
    let without = StoreRecord::connected("shared", "postgres://u@db/s", "layerfs", "local", None);
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
