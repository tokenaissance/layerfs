//! #547 regression coverage for the pure control-slot state machine.
//!
//! #543 deleted the inline `#[cfg(test)]` modules that proved the #540
//! invariants: a retained failure never owns a slot, a stale or duplicate
//! finish changes nothing, and the retained ring stays bounded and timed.
//! These tests live outside product `src/`; they reach only the pure
//! `Slots`/`RetainedFailures` values, no socket and no daemon process.

use layerfs_bridge::{
    control::{Call, Reply, Request},
    duplex::{ChannelError, ChannelWork, PeerEndFailure, PeerEndPhase},
};
use layerfs_daemon::application::{
    internals::{
        AdmissionClass, Finished, RetainedFailure, RetainedFailures, SlotClass, SlotTicket, Slots,
        LIMIT, RESERVED_SLOTS, TTL,
    },
    ApplicationError, ConnectionFailure,
};
use layerfs_daemon::control::{ServeCause, ServeFailure, Served, Success};
use std::time::{Duration, Instant};

/// A failure after a decoded request: retained, never released.
fn failure(slot: usize) -> ConnectionFailure {
    ConnectionFailure {
        slot,
        received: None,
        original: None,
        cause: ApplicationError::Poisoned,
        fence_error: None,
        diagnostic_error: None,
    }
}

fn describe(slot: usize, class: SlotClass, generation: u64) -> RetainedFailure {
    RetainedFailure::describe(
        &failure(slot),
        class,
        generation,
        "daemon:pid:layerfs-control-0",
    )
}

/// A pool admission never takes the reserved slot and vice versa.
#[test]
fn admit_uses_only_its_class() {
    let mut slots = Slots::new(8 + RESERVED_SLOTS);
    for _ in 0..8 {
        slots.admit(AdmissionClass::ControlPool).unwrap();
    }
    assert_eq!(
        slots.admit(AdmissionClass::ControlPool),
        None,
        "a pool admission took the reserved slot"
    );
    let reserved = slots.admit(AdmissionClass::Install).unwrap();
    assert_eq!(reserved.index, 8);
    assert_eq!(reserved.class, SlotClass::Reserved);
    assert_eq!(slots.admit(AdmissionClass::Lease), None);
    let counts = slots.counts();
    assert_eq!(counts.pool_vacant, 0);
    assert_eq!(counts.pool_running, 8);
    assert_eq!(counts.reserved_vacant, 0);
    assert_eq!(counts.reserved_running, 1);
}

/// A retained failure is a record, not a slot: finishing the worker frees the
/// slot before the record is stored (#540).
#[test]
fn finish_frees_even_for_a_retained_failure() {
    let mut slots = Slots::new(8 + RESERVED_SLOTS);
    let now = Instant::now();
    let ticket = slots.admit(AdmissionClass::ControlPool).unwrap();
    let prebuilt = describe(ticket.index, ticket.class, ticket.generation);
    match slots.finish(ticket, Err(failure(ticket.index)), Some(prebuilt), now) {
        Finished::Retained(record) => {
            assert_eq!(record.class, "pool");
            assert_eq!(record.generation, ticket.generation);
        }
        _ => panic!("a decoded failure was not retained"),
    }
    assert_eq!(slots.counts().pool_vacant, 8);
    assert_eq!(slots.snapshot(now).failures.len(), 1);
}

/// Every running slot ends exactly once; a duplicate or stale finish releases
/// nothing and cannot free a newer worker (invariant 1).
#[test]
fn stale_or_duplicate_finish_changes_nothing() {
    let mut slots = Slots::new(8 + RESERVED_SLOTS);
    let now = Instant::now();
    let first = slots.admit(AdmissionClass::ControlPool).unwrap();
    slots.finish(
        first,
        Err(failure(first.index)),
        Some(describe(first.index, first.class, first.generation)),
        now,
    );
    // A duplicate finish of the same ticket changes nothing.
    assert!(matches!(
        slots.finish(first, Ok(()), None, now),
        Finished::Stale
    ));
    let second = slots.admit(AdmissionClass::ControlPool).unwrap();
    assert_eq!(second.index, first.index);
    assert!(second.generation > first.generation);
    // The old ticket cannot free the newer worker.
    assert!(matches!(
        slots.finish(first, Ok(()), None, now),
        Finished::Stale
    ));
    assert_eq!(slots.counts().pool_running, 1);
    slots.finish(second, Ok(()), None, now);
    assert_eq!(slots.counts().pool_vacant, 8);
}

