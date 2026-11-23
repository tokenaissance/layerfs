#![cfg(test)]
use super::*;
use layerfs_history::{GcIntent, GcIntentKind, GcScopeKind};

fn mount(op: u8) -> GcIntent {
    GcIntent::shared(
        [op; 16],
        GcIntentKind::Mount,
        GcScopeKind::Branch,
        vec![op; 17],
    )
    .named(Some("shop"), Some("main"))
    .placed(None, None, None)
}

#[test]
fn holder_rows_report_op_and_legacy_state() {
    let rows = holder_rows(&[MountHolderView::of(&mount(7))]);
    let SdkValue::List(rows) = rows else {
        panic!("a holder list");
    };
    assert_eq!(rows.len(), 1);
    assert_eq!(
        rows[0].get_text("op"),
        Some("07070707070707070707070707070707")
    );
    assert_eq!(rows[0].get_text("state"), Some("live"));
    assert_eq!(rows[0].get_text("sandbox"), None);
    assert_eq!(rows[0].get("legacy"), Some(&SdkValue::Bool(true)));
}

#[test]
fn an_operator_label_is_a_bounded_local_name() {
    assert_eq!(operator_label(""), Ok("local"));
    assert_eq!(operator_label("  alice "), Ok("alice"));
    assert!(operator_label(&"x".repeat(129)).is_err());
    assert!(operator_label("alice\nroot").is_err());
}

#[test]
fn legacy_is_missing_owner_or_place_evidence() {
    let mut row = mount(9);
    assert!(MountHolderView::of(&row).legacy());
    row = row.owned(Some("pid:1@0"), Some("boot:1")).placed(
        Some([0; 32]),
        Some("box"),
        Some("docker"),
    );
    assert!(!MountHolderView::of(&row).legacy());
    row = row.placed(None, None, None);
    assert!(MountHolderView::of(&row).legacy());
}
