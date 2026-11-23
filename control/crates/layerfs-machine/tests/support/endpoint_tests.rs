#![cfg(test)]
use super::*;
use layerfs_home::home;

static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

fn scratch() -> std::path::PathBuf {
    let path = std::env::temp_dir().join(format!(
        "layerfs-start-token-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&path);
    std::fs::create_dir_all(&path).unwrap();
    path
}

#[test]
fn a_start_mints_an_ordered_token_and_records_it_before_serving() {
    let scratch = scratch();
    let home = scratch.join("home");
    let id = home::ensure(&home).unwrap().id;
    super::super::spec::ensure_built_ins(&home, &id).unwrap();
    let first = mint_incarnation(&home, "docker").expect("the first token");
    std::thread::sleep(std::time::Duration::from_millis(5));
    let second = mint_incarnation(&home, "docker").expect("the second token");
    assert!(first.starts_with("p1:worker:"), "{first}");
    assert!(second > first, "a newer start mints a greater value");
    assert_eq!(
        MachineRecord::of(&home, "docker").unwrap().incarnation(),
        Some(second.as_str())
    );
    std::fs::remove_dir_all(scratch).unwrap();
}
