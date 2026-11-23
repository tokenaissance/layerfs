#![cfg(test)]
use super::*;

fn record() -> MachineRecord {
    MachineRecord::from_record(
        "docker",
        SdkValue::map([
            ("name", SdkValue::text("docker")),
            ("platform", SdkValue::text("docker")),
        ]),
    )
}

#[test]
fn a_record_written_before_the_ordered_start_has_no_incarnation() {
    assert_eq!(record().incarnation(), None);
}

#[test]
fn a_start_records_the_ordered_incarnation_it_minted() {
    let incarnation = layerfs_home::helpers::ordered_token("worker");
    let record = record().with_incarnation(&incarnation);
    assert_eq!(record.incarnation(), Some(incarnation.as_str()));
    assert!(record.to_record().get_text("incarnation").is_some());
}
