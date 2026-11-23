#![cfg(test)]
use super::*;
use layerfs_history::records::GcIntentDone;

#[test]
fn a_place_view_round_trips_the_worker_frame() {
    let mut view = PlaceView::new();
    view.set_machine("box", "p1:worker:1:aa");
    view.set_sandbox_generation("box", "live", "p1:sandbox:2:bb");
    view.set_sandbox_retired("box", "gone", "p1:sandbox:1:cc");
    let encoded = encode_place_view(&view);
    let decoded = decode_place_view(Some(&encoded)).expect("the encoded view");
    assert_eq!(decoded, view);
}

#[test]
fn an_empty_or_absent_frame_place_is_none() {
    assert_eq!(decode_place_view(None), None);
    assert_eq!(
        decode_place_view(Some(&encode_place_view(&PlaceView::new()))),
        None
    );
}

#[test]
fn an_audit_page_names_every_retained_row() {
    let page = GcAuditPage {
        page: 2,
        limit: 10,
        has_more: true,
        items: vec![GcIntentDone {
            op_id: [7; 16],
            kind: GcIntentKind::Mount,
            scope_kind: GcScopeKind::Branch,
            scope_id: vec![1; 17],
            project: Some("proj".to_owned()),
            branch: Some("work".to_owned()),
            machine: Some("box".to_owned()),
            sandbox: Some("box".to_owned()),
            phase: Some("release".to_owned()),
            evidence: Some("action=release".to_owned()),
            updated_ms: 42,
        }],
    };
    let value = audit_value(&page);
    assert_eq!(value.get_int("page"), Some(2));
    assert_eq!(value.get_int("limit"), Some(10));
    assert_eq!(value.get("has_more"), Some(&SdkValue::Bool(true)));
    let Some(SdkValue::List(items)) = value.get("items") else {
        panic!("an item list");
    };
    assert_eq!(items.len(), 1);
    assert_eq!(
        items[0].get_text("op"),
        Some("07070707070707070707070707070707")
    );
    assert_eq!(items[0].get_text("evidence"), Some("action=release"));
    assert_eq!(items[0].get_int("updated_ms"), Some(42));
}
