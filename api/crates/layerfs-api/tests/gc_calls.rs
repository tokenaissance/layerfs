//! T11.1: the four GC calls in the API call table — their ids-only arguments,
//! typed refusals before any effect, and the result shapes of one reachable
//! refusal per call plus the three removal results and the §11 report.
use layerfs_api::Kind;
use layerfs_bridge::control::SdkValue;
use layerfs_history::records::{GcIntent, GcIntentKind, GcScopeKind};
use layerfs_history::PlaceAuthority;
use layerfs_store::open_args::OpenArgs;
use layerfs_store::record::StoreRecord;
use layerfs_store::service::{branch_named, with_service};
use layerfs_store_service::history::lookup;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT: AtomicU64 = AtomicU64::new(0);

fn tempdir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "layerfs-gc-calls-{tag}-{}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700)).unwrap();
    dir
}

fn t(s: &str) -> SdkValue {
    SdkValue::text(s)
}

fn map(fields: &[(&str, SdkValue)]) -> SdkValue {
    SdkValue::Map(
        fields
            .iter()
            .map(|(name, value)| ((*name).to_owned(), value.clone()))
            .collect(),
    )
}

fn call(
    home: &Path,
    name: &str,
    fields: &[(&str, SdkValue)],
) -> Result<SdkValue, (String, String)> {
    layerfs_api::call(Some(home), name, map(fields), &mut |_| {})
        .map_err(|refusal| (refusal.code, refusal.message))
}

fn ok(home: &Path, name: &str, fields: &[(&str, SdkValue)]) -> SdkValue {
    call(home, name, fields).unwrap_or_else(|refusal| panic!("{name}: {refusal:?}"))
}

fn refused(home: &Path, name: &str, fields: &[(&str, SdkValue)]) -> (String, String) {
    call(home, name, fields).expect_err("the call is refused")
}

/// A home with Store `shop` and project `shop/api` imported from a folder.
fn project() -> (PathBuf, PathBuf) {
    let home = tempdir("home");
    layerfs_api::home::open(&home).unwrap();
    let folder = tempdir("folder");
    std::fs::write(folder.join("base.txt"), "hello\n").unwrap();
    ok(&home, "store.create", &[("name", t("shop"))]);
    ok(
        &home,
        "project.init",
        &[
            ("project", t("shop/api")),
            ("folder", t(&folder.display().to_string())),
        ],
    );
    (home, folder)
}

fn p() -> (&'static str, SdkValue) {
    ("project", t("shop/api"))
}

#[test]
fn the_four_gc_calls_take_ids_only() {
    let expected: &[(&str, &[(&str, Kind)])] = &[
        (
            "branch.remove",
            &[("project", Kind::Project), ("branch", Kind::Name)],
        ),
        ("project.delete", &[("project", Kind::Project)]),
        (
            "project.remove_file",
            &[("project", Kind::Project), ("path", Kind::Text)],
        ),
        ("store.compact", &[("name", Kind::Name)]),
    ];
    for &(name, args) in expected {
        let spec = layerfs_api::find(name).unwrap_or_else(|| panic!("{name} is missing"));
        let given: Vec<(&str, Kind)> = spec.args.iter().map(|arg| (arg.name, arg.kind)).collect();
        assert_eq!(given.as_slice(), args, "{name} arguments");
        assert!(spec.args.iter().all(|arg| !arg.optional), "{name} required");
        // ids only: no call takes a data option. `store.compact` alone
        // declares the shared `on_progress` function (#42 item 45).
        let options: Vec<(&str, Kind)> = spec.options.iter().map(|o| (o.name, o.kind)).collect();
        if name == "store.compact" {
            assert_eq!(options, [("on_progress", Kind::Function)], "{name}");
        } else {
            assert!(options.is_empty(), "{name} has no options");
        }
    }
}

