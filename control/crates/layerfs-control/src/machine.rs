//! The machine calls whose answers or checks read a machine's Stores and
//! Sandboxes (layerfs-project#104): each runs `layerfs-machine`'s call with
//! those reads from [`crate::inventory`]. The other machine calls are
//! `layerfs-machine`'s own.
use crate::inventory;
use layerfs_bridge::control::{SdkRefusal, SdkValue};
use layerfs_home::events::Events;
use layerfs_home::names::MachineName;
use layerfs_home::outcome::Outcome;
use layerfs_machine::{MachineCreate, MachineUpdate, Related};
use std::path::Path;
use std::time::Duration;

/// What a machine holds, read from the Store and Sandbox records.
pub const RELATED: Related = Related {
    stores_on: inventory::stores_on,
    sandboxes_on: inventory::sandboxes_on,
    can_remove: inventory::can_remove_machine,
    can_stop: inventory::can_stop_machine,
    can_change: inventory::can_change_machine,
};

/// `machine.list`.
pub fn list(home: &Path) -> Outcome {
    layerfs_machine::list(home, RELATED)
}

/// `machine.get`.
pub fn get(home: &Path, name: &MachineName) -> Outcome {
    layerfs_machine::get(home, name, RELATED)
}

/// `machine.status`.
pub fn status(home: &Path, name: &MachineName) -> Outcome {
    layerfs_machine::status(home, name, RELATED)
}

/// `machine.start`. The start stops a previous worker and confirms it gone,
/// persists the ordered incarnation in the home `MachineRecord` before the
/// worker serves, and then settles the intents a previous incarnation left in
/// each Store on that machine (spec §3.1). A start that cannot confirm the old
/// worker or record the token fails before any settle; a Store the reconcile
/// cannot reach is left for the next start.
pub fn start(home: &Path, name: &MachineName) -> Outcome {
    let started = layerfs_machine::start(home, name, RELATED)?;
    let incarnation = record_start(home, name)?;
    let _ = reconcile_stores(home, name, incarnation.as_deref());
    Ok(started)
}

/// `machine.start` with stage progress.
pub fn start_with_progress(home: &Path, events: &mut Events<'_>, name: &MachineName) -> Outcome {
    let started = layerfs_machine::start_with_progress(home, name, RELATED, events)?;
    let incarnation = record_start(home, name)?;
    let _ = reconcile_stores(home, name, incarnation.as_deref());
    Ok(started)
}

/// The ordered incarnation of the start that just happened: the kernel boot
/// on `native` (stable across starts on one boot, changed by a reboot), or the
/// value the machine start persisted in the home `MachineRecord` before it
/// launched the worker. Native records it here; a worker's start records it
/// before serving and fails if it cannot, so this only reads it back. No
/// record means no token and no reconcile: an older worker's intents stay
/// conservative live rather than being settled by a guessed value.
fn record_start(home: &Path, machine: &MachineName) -> Result<Option<String>, SdkRefusal> {
    if layerfs_machine::runs_here(home, machine.as_str())? {
        let Some(incarnation) =
            layerfs_home::process::me().map(|(_, boot)| format!("boot:{boot:032x}"))
        else {
            return Ok(None);
        };
        let _lock = layerfs_home::home::lock::take(home)?;
        let record = layerfs_machine::record::MachineRecord::of(home, machine.as_str())?;
        record.with_incarnation(&incarnation).write(home)?;
        return Ok(Some(incarnation));
    }
    let record = layerfs_machine::record::MachineRecord::of(home, machine.as_str())?;
    let Some(recorded) = record.incarnation().map(str::to_owned) else {
        return Ok(None);
    };
    // Reconcile only with the token the worker is actually serving: a home
    // restore can bring back an older record than the running worker, and a
    // reconcile over that older value must not settle a live owner's intents.
    match worker_incarnation(home, machine.as_str())? {
        Some(reported) if reported == recorded => Ok(Some(recorded)),
        _ => Ok(None),
    }
}

