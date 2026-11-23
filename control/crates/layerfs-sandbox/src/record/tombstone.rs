//! Retired Sandbox tombstones: `machine/<machine>/sandbox-retired/<name>.json`.
//!
//! A close, force close, remove or reclaim writes the tombstone **before** it
//! deletes the Sandbox record, so a crash leaves the record or both, never
//! neither. The path is outside `sandbox/`, so a Sandbox listing never
//! mistakes a tombstone for a Sandbox. The tombstone names the generation the
//! close retired; a Sandbox recreated under the same name mints a new, greater
//! generation, so the old tombstone never retires it. A missing tombstone and
//! a missing record are both "no proof", never death.
use super::sandbox::SandboxRecord;
use layerfs_bridge::control::{SdkRefusal, SdkValue};
use layerfs_home::home::{self, paths, read_record, write_entity};
use std::path::Path;

type Result<T> = std::result::Result<T, SdkRefusal>;

/// One retired Sandbox record, as written before the Sandbox record was
/// removed. The generation is the ordered value its create minted.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct SandboxTombstone {
    /// The retired Sandbox's name.
    pub name: String,
    /// The machine its record named.
    pub machine: String,
    /// The generation the close retired.
    pub generation: String,
    /// When it was retired, in Unix milliseconds.
    pub retired_ms: i64,
}

impl SandboxTombstone {
    /// The tombstone of Sandbox `name` on `machine` in `home`, if it has one.
    pub fn read(home: &Path, machine: &str, name: &str) -> Result<Option<Self>> {
        let Some(value) = read_record(&paths::sandbox_tombstone(home, machine, name))? else {
            return Ok(None);
        };
        Ok(Some(Self::from_record(value)))
    }

    /// Writes the tombstone under `home`, replacing an earlier one for the
    /// same name (the newest retirement is the one admission compares).
    pub fn write(&self, home: &Path) -> Result<()> {
        let value = SdkValue::map([
            ("name", SdkValue::text(&self.name)),
            ("machine", SdkValue::text(&self.machine)),
            ("generation", SdkValue::text(&self.generation)),
            ("retired_ms", SdkValue::Int(self.retired_ms)),
        ]);
        write_entity(&paths::sandbox_tombstone(home, &self.machine, &self.name), &value)
    }

    /// The record as read; a tombstone missing a field is kept as read.
    fn from_record(value: SdkValue) -> Self {
        Self {
            name: value.get_text("name").unwrap_or("").to_owned(),
            machine: value.get_text("machine").unwrap_or("").to_owned(),
            generation: value.get_text("generation").unwrap_or("").to_owned(),
            retired_ms: value.get_int("retired_ms").unwrap_or(0),
        }
    }
}

/// Writes `record`'s tombstone under `home` before its record is deleted.
/// A record without a generation or machine has nothing a tombstone could
/// name, so there is nothing to write.
pub fn retire(home: &Path, record: &SandboxRecord) -> Result<()> {
    let Some(generation) = record.generation() else {
        return Ok(());
    };
    let machine = record.machine();
    if generation.is_empty() || machine.is_empty() {
        return Ok(());
    }
    SandboxTombstone {
        name: record.name().to_owned(),
        machine: machine.to_owned(),
        generation: generation.to_owned(),
        retired_ms: home::now_ms(),
    }
    .write(home)
}

/// [`retire`] for a record still in `directory`, named `name`: reads the
/// record there and writes its tombstone under `home`.
pub fn retire_in(home: &Path, directory: &Path, name: &str) -> Result<()> {
    match SandboxRecord::read_in(directory, name)? {
        Some(record) => retire(home, &record),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use layerfs_bridge::control::SdkValue;
    use layerfs_home::home::paths;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT: AtomicU64 = AtomicU64::new(0);

    fn home(tag: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "layerfs-tombstone-{tag}-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = std::fs::remove_dir_all(&path);
        std::fs::create_dir_all(&path).unwrap();
        path
    }

    fn record(name: &str, machine: &str, generation: Option<&str>) -> SandboxRecord {
        SandboxRecord::from_record(
            name,
            SdkValue::map([
                ("name", SdkValue::text(name)),
                ("machine", SdkValue::text(machine)),
                ("generation", SdkValue::opt_text(generation)),
            ]),
        )
    }

    #[test]
    fn a_tombstone_names_the_name_machine_and_generation() {
        let home = home("round-trip");
        let generation = layerfs_home::helpers::ordered_token("sandbox");
        retire(&home, &record("box", "machine-1", Some(&generation))).unwrap();
        let tombstone = SandboxTombstone::read(&home, "machine-1", "box")
            .unwrap()
            .expect("the tombstone");
        assert_eq!(tombstone.name, "box");
        assert_eq!(tombstone.machine, "machine-1");
        assert_eq!(tombstone.generation, generation);
        assert!(tombstone.retired_ms >= 0);
        assert!(paths::sandbox_tombstone(&home, "machine-1", "box").is_file());
        assert!(
            !paths::sandbox_retired_dir(&home, "machine-1")
                .starts_with(paths::sandbox_dir(&home, "box")),
            "the tombstone is outside the Sandbox namespace"
        );
        std::fs::remove_dir_all(home).unwrap();
    }

    #[test]
    fn a_record_without_a_generation_writes_no_tombstone() {
        let home = home("no-generation");
        retire(&home, &record("box", "machine-1", None)).unwrap();
        assert!(SandboxTombstone::read(&home, "machine-1", "box")
            .unwrap()
            .is_none());
        std::fs::remove_dir_all(home).unwrap();
    }
}
