// Installed by herdr-core.nvim: labels the hc terminal with this Kilo session so it can be resumed.
import { spawn } from "node:child_process";

const started = {{start_command}};
let reported;

function report(id) {
  if (!id || id === reported || !process.env.HC_TERMINAL_ID) return;
  reported = id;
  try {
    const child = spawn(started, { shell: true, stdio: ["pipe", "ignore", "ignore"], windowsHide: true });
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify({ session_id: id }));
    child.unref();
  } catch {}
}

export const HerdrCoreNvimPlugin = async () => ({
  event: async ({ event }) => {
    if (event?.type !== "session.created" && event?.type !== "session.updated") return;
    const properties = event.properties ?? {};
    // Subagents run in child sessions; only the root session is resumed.
    if (properties.info?.parentID) return;
    const id = properties.info?.id ?? properties.sessionID;
    if (typeof id === "string") report(id);
  },
});
