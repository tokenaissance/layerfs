//! The `store` family: 13 calls, one file each (H1: push and pull replace
//! move; a PostgreSQL Store runs on every machine, #536 C4, and `update`
//! gives one its own connection, H9; `repair_mount_holders` is the explicit
//! operator bridge for legacy/unproven mount admissions).
mod compact;
mod connect;
mod repair_mount_holders;
mod create;
mod disconnect;
mod get;
mod list;
mod pull;
mod push;
mod remove;
mod stats;
mod status;
mod update;

use crate::calls::Calls;

/// Its calls, in the order help lists them.
pub(crate) fn calls() -> Calls {
    &[
        list::CALL,
        get::CALL,
        status::CALL,
        stats::CALL,
        create::CALL,
        connect::CALL,
        update::CALL,
        push::CALL,
        pull::CALL,
        remove::CALL,
        compact::CALL,
        repair_mount_holders::CALL,
        disconnect::CALL,
    ]
}
