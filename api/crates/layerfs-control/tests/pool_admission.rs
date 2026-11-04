//! #547 regression coverage for the control pool's admission classification.
//!
//! #543 deleted the inline tests behind `sandbox.get`'s refusal: a daemon that
//! closes before Hello means no vacant control slot with an *unknown* retained
//! count, and a broken connection is a failed connection, not capacity. A
//! timeout or a stale-daemon refusal is neither. This file proves that
//! classification, which is the decision the retrying open is built on.
//!
//! The two refusal *message* builders (`notice_refusal`, `admission_refusal`)
//! are private again: their wording is not a contract to assert, and the
//! `admission` detail they carry is a future typed outcome (S6). Consequences
//! are stated in `core/docs/issues/547/README.md`: the client mapping of a
//! decoded `LAYERFS-CAPACITY` notice to `Capacity` has no external test, and
//! no test covers the daemon *emitting* `NoPoolSlot` (it needs a
//! `ControlReady` daemon with every pool slot held). The notice encoding is
//! covered by `engine/crates/layerfs-bridge/tests/admission.rs`, and the
//! daemon's still-starting notice by `daemon_slots.rs`.

use layerfs_bridge::control::{SdkRefusal, SdkValue};
use layerfs_control::daemon::internal::{not_admitted, NotAdmitted};

fn failed(message: &str) -> SdkRefusal {
    refused("Failed", message)
}

fn refused(code: &str, message: &str) -> SdkRefusal {
    SdkRefusal {
        code: code.to_owned(),
        message: message.to_owned(),
        detail: SdkValue::Null,
    }
}

/// EOF before Hello is a no-vacant-slot admission failure; the retained
/// count is unknown, so nothing is claimed about it.
#[test]
fn eof_is_a_no_vacant_slot_admission_failure() {
    let (admission, kind) = not_admitted(&failed("Io(Kind(UnexpectedEof))")).unwrap();
    assert_eq!(kind, "UnexpectedEof");
    assert!(matches!(
        admission,
        NotAdmitted::NoVacantSlot { retained: None }
    ));
}

/// A broken pipe or a reset is a failed connection, not exhausted capacity.
#[test]
fn reset_is_a_failed_connection() {
    for kind in ["BrokenPipe", "ConnectionReset"] {
        let (admission, observed) = not_admitted(&failed(&format!("Io(Kind({kind}))"))).unwrap();
        assert_eq!(observed, kind);
        assert_eq!(admission, NotAdmitted::ConnectionFailed);
    }
}

/// A timeout or a stale-daemon refusal is not an admission refusal.
#[test]
fn other_refusals_are_not_admission_refusals() {
    assert_eq!(not_admitted(&refused("StaleSandbox", "saved daemon")), None);
    assert_eq!(not_admitted(&failed("Io(Kind(TimedOut))")), None);
}