#[test]
fn wrong_kinds_and_unknown_options_are_refused_before_any_effect() {
    let home = tempdir("types");
    layerfs_api::home::open(&home).unwrap();
    let wrong: &[(&str, &[(&str, SdkValue)])] = &[
        (
            "branch.remove",
            &[("project", t("shop/api")), ("branch", SdkValue::Int(1))],
        ),
        ("project.delete", &[("project", SdkValue::Int(1))]),
        (
            "project.remove_file",
            &[("project", t("shop/api")), ("path", SdkValue::Int(1))],
        ),
        ("store.compact", &[("name", SdkValue::Int(1))]),
    ];
    for &(name, fields) in wrong {
        let (code, message) = refused(&home, name, fields);
        assert_eq!(code, "InvalidInput", "{name}: {message}");
        assert!(message.starts_with(name), "{name}: {message}");
    }
    let unknown: &[(&str, &[(&str, SdkValue)])] = &[
        (
            "branch.remove",
            &[
                ("project", t("shop/api")),
                ("branch", t("main")),
                ("force", SdkValue::Bool(true)),
            ],
        ),
        (
            "project.delete",
            &[("project", t("shop/api")), ("force", SdkValue::Bool(true))],
        ),
        (
            "project.remove_file",
            &[
                ("project", t("shop/api")),
                ("path", t("/base.txt")),
                ("force", SdkValue::Bool(true)),
            ],
        ),
        (
            "store.compact",
            &[("name", t("shop")), ("force", SdkValue::Bool(true))],
        ),
    ];
    for &(name, fields) in unknown {
        let (code, message) = refused(&home, name, fields);
        assert_eq!(code, "InvalidInput", "{name}: {message}");
        assert!(
            message.contains("unknown argument `force`"),
            "{name}: {message}"
        );
    }
    std::fs::remove_dir_all(home).unwrap();
}

#[test]
fn branch_remove_refuses_reserved_and_absent_branches() {
    let (home, folder) = project();
    let (code, message) = refused(&home, "branch.remove", &[p(), ("branch", t("main"))]);
    assert_eq!(code, "ReservedName", "{message}");
    // nothing ran: main is still there
    ok(&home, "branch.get", &[p(), ("branch", t("main"))]);
    let (code, message) = refused(&home, "branch.remove", &[p(), ("branch", t("ghost"))]);
    assert_eq!(code, "NoSuchBranch", "{message}");
    // a live Branch is hidden by the marker and reported as `Removed`
    ok(
        &home,
        "branch.fork",
        &[p(), ("name", t("work")), ("from_branch", t("main"))],
    );
    let removed = ok(&home, "branch.remove", &[p(), ("branch", t("work"))]);
    assert_eq!(removed.get_text("kind"), Some("Removed"));
    // the project is the caller's <store>/<project>, not the Store's inner name
    assert_eq!(removed.get_text("project"), Some("shop/api"));
    assert_eq!(removed.get_text("branch"), Some("work"));
    assert!(removed.get_int("removed_ms").is_some_and(|ms| ms >= 0));
    let (code, message) = refused(&home, "branch.get", &[p(), ("branch", t("work"))]);
    assert_eq!(code, "NoSuchBranch", "{message}");
    std::fs::remove_dir_all(home).unwrap();
    let _ = std::fs::remove_dir_all(folder);
}

#[test]
fn project_remove_file_checks_its_path_grammar_then_reports_markers() {
    let (home, folder) = project();
    for bad in [
        "", "/", "//a", "a//b", "a/", "./a", "a/./b", ".", "..", "\\",
    ] {
        let (code, message) = refused(&home, "project.remove_file", &[p(), ("path", t(bad))]);
        assert_eq!(code, "InvalidInput", "{bad:?}: {message}");
    }
    // no effect: the file the bad calls named is still readable
    let read = ok(
        &home,
        "file.read",
        &[p(), ("branch", t("main")), ("path", t("/base.txt"))],
    );
    assert_eq!(read.get_text("text"), Some("hello\n"));

    let removed = ok(
        &home,
        "project.remove_file",
        &[p(), ("path", t("/base.txt"))],
    );
    assert_eq!(removed.get_text("kind"), Some("Removed"));
    // the same full project name the caller passed
    assert_eq!(removed.get_text("project"), Some("shop/api"));
    assert!(removed.get_int("frontier_serial").is_some());
    assert!(removed.get_int("removed_ms").is_some_and(|ms| ms >= 0));
    // a repeat at the same frontier is UpToDate
    let repeat = ok(
        &home,
        "project.remove_file",
        &[p(), ("path", t("/base.txt"))],
    );
    assert_eq!(repeat.get_text("kind"), Some("UpToDate"));
    assert_eq!(
        repeat.get_int("frontier_serial"),
        removed.get_int("frontier_serial")
    );
    // the marker hides it from reads
    let (code, message) = refused(
        &home,
        "file.read",
        &[p(), ("branch", t("main")), ("path", t("/base.txt"))],
    );
    assert_eq!(code, "Removed", "{message}");
    std::fs::remove_dir_all(home).unwrap();
    let _ = std::fs::remove_dir_all(folder);
}

