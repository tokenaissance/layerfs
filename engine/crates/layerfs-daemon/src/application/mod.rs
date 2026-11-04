//! Production direct-Store daemon startup/control, with no command supervisor.
mod bodies;
mod cli;
mod config;
mod connection;
mod diagnostics;
mod failure;
mod filesystem;
mod owner;
mod retained;
mod serve;
pub use cli::main;
pub use diagnostics::resources::{ResourceDiagnosticError, ResourceFailure, ResourceObservation};
pub(crate) use diagnostics::{commit_parts, namespace_values, storage_values};
pub use failure::{ApplicationError, ConnectionFailure};
pub use owner::Application;
#[doc(hidden)]
pub use owner::{
    AdmissionClass, Finished, SlotClass, SlotCounts, SlotTicket, Slots, RESERVED_SLOTS,
};
#[doc(hidden)]
pub use retained::{RetainedFailure, RetainedFailures, RetainedSnapshot, LIMIT, TTL};
