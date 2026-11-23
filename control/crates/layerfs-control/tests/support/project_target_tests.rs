#![cfg(test)]
use super::*;

fn row(project: &str) -> SdkValue {
    SdkValue::map([
        ("operation", SdkValue::text("00ff")),
        ("project", SdkValue::text(project)),
    ])
}

#[test]
fn filters_to_the_selected_project() {
    let rows = SdkValue::List(vec![row("api"), row("other"), row("api")]);
    let SdkValue::List(filtered) = filter_project(rows, "api") else {
        panic!("a list");
    };
    assert_eq!(filtered.len(), 2);
    assert!(filtered
        .iter()
        .all(|row| row.get_text("project") == Some("api")));
}
