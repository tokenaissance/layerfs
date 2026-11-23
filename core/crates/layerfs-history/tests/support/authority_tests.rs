#![cfg(test)]
use super::*;

fn token(label: &str, milliseconds: u64, nonce: &str) -> String {
    format!("{ORDERED_TOKEN_PREFIX}{label}:{milliseconds:016}:{nonce}")
}

fn authority(machine: u64, sandbox: &str) -> PlaceAuthority {
    PlaceAuthority {
        machine_incarnation: Some(token("worker", machine, "aa")),
        sandbox_generation: Some(token("sandbox", 10, sandbox)),
        lease_expires_ms: Some(1_000),
        fence_token: Some("fence:3".to_owned()),
    }
}

fn record(machine: Option<u64>, sandbox: Option<&str>) -> PlaceRecord {
    PlaceRecord {
        machine_incarnation: machine.map(|ms| token("worker", ms, "aa")),
        sandbox_generation: sandbox.map(|nonce| token("sandbox", 10, nonce)),
        sandbox_retired: None,
    }
}

#[test]
fn a_newer_machine_incarnation_is_dead_even_with_an_expired_lease() {
    assert_eq!(
        authority(7, "bb").liveness(2_000, Some(&record(Some(8), None))),
        Liveness::Dead
    );
}

#[test]
fn an_older_current_incarnation_is_uncertain_never_dead() {
    assert_eq!(
        authority(8, "bb").liveness(500, Some(&record(Some(7), None))),
        Liveness::Uncertain
    );
}

#[test]
fn equal_incarnations_are_live_while_the_lease_holds() {
    assert_eq!(
        authority(7, "bb").liveness(500, Some(&record(Some(7), None))),
        Liveness::Live
    );
}

#[test]
fn a_retired_sandbox_generation_is_dead() {
    let mut current = record(None, Some("bb"));
    current.sandbox_retired = Some(token("sandbox", 10, "bb"));
    assert_eq!(
        authority(7, "bb").liveness(500, Some(&current)),
        Liveness::Dead
    );
}

#[test]
fn a_reused_sandbox_name_with_a_newer_generation_is_dead() {
    assert_eq!(
        authority(7, "aa").liveness(500, Some(&record(None, Some("bb")))),
        Liveness::Dead
    );
}

#[test]
fn an_older_current_generation_is_uncertain_never_dead() {
    assert_eq!(
        authority(7, "bb").liveness(500, Some(&record(None, Some("aa")))),
        Liveness::Uncertain
    );
}

#[test]
fn unordered_values_differing_are_uncertain_equal_are_live() {
    let mut authority = authority(7, "aa");
    authority.machine_incarnation = Some("worker:7".to_owned());
    authority.sandbox_generation = None;
    let current = PlaceRecord {
        machine_incarnation: Some("worker:8".to_owned()),
        ..PlaceRecord::default()
    };
    assert_eq!(authority.liveness(500, Some(&current)), Liveness::Uncertain);
    let same = PlaceRecord {
        machine_incarnation: Some("worker:7".to_owned()),
        ..PlaceRecord::default()
    };
    assert_eq!(authority.liveness(500, Some(&same)), Liveness::Live);
}

#[test]
fn missing_place_evidence_never_proves_death() {
    let mut authority = authority(7, "aa");
    authority.lease_expires_ms = None;
    assert_eq!(authority.liveness(2_000, None), Liveness::Live);
}

#[test]
fn expired_lease_is_uncertain_not_dead() {
    assert_eq!(
        authority(7, "aa").liveness(2_000, Some(&record(Some(7), Some("aa")))),
        Liveness::Uncertain
    );
}

#[test]
fn an_old_fence_cannot_renew_or_release() {
    let authority = authority(7, "aa");
    assert!(authority.fence_matches(Some("fence:3")));
    assert!(!authority.fence_matches(Some("fence:4")));
    assert!(!authority.fence_matches(None));
}

#[test]
fn a_recreated_sandbox_is_live_beside_its_older_tombstone() {
    // name reuse: the current record's generation is newer than the
    // tombstone an earlier Sandbox of the same name left
    let mut place = record(None, Some("bb"));
    place.sandbox_retired = Some(token("sandbox", 10, "aa"));
    assert_eq!(
        authority(7, "bb").liveness(500, Some(&place)),
        Liveness::Live
    );
}

#[test]
fn a_tombstone_without_a_current_record_retires_its_generation() {
    let mut retired = record(None, None);
    retired.sandbox_retired = Some(token("sandbox", 10, "bb"));
    assert_eq!(
        authority(7, "aa").liveness(500, Some(&retired)),
        Liveness::Dead
    );
    // a newer recorded generation is a restore, never dead
    assert_eq!(
        authority(7, "cc").liveness(500, Some(&retired)),
        Liveness::Uncertain
    );
}

#[test]
fn a_place_view_carries_only_the_names_it_was_given() {
    let mut view = PlaceView::new();
    view.set_machine("box", "worker-new");
    view.set_sandbox_retired("box", "dead-box", "generation-dead");
    let place = view.record(Some("box"), Some("live-box"));
    assert_eq!(place.machine_incarnation.as_deref(), Some("worker-new"));
    assert_eq!(place.sandbox_generation, None);
    assert_eq!(place.sandbox_retired, None);
    // another machine is not in the view: no proof, never death
    let other = view.record(Some("other"), Some("dead-box"));
    assert_eq!(other, PlaceRecord::default());
    assert!(!view.is_empty());
    assert_eq!(view.machines().len(), 1);
    assert_eq!(view.sandboxes().len(), 1);
}

#[test]
fn a_place_view_retired_generation_proves_an_older_record_dead() {
    let mut view = PlaceView::new();
    view.set_sandbox_retired("box", "dead-box", token("sandbox", 10, "bb"));
    let place = view.record(Some("box"), Some("dead-box"));
    assert_eq!(
        authority(7, "aa").liveness(500, Some(&place)),
        Liveness::Dead
    );
    assert_eq!(
        authority(7, "cc").liveness(500, Some(&place)),
        Liveness::Uncertain
    );
}

#[test]
fn an_empty_place_view_proves_nothing() {
    let view = PlaceView::new();
    assert!(view.is_empty());
    assert_eq!(
        view.record(Some("box"), Some("box")),
        PlaceRecord::default()
    );
    assert_eq!(
        authority(7, "aa").liveness(500, Some(&view.record(Some("box"), Some("box")))),
        Liveness::Live
    );
}