#[test]
fn project_delete_reports_removal_and_retires_the_entry() {
    let (home, folder) = project();
    let (code, message) = refused(&home, "project.delete", &[("project", t("shop/ghost"))]);
    assert_eq!(code, "NoSuchProject", "{message}");
    let removed = ok(&home, "project.delete", &[p()]);
    assert_eq!(removed.get_text("kind"), Some("Removed"));
    assert_eq!(removed.get_text("project"), Some("shop/api"));
    assert!(removed.get_int("deleted_ms").is_some_and(|ms| ms >= 0));
    assert!(removed.get_bool("home_entry_removed"));
    let (code, _) = refused(&home, "project.get", &[p()]);
    assert_eq!(code, "NoSuchProject");
    std::fs::remove_dir_all(home).unwrap();
    let _ = std::fs::remove_dir_all(folder);
}

/// A project name a `project.delete` retired is still held: a second
/// `project.init` is `NameTaken` with the `deleted` holder, refused before
/// the folder is scanned.
#[test]
fn project_init_after_delete_is_nametaken_deleted() {
    let (home, folder) = project();
    ok(&home, "project.delete", &[p()]);
    let refusal = layerfs_api::call(
        Some(&home),
        "project.init",
        map(&[
            ("project", t("shop/api")),
            ("folder", t(&folder.display().to_string())),
        ]),
        &mut |_| {},
    )
    .unwrap_err();
    assert_eq!(refusal.code, "NameTaken", "{}", refusal.message);
    let holder = refusal.detail.get("holder").expect("holder detail");
    assert_eq!(holder.get_text("kind"), Some("project"), "{refusal:?}");
    assert_eq!(holder.get_text("name"), Some("api"));
    assert_eq!(holder.get_text("state"), Some("deleted"));
    assert_eq!(refusal.detail.get_text("source"), Some("store"));
    std::fs::remove_dir_all(home).unwrap();
    let _ = std::fs::remove_dir_all(folder);
}

/// `store.compact` sends each phase as a progress event before it answers:
/// `{ progress: { phase, done, total } }` with null counts.
#[test]
fn store_compact_sends_each_phase_as_a_progress_event() {
    let (home, folder) = project();
    let compact = || {
        let mut phases = Vec::new();
        let report = layerfs_api::call(
            Some(&home),
            "store.compact",
            map(&[("name", t("shop"))]),
            &mut |event| {
                let progress = event.get("progress").expect("a progress event").clone();
                assert_eq!(progress.get("done"), Some(&SdkValue::Null), "{progress:?}");
                assert_eq!(progress.get("total"), Some(&SdkValue::Null), "{progress:?}");
                phases.push(progress.get_text("phase").expect("phase").to_owned());
            },
        )
        .unwrap_or_else(|refusal| panic!("store.compact: {refusal:?}"));
        (report.get_text("path").expect("path").to_owned(), phases)
    };
    // nothing is dead yet: the run stops after its mark
    let (path, phases) = compact();
    assert_eq!(
        (path.as_str(), phases.as_slice()),
        ("none", ["mark".to_owned()].as_slice())
    );
    // a deleted project makes the next run a rebuild, through all four phases
    ok(&home, "project.delete", &[p()]);
    let (path, phases) = compact();
    assert_eq!(path, "rebuild");
    assert_eq!(phases, ["mark", "build", "verify", "install"]);
    std::fs::remove_dir_all(home).unwrap();
    let _ = std::fs::remove_dir_all(folder);
}

