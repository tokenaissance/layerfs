#![cfg(test)]
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
