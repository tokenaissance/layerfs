//! Pre-#540 base proof for #547 slice 1: the failing behavior itself.
//!
//! This file is not built with the branch. It is the base half of the slice-1
//! proof: on `d2c3f2c97` (the `fix/540-daemon-slots` base before the #540 fix
//! and before #543 moved tests out of product source) a control connection
//! that fails after its record was received keeps its admission slot
//! `Retained`, so the daemon runs out of control capacity.
//!
//! Reproduce, from a clean checkout of that commit:
//!
//! ```text
//! git worktree add /tmp/layerfs-547-base d2c3f2c97
//! cd /tmp/layerfs-547-base
//! cp <this file> engine/crates/layerfs-daemon/tests/pre543_repro.rs
//! cargo test -p layerfs-daemon --test pre543_repro
//! ```
//!
//! Expected: the test fails at the tenth client, before its Hello reply. The
//! branch's `daemon_slots.rs::retained_failures_do_not_consume_control_slots`
//! runs the same deaths and then reaches Hello, on the daemon this branch
//! ships. The suite in this branch cannot be built on the base: the slot
//! types it names (`Slots`, `SlotTicket`, `RetainedFailures`, `CapacityModel`)
//! do not exist before #540/#543.
//!
//! The file needs no product API beyond the public `DaemonSetup` config
//! encoding, the `layerfs-daemon` binary and the authenticated duplex client.

#![cfg(any(target_os = "linux", target_os = "macos"))]

use layerfs_bridge::{
    control::{Answer, Call, DaemonPhase, HelloRequest, Reply, Request},
    daemon_setup::{DaemonLimits, DaemonSetup},
    duplex::{self, Connection},
    DaemonStore, KernelRoute,
};
use std::{
    fs::{self, File},
    io::{BufRead, BufReader},
    net::SocketAddr,
    os::unix::fs::{MetadataExt, PermissionsExt},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::mpsc,
    thread,
    time::Duration,
};

const CLIENT_PRIVATE: [u8; 32] = [71; 32];
const SERVER_PRIVATE: [u8; 32] = [72; 32];
const CONNECTIONS: u16 = 8;
/// Nine deaths fill the eight pool slots and the one reserved slot, so the
/// tenth connection is refused admission.
const DEATHS: usize = CONNECTIONS as usize + 1;
/// A record the daemon receives but cannot decode: the worker fails after the
/// receive, and on this base keeps its slot.
const DIE: &[u8] = b"client-died-before-reading-reply";

struct Daemon {
    child: Child,
    address: SocketAddr,
    directory: PathBuf,
}

impl Drop for Daemon {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
        let _ = fs::remove_dir_all(&self.directory);
    }
}

fn private_directory(path: &Path) {
    fs::create_dir_all(path).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).unwrap();
}

/// Starts the actual pre-#540 executable with no installed Store.
fn start() -> Daemon {
    let directory = std::env::temp_dir().join(format!(
        "layerfs-547-pre543-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let _ = fs::remove_dir_all(&directory);
    private_directory(&directory);
    let mounts = directory.join("mounts");
    private_directory(&mounts);
    let identity = fs::metadata(&directory).unwrap();
    let setup = DaemonSetup {
        listen: "127.0.0.1:0".into(),
        private_key: SERVER_PRIVATE,
        control_peer: duplex::public_key(&CLIENT_PRIVATE).unwrap(),
        route: KernelRoute::Nfs,
        overlay: directory.join("overlay.sqlite").display().to_string(),
        mounts: mounts.display().to_string(),
        command_uid: identity.uid(),
        command_gid: identity.gid(),
        limits: DaemonLimits {
            connections: CONNECTIONS,
            handshake_ms: 2000,
            cache_bytes: 1024 * 1024,
            namespaces: 16,
            pager_kib: 1024,
            serial_low_water: 256,
        },
        store: DaemonStore::Sqlite {
            locator: directory.join("store.sqlite").display().to_string(),
            install: None,
        },
    };
    let config = directory.join("daemon.config");
    fs::write(&config, setup.encode().unwrap()).unwrap();
    fs::set_permissions(&config, fs::Permissions::from_mode(0o600)).unwrap();
    let child = Command::new(env!("CARGO_BIN_EXE_layerfs-daemon"))
        .arg("--config")
        .arg(&config)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::from(File::create(directory.join("daemon.stderr")).unwrap()))
        .spawn()
        .expect("spawn layerfs-daemon");
    let mut daemon = Daemon {
        child,
        address: "127.0.0.1:0".parse().unwrap(),
        directory,
    };
    let stdout = daemon.child.stdout.take().unwrap();
    let (send, receive) = mpsc::sync_channel(1);
    let reader = thread::spawn(move || {
        let mut line = String::new();
        let result = BufReader::new(stdout).read_line(&mut line).map(|_| line);
        let _ = send.send(result);
    });
    let line = match receive.recv_timeout(Duration::from_secs(10)) {
        Ok(Ok(line)) => line,
        _ => panic!("daemon never reported a listener"),
    };
    reader.join().unwrap();
    daemon.address = line
        .strip_prefix("LAYERFS_DAEMON_LISTEN ")
        .unwrap_or_else(|| panic!("unexpected daemon startup line: {line:?}"))
        .trim()
        .parse()
        .unwrap();
    daemon
}

/// One authenticated client. On the pre-#540 base the tenth call fails here:
/// the accept loop drops the socket instead of admitting it.
fn connect(address: SocketAddr) -> Connection {
    let stream = std::net::TcpStream::connect_timeout(&address, Duration::from_secs(2)).unwrap();
    stream
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    stream
        .set_write_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    duplex::initiate(
        stream,
        &CLIENT_PRIVATE,
        duplex::public_key(&SERVER_PRIVATE).unwrap(),
    )
    .unwrap()
}

/// The startup phase a client sees after its Hello reply.
fn hello(address: SocketAddr) -> DaemonPhase {
    let mut connection = connect(address);
    let call = Call {
        id: 1,
        request: Request::Hello(HelloRequest {
            expected_instance: None,
            wait_for_store: false,
        }),
    };
    connection.send.send(&call.encode().unwrap()).unwrap();
    match Answer::decode(connection.receive.receive().unwrap())
        .unwrap()
        .reply
    {
        Reply::Hello(status) => status.phase,
        other => panic!("unexpected Hello reply: {other:?}"),
    }
}

/// Nine clients die after their record was received; the tenth must be
/// admitted by the fixed daemon, and is refused by the base.
#[test]
fn tenth_client_is_refused_after_nine_deaths() {
    let daemon = start();
    for round in 0..DEATHS {
        let mut connection = connect(daemon.address);
        connection.send.send(DIE).unwrap();
        // The daemon records the failure and closes its end; a retained slot
        // is the only reason it would not admit the next connection.
        assert!(
            connection.receive.receive().is_err(),
            "round {round}: the daemon kept the connection after a recorded failure"
        );
        drop(connection);
    }

    // The base refuses this tenth authenticated client instead of answering
    // its Hello; the fixed daemon answers install-pending.
    assert_eq!(hello(daemon.address), DaemonPhase::InstallPending);
}