/// The retained ring is bounded: the 65th record evicts the oldest and each
/// eviction increments `dropped` (invariant 3).
#[test]
fn ring_limit_evicts_oldest_and_counts_drops() {
    let mut store = RetainedFailures::new(3, TTL);
    let now = Instant::now();
    for slot in 0..5 {
        store.record(describe(slot, SlotClass::Pool, slot as u64 + 1), now);
    }
    let snapshot = store.snapshot(now);
    assert_eq!(snapshot.dropped, 2);
    assert_eq!(snapshot.recorded, 5);
    assert_eq!(
        snapshot.failures.iter().map(|f| f.slot).collect::<Vec<_>>(),
        vec![2, 3, 4]
    );
    assert_eq!(snapshot.limit, 3);
    assert_eq!(snapshot.ttl, TTL);

    let mut full = RetainedFailures::new(LIMIT, TTL);
    for slot in 0..LIMIT + 1 {
        full.record(describe(slot % 8, SlotClass::Pool, slot as u64 + 1), now);
    }
    let snapshot = full.snapshot(now);
    assert_eq!(snapshot.failures.len(), LIMIT);
    assert_eq!(snapshot.dropped, 1);
    assert_eq!(snapshot.recorded as usize, LIMIT + 1);
}

/// Records past their TTL are never returned and count as dropped.
#[test]
fn ttl_prunes_expired_records() {
    let mut store = RetainedFailures::new(8, Duration::from_secs(10));
    let now = Instant::now();
    store.record(describe(1, SlotClass::Pool, 1), now);
    store.record(
        describe(2, SlotClass::Pool, 2),
        now + Duration::from_secs(5),
    );
    let snapshot = store.snapshot(now + Duration::from_secs(9));
    assert_eq!(snapshot.failures.len(), 2);
    assert_eq!(snapshot.failures[0].expires_in, Duration::from_secs(1));
    let snapshot = store.snapshot(now + Duration::from_secs(16));
    assert_eq!(snapshot.failures.len(), 0);
    assert_eq!(snapshot.dropped, 2);
}

/// The accept loop's lazy reaper frees expired records before it refuses.
#[test]
fn reap_drops_expired_records() {
    let mut slots = Slots::new(1 + RESERVED_SLOTS);
    let now = Instant::now();
    let ticket = slots.admit(AdmissionClass::ControlPool).unwrap();
    slots.finish(
        ticket,
        Err(failure(ticket.index)),
        Some(describe(ticket.index, ticket.class, ticket.generation)),
        now,
    );
    slots.reap(now + TTL + Duration::from_secs(1));
    assert_eq!(slots.visible(), 0);
}

/// The textual cause is bounded and cut on a character boundary.
#[test]
fn cause_is_bounded_and_char_safe() {
    let mut failure = failure(0);
    failure.cause = ApplicationError::Worker("é".repeat(4096));
    let record = RetainedFailure::describe(&failure, SlotClass::Pool, 1, "owner");
    assert!(record.cause.len() <= 512 + "…".len());
    assert!(record.cause.ends_with('…'));
    assert!(record.cause.is_char_boundary(record.cause.len()));
}

/// A record names the slot, class, generation, owner, request, reply state and
/// cause the operator needs — not just a count.
#[test]
fn record_names_the_cause_request_and_reply_state() {
    let served = Served {
        call: Call {
            id: 1,
            request: Request::EndSession,
        },
        outcome: Ok(Success {
            reply: Reply::SessionEnded,
            commit: None,
            observation_failure: None,
            kernel: None,
        }),
    };
    let failure = ConnectionFailure {
        slot: 3,
        received: Some(vec![0xde, 0xad, 0xbe, 0xef]),
        original: None,
        cause: ApplicationError::SessionEnd {
            served: Box::new(served),
            ending: Box::new(PeerEndFailure {
                cause: ChannelError::Invalid("peer reset after final reply"),
                phase: PeerEndPhase::Read,
                fence_attempted: false,
                received: None,
                work: ChannelWork::default(),
            }),
        },
        fence_error: None,
        diagnostic_error: None,
    };
    let record = RetainedFailure::describe(
        &failure,
        SlotClass::Pool,
        9,
        "a1b2c3d4:812:layerfs-control-3",
    );
    assert_eq!(record.slot, 3);
    assert_eq!(record.class, "pool");
    assert_eq!(record.generation, 9);
    assert_eq!(record.received_bytes, Some(4));
    assert_eq!(record.request, Some("end-session"));
    assert!(record.reply_sent);
    assert!(record.cause.contains("session"), "{}", record.cause);
    let line = record.to_string();
    assert!(line.starts_with("ConnectionFailure {"), "{line}");
    assert!(
        line.contains("original_kind: Some(\"end-session\")"),
        "{line}"
    );
    assert!(line.contains("reply: \"sent\""), "{line}");
    assert!(line.contains("class: \"pool\""), "{line}");
    assert!(line.contains("owner:"), "{line}");
    assert!(line.contains("expires_in_ms:"), "{line}");
}

