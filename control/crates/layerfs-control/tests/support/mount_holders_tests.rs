#![cfg(test)]
use super::super::target::Checks;
use super::*;

#[test]
fn a_missing_local_record_warns_and_is_never_released() {
    let home = std::env::temp_dir().join(format!("layerfs-mount-holders-{}", std::process::id()));
    std::fs::create_dir_all(&home).unwrap();
    let workspace = "07".repeat(32);
    let rows = SdkValue::List(vec![SdkValue::map([
        ("operation", SdkValue::text("00ff")),
        ("scope_id", SdkValue::text("11")),
        ("workspace", SdkValue::text(&workspace)),
        ("sandbox", SdkValue::text("gone")),
        ("machine", SdkValue::text("native")),
        ("project", SdkValue::text("api")),
        ("branch", SdkValue::text("main")),
    ])]);
    let mut checks = Checks::new("store", "shop");
    report(&home, "shop", false, STORE, Some(&rows), &mut checks);
    let text = format!("{:?}", checks.to_sdk());
    assert!(text.contains("mount holder"), "{text}");
    assert!(text.contains("store.mount_holders"), "{text}");
    assert!(text.contains("Historical mount holders"), "{text}");
    let _ = std::fs::remove_dir_all(&home);
}

#[test]
fn the_done_audit_is_reported_as_evidence_and_never_released() {
    let page = SdkValue::map([
        (
            "items",
            SdkValue::List(vec![SdkValue::map([
                ("op", SdkValue::text("00ff")),
                (
                    "evidence",
                    SdkValue::text("action=release;operator=alice;op=00ff"),
                ),
            ])]),
        ),
        ("page", SdkValue::Int(0)),
        ("limit", SdkValue::Int(16)),
        ("has_more", SdkValue::Bool(false)),
    ]);
    let mut checks = Checks::new("store", "shop");
    audit_report(&page, &mut checks);
    let text = format!("{:?}", checks.to_sdk());
    assert!(text.contains("retained done operator-audit row"), "{text}");
    assert!(text.contains("store.gc_audit"), "{text}");
    assert!(text.contains("action=release"), "{text}");
    assert!(!text.contains("warning"), "{text}");
}

#[test]
fn a_failed_audit_read_is_unknown_not_a_release() {
    let mut checks = Checks::new("store", "shop");
    audit_result(
        Err(refused("Unavailable", "the audit could not be read")),
        &mut checks,
    );
    let text = format!("{:?}", checks.to_sdk());
    assert!(text.contains("store.gc_audit"), "{text}");
    assert!(text.contains("unknown"), "{text}");
}
