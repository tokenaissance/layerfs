// layerfs sandbox close: sandbox.close(sandbox, force?).

export default {
  args: ["sandbox"],
  options: { force: "bool" },
  summary: "stop a Sandbox and delete its container; --force discards its uncommitted Workspaces and kills all its processes",
  run: (lf, a, o) => lf.sandbox.close(a.sandbox, o.force),
};
