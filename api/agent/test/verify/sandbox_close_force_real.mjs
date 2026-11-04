// #539 E2E: `sandbox.close(sandbox, true)` recovers a Sandbox that an
// orphaned foreground exec keeps busy. Client A mounts, runs `sleep 30` in
// the foreground and is SIGKILLed; client B cannot unmount (Busy), cannot
// close normally (MountsActive), and force-closes the Sandbox. Then its
// container, records and number are gone, and the number is reused.
// Under the E2E launcher (its Store volume, home and deployment):
//   node api/agent/test/verify/sandbox_close_force_real.mjs inner
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { request } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const home = () => process.env.LAYERFS_HOME;
const t0 = Date.now();
const log = (line) => console.log(`[${((Date.now() - t0) / 1000).toFixed(2)}s] ${line}`);
const attempt = async (promise) => {
  try { return { value: await promise }; } catch (error) { return { error }; }
};
const detailProcesses = (error) => {
  const processes = error?.detail?.processes;
  return Array.isArray(processes) ? processes : [];
};

/** `GET /containers/json` through the Engine socket, for this run's prefix. */
function containers(all = true) {
  const filters = encodeURIComponent(JSON.stringify({ name: [process.env.LAYERFS_CONTAINER_PREFIX] }));
  return new Promise((resolve, reject) => {
    const call = request({ socketPath: process.env.LAYERFS_DOCKER, path: `/containers/json?all=${all ? 1 : 0}&filters=${filters}`, method: "GET" }, (answer) => {
      let body = "";
      answer.on("data", (chunk) => (body += chunk));
      answer.on("end", () => {
        let parsed;
        try { parsed = JSON.parse(body); } catch { return reject(new Error(`${answer.statusCode} ${body.slice(0, 200)}`)); }
        // the run's own client container shares the prefix; it is not a Sandbox
        resolve(parsed
          .map((item) => ({ name: item.Names?.[0]?.replace(/^\//, ""), state: item.State, id: item.Id.slice(0, 12) }))
          .filter((item) => !item.name.endsWith("-client")));
      });
    });
    call.on("error", reject);
    call.end();
  });
}

/** Client A: mount, start a foreground command, then die while it runs. */
async function child() {
  const { LayerFS } = await import("@layerfs/agent");
  const handoff = process.env.HANDOFF;
  const lf = await LayerFS.open(process.env.PROJECT);
  const ws = await lf.workspace.mount(process.env.SANDBOX, "lane");
  writeFileSync(join(handoff, "ws.json"), JSON.stringify(ws));
  lf.workspace.exec(ws, process.env.COMMAND).then(
    () => writeFileSync(join(handoff, "exec-ended"), "ended before the kill"),
    (error) => writeFileSync(join(handoff, "exec-ended"), String(error?.message ?? error)),
  );
  writeFileSync(join(handoff, "exec-started"), "started");
  await sleep(1200);
  process.kill(process.pid, "SIGKILL");
}

async function inner() {
  assert.ok(process.env.LAYERFS_HOME && process.env.LAYERFS_IMAGE, "the E2E launcher supplies the deployment");
  const { LayerFS } = await import("@layerfs/agent");
  const project = `cf-${Date.now().toString(36)}`;
  const source = mkdtempSync(join(tmpdir(), "layerfs-cf-"));
  writeFileSync(join(source, "README.md"), "close force\n");
  const handoff = mkdtempSync(join(tmpdir(), "layerfs-cf-handoff-"));
  let layerfs;
  try {
    layerfs = await LayerFS.init(project, source);
    rmSync(source, { recursive: true, force: true });
    await layerfs.branch.fork("lane");
    const own = await layerfs.sandbox.create();
    assert.deepEqual(own, { sandbox: "1", image: process.env.LAYERFS_IMAGE });
    log(`sandbox.create -> ${JSON.stringify(own)}; ${(await containers()).length} container(s)`);

    const childEnv = { ...process.env, PROJECT: project, SANDBOX: "1", HANDOFF: handoff, COMMAND: "sleep 30" };
    const a = spawn(process.execPath, [fileURLToPath(import.meta.url), "child"], { env: childEnv, stdio: "inherit" });
    const aExit = await new Promise((resolve) => a.on("exit", (status, signal) => resolve({ status, signal })));
    log(`client A exited: ${JSON.stringify(aExit)}; exec-ended marker: ${existsSync(join(handoff, "exec-ended")) ? readFileSync(join(handoff, "exec-ended"), "utf8") : "no"}`);
    assert.equal(aExit.signal, "SIGKILL", "client A was killed while its foreground exec ran");
    assert.ok(existsSync(join(handoff, "ws.json")), "client A mounted a Workspace");
    const ws = JSON.parse(readFileSync(join(handoff, "ws.json"), "utf8"));

    const b = await LayerFS.open(project);
    try {
      const listed = await b.sandbox.list_workspaces("1", 20);
      log(`sandbox.list_workspaces -> ${JSON.stringify(listed.items.map((x) => ({ path: x.path, activity: x.activity })))}`);

      const unmount = await attempt(b.workspace.unmount(ws));
      assert.ok(unmount.error, `an orphaned foreground exec keeps the Workspace Busy, got ${JSON.stringify(unmount.value)}`);
      log(`workspace.unmount -> ${unmount.error.code}: ${unmount.error.message}`);
      assert.equal(unmount.error.code, "Busy", unmount.error.message);

      const plain = await attempt(b.sandbox.close("1"));
      assert.ok(plain.error, `a mounted Workspace refuses a plain close, got ${JSON.stringify(plain.value)}`);
      log(`sandbox.close -> ${plain.error.code}: ${plain.error.message}`);
      assert.equal(plain.error.code, "MountsActive", plain.error.message);

      const forced = await attempt(b.sandbox.close("1", true));
      assert.ok(!forced.error, `sandbox.close("1", true) closes it: ${forced.error?.code} ${forced.error?.message}`);
      log(`sandbox.close(force) -> ${JSON.stringify(forced.value)}`);
      assert.deepEqual(forced.value, { kind: "Closed", sandbox: "1" });

      const still = await attempt(b.project.list_sandboxes());
      assert.deepEqual(still.value.items, [], "no Sandbox is left in the project");
      log(`project.list_sandboxes -> ${JSON.stringify(still.value.items)}`);

      for (const call of ["sandbox.list_workspaces", "workspace.mount"]) {
        const gone = await attempt(call === "sandbox.list_workspaces" ? b.sandbox.list_workspaces("1") : b.workspace.mount("1", "lane"));
        assert.equal(gone.error?.code, "NoSuchSandbox", `${call} refuses after close: ${gone.error?.code}`);
      }
      const directory = join(home(), project, "sandboxes", "1");
      assert.equal(existsSync(directory), false, `the Sandbox record is gone: ${directory}`);

      const left = await containers();
      assert.deepEqual(left, [], `the Sandbox container is gone, still: ${JSON.stringify(left)}`);
      log(`containers after close -> ${JSON.stringify(left)}`);

      const again = await b.sandbox.create();
      assert.deepEqual(again, { sandbox: "1", image: process.env.LAYERFS_IMAGE }, "the closed number is reused");
      log(`sandbox.create again -> ${JSON.stringify(again)}`);
      const reopened = await attempt(b.sandbox.close("1"));
      assert.deepEqual(reopened.value, { kind: "Closed", sandbox: "1" });
      assert.deepEqual(await attempt(b.project.list_sandboxes()).then((r) => r.value.items), []);
      log("close force: PASS");
    } finally {
      await b.close();
    }
  } finally {
    await layerfs?.close().catch(() => {});
    rmSync(handoff, { recursive: true, force: true });
  }
}

if (process.argv[2] === "child") await child();
else if (process.argv[2] === "inner") await inner();
else throw new Error("usage: sandbox_close_force_real.mjs inner (under tools/worktree.py run)");
