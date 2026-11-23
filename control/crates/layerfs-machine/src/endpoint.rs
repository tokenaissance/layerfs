//! `machine.start` (#535 D11: the only call that starts a machine): it
//! dials the worker its `worker.json` records and, when that worker does
//! not answer, starts the machine and its worker, waits until it is ready
//! (a readiness wait, not a retry) and replaces `worker.json`
//! ([`running`]). Two processes starting the same machine take turns on its
//! `start.lock`.
use super::record::MachineRecord;
use super::spec::{self as record, machine_of, refusal, save_running};
use crate::progress::stage;
use crate::worker::Endpoint;
use layerfs_bridge::control::SdkRefusal;
use layerfs_home::events::Events;
use layerfs_home::outcome::refused;
use layerfs_platform::{self as adapters, HostOs, Platform, Route};
use std::path::Path;
use std::time::Duration;

/// How long a call waits for another process starting the same machine.
const START_WAIT: Duration = Duration::from_secs(600);

/// The worker of machine `name`, started if it does not answer its secret;
/// `None` when the machine's calls run in this process (`native`).
pub fn running(home: &Path, name: &str) -> Result<Option<Endpoint>, SdkRefusal> {
    let mut sink = |_| {};
    running_with_progress(home, name, &mut Events::new(&mut sink))
}

/// Starts or observes a worker while reporting stage boundaries and elapsed time.
pub fn running_with_progress(
    home: &Path,
    name: &str,
    events: &mut Events<'_>,
) -> Result<Option<Endpoint>, SdkRefusal> {
    let record = machine_of(home, name)?;
    let kind = record.platform()?;
    if kind.route(HostOs::current()) == Route::InProcess {
        return Ok(None);
    }
    if let Some(endpoint) = answering(home, name)? {
        return Ok(Some(endpoint));
    }
    let _start = start_lock(home, name)?;
    // another process may have started it, or removed it, meanwhile
    let record = machine_of(home, name)?;
    if let Some(endpoint) = answering(home, name)? {
        return Ok(Some(endpoint));
    }
    start(home, name, &record, events)
}

/// Starts machine `name` (its `record`) and records its worker; under its
/// start lock.
fn start(
    home: &Path,
    name: &str,
    record: &MachineRecord,
    events: &mut Events<'_>,
) -> Result<Option<Endpoint>, SdkRefusal> {
    let id = layerfs_home::home::opened(home)?.id;
    let mut spec = record::spec(home, &id, record)?;
    let bundle = stage(events, "bundle-validation", super::bundle::bundle)?;
    // the first start pins its Engine before anything is made in it (an
    // image loaded, a volume or container made); an Engine that does not
    // answer gets nothing, so a start that cannot reach it pins nothing
    let socket = &spec.tools.docker_socket;
    if spec.kind == Platform::Docker
        && adapters::socket_state(socket, adapters::SOCKET_ANSWER)
            == adapters::SocketState::Answering
    {
        let _lock = layerfs_home::home::lock::take(home)?;
        record_socket(home, name, socket)?;
    }
    // the docker worker's container runs the bundle's image when the
    // machine names none (P5)
    if spec.kind == Platform::Docker && spec.os_image.is_none() {
        spec.os_image = Some(stage(events, "sandbox-image", || {
            super::image::docker_default(home)
        })?);
    }
    // A new worker must replace a stopped one: its fresh incarnation would
    // mark every intent the old worker still serves dead. Stop it and confirm
    // the provider and its endpoint are gone; a start that cannot confirm
    // mints no token and settles nothing.
    stop_old(home, name, &spec)?;
    // Persist the ordered token before the worker exists, so the worker
    // serves with a value that is already durable in the home record.
    let incarnation = mint_incarnation(home, name)?;
    spec.incarnation = Some(incarnation);
    let Some(running) = stage(events, "provider-and-worker", || {
        adapters::start(&spec, &bundle).map_err(refusal)
    })?
    else {
        return Ok(None);
    };
    let endpoint = endpoint_of(&running.endpoint);
    // a worker of another build just started means the bundle is older than
    // this build: a stop and start would start it again (it stays recorded)
    let checked = stage(events, "worker-compatibility", || {
        let hello = crate::worker::hello(&endpoint)?;
        let address = endpoint.address.to_string();
        if let Some(stale) = hello.stale_bundle(name, &bundle.dir, &address) {
            return Err(stale);
        }
        Ok(())
    });
    {
        let _lock = layerfs_home::home::lock::take(home)?;
        match &checked {
            Ok(()) => save_running(home, name, &running)?,
            Err(error) => record::save_unready(home, name, &running, &error.message)?,
        }
        if spec.kind == Platform::Docker {
            record_socket(home, name, &spec.tools.docker_socket)?;
        }
    }
    checked?;
    Ok(Some(endpoint))
}