/// The incarnation the machine's running worker reports, or `None` when its
/// calls run in this process (a `native` machine has no worker). Reads the
/// endpoint the start recorded and asks it once; it never starts a machine, so
/// a failed read cannot restart one.
fn worker_incarnation(home: &Path, machine: &str) -> Result<Option<String>, SdkRefusal> {
    if layerfs_machine::runs_here(home, machine)? {
        return Ok(None);
    }
    let Some(endpoint) = layerfs_machine::worker_endpoint(home, machine)? else {
        return Ok(None);
    };
    // A bounded read, not a retry: the machine is already up, so a worker
    // that does not answer now leaves the reconcile for the next start.
    let budget = layerfs_machine::worker::Budget {
        connect: Duration::from_millis(500),
        hello: Duration::from_millis(500),
        answer: Duration::from_secs(1),
    };
    let request = layerfs_machine::worker::request("worker.ping", SdkValue::Null)?;
    let answer =
        match layerfs_machine::worker::send_within(&endpoint, "worker.ping", &request, budget) {
            Ok(Ok(answer)) => answer,
            _ => return Ok(None),
        };
    Ok(answer.get_text("incarnation").map(str::to_owned))
}

/// Settles the mount intents a previous worker incarnation left in each Store
/// on `machine`, with the incarnation this start recorded. Never a live or
/// uncertain owner: the Store-side reconcile applies the same rule admission
/// does. A start that could not read or verify the incarnation skips the
/// reconcile.
fn reconcile_stores(
    home: &Path,
    machine: &MachineName,
    incarnation: Option<&str>,
) -> Result<(), SdkRefusal> {
    let Some(incarnation) = incarnation else {
        return Ok(());
    };
    let stores = inventory::stores_on(home, machine.as_str())?;
    for store in stores {
        let _ =
            layerfs_store::service::reconcile_machine(home, &store, machine.as_str(), incarnation);
    }
    Ok(())
}

/// `machine.stop`.
pub fn stop(home: &Path, name: &MachineName) -> Outcome {
    layerfs_machine::stop(home, name, RELATED)
}

/// `machine.create`.
pub fn create(home: &Path, events: &mut Events<'_>, request: &MachineCreate) -> Outcome {
    layerfs_machine::create(home, events, request, RELATED)
}

/// `machine.remove`. A removed machine's own connection to each
/// PostgreSQL Store is forgotten with it, so a later machine of its name
/// dials the Store's.
pub fn remove(home: &Path, name: &MachineName) -> Outcome {
    let removed = layerfs_machine::remove(home, name, RELATED)?;
    layerfs_store::postgresql::check::forget_machine(home, name).map_err(|refusal| {
        layerfs_home::outcome::refused(
            &refusal.code,
            format!(
                "machine {name} was removed, but its own PostgreSQL connection was not forgotten: {}",
                refusal.message
            ),
        )
    })?;
    Ok(removed)
}

/// `machine.update`.
pub fn update(home: &Path, request: &MachineUpdate) -> Outcome {
    layerfs_machine::update(home, request, RELATED)
}

/// `machine.images`: the Sandbox images on this machine, and the host's
/// Docker images it can copy.
pub fn images(home: &Path, name: &MachineName) -> Outcome {
    layerfs_sandbox::images::list(home, name)
}

/// `machine.load`: copies an image to this machine without a Sandbox.
pub fn load(home: &Path, events: &mut Events<'_>, name: &MachineName, image: &str) -> Outcome {
    layerfs_sandbox::image_load::machine_load(home, events, name, image)
}

/// `machine.prune`: removes one image, or every unused one.
pub fn prune(home: &Path, name: &MachineName, image: Option<&str>, unused: bool) -> Outcome {
    layerfs_sandbox::images::prune(home, name, image, unused)
}

/// Explicit crash stop of a machine and this home's Sandboxes, preserving data.
pub fn stop_force(home: &Path, name: &MachineName) -> Outcome {
    crate::machine_force::stop(home, name)
}
