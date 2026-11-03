// sandbox.close: stops one Sandbox now, made by sandbox.create. Refused MountsActive while a Workspace is mounted in it and
// NoSuchSandbox when it is not running; stop, then delete, each once. `force` skips the mounted-Workspace refusal, stops
// the container (or deletes a stopped one) and deletes it, discarding uncommitted Workspaces and killing their processes.
import { invokeClient, sandboxArg } from "../client.js";
export function close(client, sandbox, force = false) {
  return invokeClient(client, "sandbox.close", { sandbox: sandboxArg(sandbox), force: force === true });
}
