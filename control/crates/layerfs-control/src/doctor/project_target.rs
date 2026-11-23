//! One project's Store mount holders, reported against this home.
use super::mount_holders::{self, PROJECT};
use super::target::{Budget, Checks};
use layerfs_bridge::control::SdkValue;
use layerfs_home::home::paths;
use layerfs_store::{
    diagnostic, identity,
    place::{self, Executor},
    record::{StoreRecord, StoreRef},
};
use std::path::Path;

/// Reports the mount intents of `project`'s Store that name that project.
/// A missing local SandboxRecord/WorkspaceRecord is a warning, never release.
pub(super) fn diagnose(home: &Path, project: &str, _budget: &Budget, checks: &mut Checks) {
    let Some((store, name)) = project.split_once('/') else {
        checks.fail(
            "project.record",
            "project must be written <store>/<project>",
        );
        return;
    };
    let record = match StoreRecord::of(home, store) {
        Ok(record) => record,
        Err(error) => {
            checks.fail(
                "project.store",
                format!("Store {store} record unavailable ({})", error.code),
            );
            return;
        }
    };
    let identity = match identity::identity_in(&record) {
        Ok(identity) => identity,
        Err(_) => {
            checks.fail("project.store", "Store identity is invalid");
            return;
        }
    };
    checks.pass("project.store", "Store record and identity parsed");
    match record.store_ref() {
        Ok(reference @ StoreRef::Sqlite { .. }) => match place::plan(home, reference) {
            Ok(Executor::Local) => {
                let path = paths::store_file(home, store);
                match diagnostic::mount_holders(&path, &identity) {
                    Ok(rows) => {
                        let rows = filter_project(rows, name);
                        mount_holders::report(home, store, false, PROJECT, Some(&rows), checks);
                    }
                    Err(error) => checks.unknown(PROJECT, error.message),
                }
            }
            Ok(Executor::Worker(_)) => checks.unknown(
                PROJECT,
                "worker-backed project mount holders are not read by this target yet",
            ),
            Err(error) => checks.unknown(PROJECT, error.message),
        },
        Ok(StoreRef::Postgres { .. }) => checks.unknown(
            PROJECT,
            "PostgreSQL project mount holders are not read by this target yet",
        ),
        Err(error) => checks.fail(
            "project.store",
            format!("Store {store} kind unavailable ({})", error.code),
        ),
    }
}

/// Keeps the rows whose recorded project is the selected project name.
fn filter_project(rows: SdkValue, project: &str) -> SdkValue {
    match rows {
        SdkValue::List(items) => SdkValue::List(
            items
                .into_iter()
                .filter(|row| row.get_text("project") == Some(project))
                .collect(),
        ),
        other => other,
    }
}

#[path = "../../tests/support/project_target_tests.rs"]
mod tests;