#[test]
fn store_compact_refuses_an_unknown_store_and_reports_a_run() {
    let home = tempdir("compact-none");
    layerfs_api::home::open(&home).unwrap();
    let (code, message) = refused(&home, "store.compact", &[("name", t("ghost"))]);
    assert_eq!(code, "NoSuchStore", "{message}");
    std::fs::remove_dir_all(home).unwrap();

    let (home, folder) = project();
    let report = ok(&home, "store.compact", &[("name", t("shop"))]);
    assert_eq!(report.get_text("kind"), Some("Compacted"));
    let path = report.get_text("path").expect("path");
    assert!(matches!(path, "none" | "rebuild"), "{path}");
    let generation = report.get("generation").expect("generation");
    let before = generation.get_int("before").unwrap();
    let after = generation.get_int("after").unwrap();
    if path == "none" {
        assert_eq!(before, after);
    } else {
        assert_eq!(after, before + 1);
    }
    for field in [
        "dead_bytes_bound",
        "dead_bytes_refined",
        "logical_discarded",
        "backend_reusable",
        "physical_shrink",
        "peak_temp_bytes",
        "estimate",
        "zero_reasons",
        "kept_waste",
        "residue",
    ] {
        assert!(report.get(field).is_some(), "missing {field}");
    }
    let kept = report.get("kept_waste").expect("kept_waste");
    for field in [
        "dead_in_retained_packs_bytes",
        "delta_bases",
        "inode_blocks_bytes",
    ] {
        assert!(kept.get(field).is_some(), "missing kept_waste.{field}");
    }
    let residue = report.get("residue").expect("residue");
    assert!(residue.get("bytes").is_some());
    assert!(residue.get("artifacts").is_some());
    std::fs::remove_dir_all(home).unwrap();
    let _ = std::fs::remove_dir_all(folder);
}

#[test]
fn a_bare_project_name_is_refused_by_every_project_call() {
    let home = tempdir("bare-names");
    layerfs_api::home::open(&home).unwrap();
    let bare: &[(&str, &[(&str, SdkValue)])] = &[
        (
            "branch.remove",
            &[("project", t("api")), ("branch", t("main"))],
        ),
        ("project.delete", &[("project", t("api"))]),
        (
            "project.remove_file",
            &[("project", t("api")), ("path", t("/base.txt"))],
        ),
    ];
    for &(name, fields) in bare {
        let (code, message) = refused(&home, name, fields);
        assert_eq!(code, "InvalidInput", "{name}: {message}");
        assert!(message.contains("with its Store"), "{name}: {message}");
    }
    // store.compact takes a Store name; a project path is not one
    let (code, message) = refused(&home, "store.compact", &[("name", t("shop/api"))]);
    assert_eq!(code, "InvalidInput", "{message}");
    assert!(message.contains("store name"), "{message}");
    std::fs::remove_dir_all(home).unwrap();
}

fn future_ms() -> i64 {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("the clock is after the epoch")
        .as_millis();
    i64::try_from(now).expect("the clock fits an i64") + 60_000
}

