// Installed by herdr-core.nvim: labels the hc terminal with the opencode session it shows so it can be resumed.
import { spawn } from "node:child_process";

const started = {{start_command}};
let reported;

function report(id) {
  if (!id || id === reported) return;
  reported = id;
  try {
    const child = spawn(started, { shell: true, stdio: ["pipe", "ignore", "ignore"], windowsHide: true });
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify({ session_id: id }));
    child.unref();
  } catch {}
}

// Subagents run in child sessions; the root is the conversation to resume. Unknown sessions wait for the next look.
function root(id, lookup) {
  const seen = new Set();
  while (typeof id === "string" && !seen.has(id)) {
    seen.add(id);
    const session = lookup(id);
    if (!session) return;
    if (!session.parentID) return id;
    id = session.parentID;
  }
}

// The TUI has no event for switching sessions, so the route is read twice a second.
function watch(current, lookup) {
  if (!process.env.HC_TERMINAL_ID) return;
  const timer = setInterval(() => {
    try {
      report(root(current(), lookup));
    } catch {}
  }, 500);
  timer.unref?.();
}

// opencode 1 calls `tui`, opencode 2 calls `setup`.
export default {
  id: "herdr-core-nvim.session",
  tui: async (api) =>
    watch(
      () => (api.route.current?.name === "session" ? api.route.current.params?.sessionID : undefined),
      (id) => api.state.session.get(id),
    ),
  setup: (api) =>
    watch(
      () => {
        const route = api.ui.router.current();
        return route?.type === "session" ? route.sessionID : undefined;
      },
      (id) => api.data.session.get(id),
    ),
};
