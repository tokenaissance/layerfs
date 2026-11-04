//! #547 regression coverage for the control pool's admission classification.
//!
//! #543 deleted the inline tests behind `sandbox.get`'s refusal: a daemon that
//! closes before Hello is `Capacity` with an *unknown* retained count, a
//! broken connection is `Unavailable`, and a decoded `LAYERFS-CAPACITY` notice
//! is `Capacity` with the exact counts (#540). This file proves those pure
//! classifications without opening a socket; the end-to-end notice path is
//! covered by the daemon's real-process test.

use layerfs_bridge::control::{SdkRefusal, SdkValue};
use layerfs_bridge::duplex::admission::{AdmissionNotice, AdmissionReason};
use layerfs_control::daemon::internal::{
    admission_refusal, not_admitted, notice_refusal, NotAdmitted,
};
use std::time::Duration;

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

/// EOF before Hello means the daemon admitted nothing; the retained count is
/// unknown, and the refusal names a control slot rather than "other processes".
#[test]
fn eof_fallback_is_capacity_with_unknown_retained() {
    let (admission, kind) = not_admitted(&failed("Io(Kind(UnexpectedEof))")).unwrap();
    assert_eq!(kind, "UnexpectedEof");
    assert!(matches!(
        admission,
        NotAdmitted::NoVacantSlot { retained: None }
    ));
    let capacity = admission_refusal(Duration::from_secs(60), admission, kind);
    assert_eq!(capacity.code, "Capacity");
    assert!(capacity.message.contains("no vacant control slot"));
    assert!(capacity.message.contains("UnexpectedEof"));
    assert!(!capacity.message.contains("other processes"));
    assert!(capacity.message.contains("not admitted"));
    assert_eq!(
        capacity.detail.get_text("resource"),
        Some("daemon_control_slot")
    );
    assert!(matches!(
        capacity.detail.get("retained"),
        Some(SdkValue::Null)
    ));
    assert!(capacity.detail.get_bool("retryable"));
    assert_eq!(
        capacity.detail.get_text("admission"),
        Some("no-vacant-slot")
    );
}

/// A broken pipe or a reset is a failed connection, not exhausted capacity.
#[test]
fn reset_is_unavailable() {
    for kind in ["BrokenPipe", "ConnectionReset"] {
        let (admission, observed) = not_admitted(&failed(&format!("Io(Kind({kind}))"))).unwrap();
        assert_eq!(observed, kind);
        assert_eq!(admission, NotAdmitted::ConnectionFailed);
        let failure = admission_refusal(Duration::from_secs(60), admission, kind);
        assert_eq!(failure.code, "Unavailable");
        assert!(failure.message.contains(kind));
        assert!(!failure.message.contains("other processes"));
        assert!(matches!(
            failure.detail.get("resource"),
            Some(SdkValue::Null)
        ));
        assert!(failure.detail.get_bool("retryable"));
        assert_eq!(
            failure.detail.get_text("admission"),
            Some("connection-failed")
        );
    }
}

/// A timeout or a stale-daemon refusal is not an admission refusal.
#[test]
fn other_refusals_are_not_admission_refusals() {
    assert_eq!(not_admitted(&refused("StaleSandbox", "saved daemon")), None);
    assert_eq!(not_admitted(&failed("Io(Kind(TimedOut))")), None);
}

/// The decoded notice is the exact form: resource, retained count, both
/// vacant counts and retryability.
#[test]
fn notice_maps_to_capacity_with_exact_retained() {
    let notice = AdmissionNotice::new(AdmissionReason::NoPoolSlot, 8, 0, 1);
    let refusal = notice_refusal(notice);
    assert_eq!(refusal.code, "Capacity");
    assert_eq!(refusal.detail.get_int("retained"), Some(8));
    assert_eq!(refusal.detail.get_int("pool_vacant"), Some(0));
    assert_eq!(refusal.detail.get_int("reserved_vacant"), Some(1));
    assert!(refusal.detail.get_bool("retryable"));
    assert_eq!(
        refusal.detail.get_text("resource"),
        Some("daemon_control_slot")
    );
    assert!(!refusal.message.contains("other processes"));
}

/// A daemon still starting is `Unavailable`, and the notice says so.
#[test]
fn starting_notice_is_unavailable() {
    let refusal = notice_refusal(AdmissionNotice::new(AdmissionReason::Starting, 0, 0, 1));
    assert_eq!(refusal.code, "Unavailable");
    assert_eq!(refusal.detail.get_text("admission"), Some("starting"));
    assert!(refusal.detail.get_bool("retryable"));
}