/// `store.repair_mount_holders` is the explicit two-step operator repair:
/// preview answers the typed holder view and changes no intent; release needs
/// a preceding settle; `settle_legacy` marks only rows with no owner or place
/// evidence; release retains the row as the durable done audit, and the audit
/// action reads it back in bounded pages.
#[test]
fn store_repair_mount_holders_is_an_explicit_two_step_operator_call() {
    let (home, folder) = project();
    let record = StoreRecord::read(&home, "shop").unwrap().unwrap();
    let open = OpenArgs::of_record(&home, "shop", &record).unwrap();
    // The fixture's main Branch is the Branch the project recorded, read from
    // the name index. `store.repair_mount_holders` is what must resolve the
    // name `main` through `project.list_branches` (spec 4.4: a listing names
    // the recorded Branch, not a null main id).
    let (stack, branch) = with_service(&open, |service| {
        let stack = lookup::project(&service.store, "api")?;
        let main = layerfs_history::HistoryName::new("main").expect("a valid Branch name");
        let branch = service
            .store
            .history()
            .branch_named(stack.id, &main)
            .map_err(lookup::history)?
            .expect("the project records its main Branch")
            .id;
        Ok((stack.id, branch))
    })
    .unwrap();
    let live = GcIntent::shared(
        [0x21; 16],
        GcIntentKind::Mount,
        GcScopeKind::Branch,
        branch.as_slice(),
    )
    .in_project(stack.as_slice())
    .named(Some("api"), Some("main"))
    .placed(Some([0x22; 32]), Some("box"), Some("box"))
    .owned(Some("pid:1@0"), Some("boot:1"))
    .authorized(PlaceAuthority {
        machine_incarnation: Some("worker:1".to_owned()),
        sandbox_generation: Some("generation:1".to_owned()),
        lease_expires_ms: Some(future_ms()),
        fence_token: Some("fence:1".to_owned()),
    });
    let legacy = GcIntent::shared(
        [0x31; 16],
        GcIntentKind::Mount,
        GcScopeKind::Branch,
        branch.as_slice(),
    )
    .in_project(stack.as_slice())
    .named(Some("api"), Some("main"));
    with_service(&open, |service| {
        service.store.history().gc_register(&live).unwrap();
        service.store.history().gc_register(&legacy).unwrap();
        Ok(())
    })
    .unwrap();

    let live_op = "21".repeat(16);
    let legacy_op = "31".repeat(16);
    let repair = |action: &str, op: Option<&str>, legacy: bool| {
        let mut fields = vec![
            ("name", t("shop")),
            ("project", t("api")),
            ("branch", t("main")),
            ("action", t(action)),
        ];
        if let Some(op) = op {
            fields.push(("op", t(op)));
        }
        if legacy {
            fields.push(("legacy", SdkValue::Bool(true)));
        }
        fields.push(("operator", t("alice")));
        fields
    };

    // Preview answers the typed view, settle is a separate step, and release
    // needs the settled state.
    let preview = ok(
        &home,
        "store.repair_mount_holders",
        &repair("preview", None, false),
    );
    let Some(SdkValue::List(holders)) = preview.get("holders") else {
        panic!("preview holders: {preview:?}");
    };
    assert_eq!(holders.len(), 2, "{preview:?}");
    assert_eq!(preview.get_text("action"), Some("preview"));
    assert_eq!(preview.get("op"), Some(&SdkValue::Null));
    assert_eq!(preview.get_text("audit"), Some("gc_intent"));
    let live_row = holders
        .iter()
        .find(|row| row.get_text("op") == Some(live_op.as_str()))
        .expect("the live holder");
    assert_eq!(live_row.get_text("state"), Some("live"));
    assert_eq!(live_row.get_text("machine_incarnation"), Some("worker:1"));
    assert_eq!(
        live_row.get_text("sandbox_generation"),
        Some("generation:1")
    );
    assert_eq!(live_row.get("legacy"), Some(&SdkValue::Bool(false)));
    assert!(matches!(
        live_row.get("lease_expires_ms"),
        Some(SdkValue::Int(_))
    ));
    let legacy_row = holders
        .iter()
        .find(|row| row.get_text("op") == Some(legacy_op.as_str()))
        .expect("the legacy holder");
    assert_eq!(legacy_row.get("legacy"), Some(&SdkValue::Bool(true)));
    assert_eq!(legacy_row.get("lease_expires_ms"), Some(&SdkValue::Null));

    let (code, message) = refused(
        &home,
        "store.repair_mount_holders",
        &repair("release", Some(&live_op), false),
    );
    assert_eq!(code, "Conflict", "{message}");
    // `legacy` may not touch a row with owner and place evidence.
    let (code, message) = refused(
        &home,
        "store.repair_mount_holders",
        &repair("settle", Some(&live_op), true),
    );
    assert_eq!(code, "InvalidInput", "{message}");

    ok(
        &home,
        "store.repair_mount_holders",
        &repair("settle", Some(&live_op), false),
    );
    let preview = ok(
        &home,
        "store.repair_mount_holders",
        &repair("preview", None, false),
    );
    let Some(SdkValue::List(holders)) = preview.get("holders") else {
        panic!("preview holders: {preview:?}");
    };
    let settled_row = holders
        .iter()
        .find(|row| row.get_text("op") == Some(live_op.as_str()))
        .expect("the settled holder");
    assert_eq!(settled_row.get_text("state"), Some("uncertain"));
    ok(
        &home,
        "store.repair_mount_holders",
        &repair("release", Some(&live_op), false),
    );

    let settled = ok(
        &home,
        "store.repair_mount_holders",
        &repair("settle_legacy", None, false),
    );
    assert_eq!(settled.get_int("settled"), Some(1));
    ok(
        &home,
        "store.repair_mount_holders",
        &repair("release", Some(&legacy_op), false),
    );
    let preview = ok(
        &home,
        "store.repair_mount_holders",
        &repair("preview", None, false),
    );
    assert!(
        matches!(preview.get("holders"), Some(SdkValue::List(rows)) if rows.is_empty()),
        "{preview:?}"
    );

    // Both releases retained their row as the durable operator audit, and
    // every preview retained its own done row: the release rows keep the op,
    // the preview rows are the operator action with no op. Admission still
    // filters every done row.
    let audit = ok(
        &home,
        "store.repair_mount_holders",
        &repair("audit", None, false),
    );
    let Some(SdkValue::List(rows)) = audit.get("items") else {
        panic!("audit items: {audit:?}");
    };
    let released: Vec<_> = rows
        .iter()
        .filter(|row| {
            row.get_text("evidence")
                .is_some_and(|evidence| evidence.starts_with("action=release;"))
        })
        .collect();
    assert_eq!(released.len(), 2, "{audit:?}");
    let previews: Vec<_> = rows
        .iter()
        .filter(|row| row.get_text("evidence") == Some("action=preview;operator=alice"))
        .collect();
    assert_eq!(previews.len(), 3, "{audit:?}");
    for row in &previews {
        assert_eq!(row.get("phase"), Some(&SdkValue::Null));
        assert_eq!(row.get_text("op").map(str::len), Some(32));
        assert_eq!(row.get_text("kind"), Some("mount"));
        assert_eq!(row.get_text("scope_kind"), Some("branch"));
    }
    let released = released
        .iter()
        .find(|row| row.get_text("op") == Some(live_op.as_str()))
        .expect("the released live op");
    assert_eq!(released.get_text("kind"), Some("mount"));
    assert_eq!(released.get_text("project"), Some("api"));
    assert_eq!(released.get_text("branch"), Some("main"));
    assert_eq!(released.get_text("machine"), Some("box"));
    assert_eq!(released.get_text("sandbox"), Some("box"));
    let evidence = released.get_text("evidence").expect("evidence");
    assert!(
        evidence.contains(&format!("action=release;operator=alice;op={live_op}")),
        "{evidence}"
    );
    assert!(matches!(audit.get("has_more"), Some(SdkValue::Bool(false))));

    // Paging is bounded by the call, not by the caller.
    let mut paged = repair("audit", None, false);
    paged.push(("limit", SdkValue::Int(i64::from(u32::MAX))));
    let paged = ok(&home, "store.repair_mount_holders", &paged);
    assert!(
        matches!(paged.get("limit"), Some(SdkValue::Int(limit)) if *limit == i64::from(layerfs_history::MAXIMUM_AUDIT_PAGE)),
        "{paged:?}"
    );

    // A refused call changes nothing.
    let (code, message) = refused(
        &home,
        "store.repair_mount_holders",
        &repair("inspect", None, false),
    );
    assert_eq!(code, "InvalidInput", "{message}");
    let (code, message) = refused(
        &home,
        "store.repair_mount_holders",
        &repair("settle", None, false),
    );
    assert_eq!(code, "InvalidInput", "{message}");
    let unknown = "99".repeat(16);
    let (code, message) = refused(
        &home,
        "store.repair_mount_holders",
        &repair("release", Some(&unknown), false),
    );
    assert_eq!(code, "NotFound", "{message}");

    std::fs::remove_dir_all(home).unwrap();
    let _ = std::fs::remove_dir_all(folder);
}