/// Stops the machine's worker (and VM where it has one) and confirms it no
/// longer runs before a new ordered incarnation is minted. The provider state
/// and the recorded endpoint must both say the old worker is gone; a stop that
/// cannot confirm one of them aborts the start, so no live mount is settled
/// by a token minted over its owner.
fn stop_old(home: &Path, name: &str, spec: &adapters::Spec) -> Result<(), SdkRefusal> {
    adapters::stop(spec).map_err(refusal)?;
    let state = adapters::provider_state(spec).map_err(refusal)?;
    // A running provider is never replaced. A broken one is not replaced
    // either, except on `docker`, where the start itself `docker rm -f`s the
    // container before making the new one; its endpoint still has to say the
    // old worker is gone below.
    if state == adapters::State::Running
        || (state == adapters::State::Failed && spec.kind != Platform::Docker)
    {
        return Err(refused(
            "Failed",
            format!(
                "the old worker of machine {name} did not stop (provider state {}); no new incarnation is minted and no intent is settled",
                state.as_str()
            ),
        ));
    }
    if let Some(endpoint) = recorded(home, name)? {
        if crate::worker::hello(&endpoint).is_ok() {
            return Err(refused(
                "Failed",
                format!(
                    "the old worker of machine {name} still answers after it was stopped; no new incarnation is minted and no intent is settled"
                ),
            ));
        }
    }
    Ok(())
}

/// Mints the ordered incarnation for the worker this start launches and
/// records it in the home `MachineRecord` before the provider starts. The
/// write is read back: a start that cannot make its token durable never
/// serves, rather than mixing this start's intents with the previous one's.
fn mint_incarnation(home: &Path, name: &str) -> Result<String, SdkRefusal> {
    let incarnation = layerfs_home::helpers::ordered_token("worker");
    let _lock = layerfs_home::home::lock::take(home)?;
    MachineRecord::of(home, name)?
        .with_incarnation(&incarnation)
        .write(home)?;
    let saved = MachineRecord::of(home, name)?;
    if saved.incarnation() != Some(incarnation.as_str()) {
        return Err(refused(
            "Failed",
            format!("machine {name}'s ordered incarnation could not be recorded; the worker did not start"),
        ));
    }
    Ok(incarnation)
}

/// The docker machine's first start records the socket it starts on: once
/// the Engine answers, before anything is made in it, and again once the
/// provider started (a start that reached it without a ping), so it never
/// moves to another Engine (its data volume and loaded image are in that
/// one) until `machine update docker --docker ""` clears it. A socket
/// recorded meanwhile is kept.
fn record_socket(home: &Path, name: &str, socket: &Path) -> Result<(), SdkRefusal> {
    record::update(home, name, |record| match record.docker() {
        Some(_) => record,
        None => record.with(
            "docker",
            layerfs_bridge::control::SdkValue::text(socket.display().to_string()),
        ),
    })
}

/// Machine `name`'s `start.lock`, held until dropped. Starting, creating and
/// removing a machine take it, always before the home lock, so a start
/// never runs beside a create or a remove of the same VM.
/// A wait for it, at most [`START_WAIT`], is not a retry.
pub type StartLock = layerfs_home::home::entity_lock::EntityLock;

/// Take the machine lifecycle lock before a start, create, remove or forced stop.
pub fn start_lock(home: &Path, name: &str) -> Result<StartLock, SdkRefusal> {
    let path = layerfs_home::home::paths::machine_dir(home, name).join("start.lock");
    let held = format!("machine {name} was being started, made or removed by another process");
    layerfs_home::home::entity_lock::take(&path, START_WAIT, &held)
}

/// The worker endpoint `machine/<name>/worker.json` records, as the client
/// dials it: the recorded address and secret, never a start and never a
/// dial. `None` when the machine records none.
pub fn recorded(home: &Path, name: &str) -> Result<Option<Endpoint>, SdkRefusal> {
    match record::worker(home, name)? {
        Some(endpoint) => Ok(Some(endpoint_of(&endpoint))),
        None => Ok(None),
    }
}

fn endpoint_of(endpoint: &adapters::Endpoint) -> Endpoint {
    Endpoint {
        address: endpoint.address,
        secret: endpoint.secret.clone(),
    }
}

/// The recorded worker, when it answers its secret and matches this build.
/// Another build is refused, never replaced by a start over it.
fn answering(home: &Path, name: &str) -> Result<Option<Endpoint>, SdkRefusal> {
    let Some(recorded) = record::worker(home, name)? else {
        return Ok(None);
    };
    let endpoint = endpoint_of(&recorded);
    match crate::worker::hello(&endpoint) {
        Ok(hello) => match hello.mismatch(&endpoint.address.to_string()) {
            Some(refusal) => Err(refusal),
            None => Ok(Some(endpoint)),
        },
        Err(_) => Ok(None),
    }
}

#[path = "../tests/support/endpoint_tests.rs"]
mod tests;