/// A worker that ends without an explicit finish releases its slot and
/// records the abandonment exactly once. `SlotGuard::drop` ends through this
/// same `Slots::abandon`; the wiring from a real dropped guard to this call
/// has no external test (a panic is caught and finished explicitly, and a
/// thread spawn failure cannot be provoked from outside the daemon).
#[test]
fn abandoning_a_slot_releases_it_and_records_the_drop_once() {
    let mut slots = Slots::new(1 + RESERVED_SLOTS);
    let now = Instant::now();
    let ticket = slots.admit(AdmissionClass::ControlPool).unwrap();
    match slots.abandon(ticket, "daemon:pid:layerfs-control-0", now) {
        Finished::Retained(record) => {
            assert_eq!(record.slot, ticket.index);
            assert_eq!(record.class, "pool");
            assert_eq!(record.generation, ticket.generation);
            assert_eq!(record.request, None);
            assert_eq!(record.received_bytes, None);
            assert!(!record.reply_sent);
            assert!(
                record.cause.contains("dropped before completion"),
                "{}",
                record.cause
            );
        }
        _ => panic!("an abandoned slot was not recorded as a retained failure"),
    }
    let counts = slots.counts();
    assert_eq!(counts.pool_running, 0);
    assert_eq!(counts.pool_vacant, 1);
    // A second drop of the same ticket is stale: the record is never doubled.
    assert!(matches!(
        slots.abandon(ticket, "daemon:pid:layerfs-control-0", now),
        Finished::Stale
    ));
    assert_eq!(slots.snapshot(now).failures.len(), 1);
}

/// A decoded call whose answer never left the daemon keeps custody: the slot
/// is released and the record names the request with `reply_sent: false`.
///
/// The failure is the one `connection()` builds when `answer_call` fails
/// after a decoded call (`ApplicationError::Control` around the original
/// `Served`). The socket-level send failure itself is not reproduced here;
/// no real-process test can lose a reply deterministically.
#[test]
fn decoded_request_without_a_reply_is_retained() {
    let mut slots = Slots::new(1 + RESERVED_SLOTS);
    let now = Instant::now();
    let ticket = slots.admit(AdmissionClass::ControlPool).unwrap();
    let failure = ConnectionFailure {
        slot: ticket.index,
        received: None,
        original: None,
        cause: ApplicationError::Control(Box::new(ServeFailure {
            original: Some(Served {
                call: Call {
                    id: 1,
                    request: Request::EndSession,
                },
                outcome: Ok(Success {
                    reply: Reply::SessionEnded,
                    commit: None,
                    observation_failure: None,
                    kernel: None,
                }),
            }),
            received: None,
            cause: ServeCause::Channel(ChannelError::Io(std::io::Error::from(
                std::io::ErrorKind::BrokenPipe,
            ))),
            fence_error: None,
        })),
        fence_error: None,
        diagnostic_error: None,
    };
    let record = RetainedFailure::describe(&failure, ticket.class, ticket.generation, "owner");
    assert_eq!(record.request, Some("end-session"));
    assert!(!record.reply_sent);
    match slots.finish(ticket, Err(failure), Some(record), now) {
        Finished::Retained(record) => {
            assert_eq!(record.request, Some("end-session"));
            assert!(!record.reply_sent);
        }
        _ => panic!("a decoded request without a reply was not retained"),
    }
    assert_eq!(slots.counts().pool_vacant, 1);
}

/// A ticket is only valid for the generation it was admitted under.
#[test]
fn ticket_identity_is_slot_and_generation() {
    let mut slots = Slots::new(1 + RESERVED_SLOTS);
    let now = Instant::now();
    let ticket: SlotTicket = slots.admit(AdmissionClass::ControlPool).unwrap();
    slots.finish(ticket, Ok(()), None, now);
    let adopted = slots.admit(AdmissionClass::ControlPool).unwrap();
    assert_eq!(adopted.index, ticket.index);
    assert_ne!(adopted.generation, ticket.generation);
    assert!(matches!(
        slots.finish(ticket, Ok(()), None, now),
        Finished::Stale
    ));
}