/// The bounded read of the Store's retained done rows, as the audit action
/// answers it.
fn audit_items(home: &Path) -> Vec<SdkValue> {
    let audit = ok(
        home,
        "store.repair_mount_holders",
        &[
            ("name", t("shop")),
            ("project", t("api")),
            ("branch", t("main")),
            ("action", t("audit")),
        ],
    );
    match audit.get("items") {
        Some(SdkValue::List(items)) => items.clone(),
        other => panic!("audit items: {other:?}"),
    }
}

/// `archive` exports the bounded retained done rows to
/// `<home>/log/gc-audit.jsonl`; export is the default, and `prune` deletes
/// exactly the exported rows. A live intent is not an exported row and stays.
#[test]
fn store_repair_archive_exports_and_prunes_only_the_done_pages() {
    let (home, folder) = project();
    let record = StoreRecord::read(&home, "shop").unwrap().unwrap();
    let open = OpenArgs::of_record(&home, "shop", &record).unwrap();
    let branch = branch_named(&open, "api", "main").unwrap();
    let stack = with_service(&open, |service| {
        Ok(lookup::project(&service.store, "api")?.id)
    })
    .unwrap();
    for tag in [0x41u8, 0x42, 0x43, 0x44] {
        let intent = GcIntent::shared(
            [tag; 16],
            GcIntentKind::Mount,
            GcScopeKind::Branch,
            branch.as_slice(),
        )
        .in_project(stack.as_slice())
        .named(Some("api"), Some("main"));
        with_service(&open, |service| {
            service.store.history().gc_register(&intent).unwrap();
            Ok(())
        })
        .unwrap();
    }
    // Three become the retained done audit; the fourth stays live.
    for tag in [0x41u8, 0x42, 0x43] {
        let evidence = format!(
            "action=release;operator=tool;op={}",
            format!("{tag:02x}").repeat(16)
        );
        with_service(&open, |service| {
            assert!(service
                .store
                .history()
                .gc_release_done(&[tag; 16], &evidence)
                .unwrap());
            Ok(())
        })
        .unwrap();
    }
    let archive = |prune: bool| {
        let mut fields = vec![
            ("name", t("shop")),
            ("project", t("api")),
            ("branch", t("main")),
            ("action", t("archive")),
            ("limit", SdkValue::Int(2)),
        ];
        if prune {
            fields.push(("prune", SdkValue::Bool(true)));
        }
        ok(&home, "store.repair_mount_holders", &fields)
    };

    let exported = archive(false);
    assert_eq!(exported.get_int("exported"), Some(3), "{exported:?}");
    assert_eq!(exported.get_int("pruned"), Some(0), "{exported:?}");
    let file = home.join("log/gc-audit.jsonl");
    assert_eq!(
        std::fs::read_to_string(&file).unwrap().lines().count(),
        3,
        "the export wrote one line per done row"
    );
    assert_eq!(audit_items(&home).len(), 3, "export keeps the rows");

    let pruned = archive(true);
    assert_eq!(pruned.get_int("exported"), Some(3), "{pruned:?}");
    assert_eq!(pruned.get_int("pruned"), Some(3), "{pruned:?}");
    assert_eq!(
        std::fs::read_to_string(&file).unwrap().lines().count(),
        6,
        "the second export appended the rows it pruned"
    );
    assert!(audit_items(&home).is_empty(), "the prune deleted them");
    let live = with_service(&open, |service| {
        Ok(service
            .store
            .history()
            .gc_intents(GcScopeKind::Branch, branch.as_slice())
            .unwrap()
            .len())
    })
    .unwrap();
    assert_eq!(live, 1, "the prune deleted no live intent");

    std::fs::remove_dir_all(home).unwrap();
    let _ = std::fs::remove_dir_all(folder);
}
