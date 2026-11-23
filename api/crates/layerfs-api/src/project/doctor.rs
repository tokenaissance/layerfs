//! `project.doctor`: one project's Store mount holders, without repair.
use crate::calls::table::{a, call, Call, Kind::Project};
use crate::calls::Context;
use layerfs_bridge::control::SdkValue;
use layerfs_control::doctor::target::{DoctorRequest, DoctorTarget};
use layerfs_control::doctor::doctor_target;
use layerfs_home::outcome::Outcome;

pub(crate) const CALL: Call = call(
    "project",
    "doctor",
    &[a("project", Project)],
    &[],
    "check a project's Store for mount holders that block compaction",
    run,
);

fn run(context: &mut Context<'_>, args: &SdkValue) -> Outcome {
    let (home, _) = context.parts();
    let request = DoctorRequest {
        target: DoctorTarget::Project(args.get_text("project").unwrap_or("").to_owned()),
        timeout: None,
        quick: false,
        write_test: false,
        build: crate::home_family::build(),
    };
    doctor_target(home, &request)
}
