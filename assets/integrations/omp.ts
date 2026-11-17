// Installed by herdr-core.nvim: labels the hc terminal with this omp session so it can be resumed.
import { spawn } from "node:child_process";

const started: string = {{start_command}};

function report(id: string | undefined): void {
  if (!id || !process.env.HC_TERMINAL_ID) return;
  try {
    const child = spawn(started, { shell: true, stdio: ["pipe", "ignore", "ignore"], windowsHide: true });
    child.on("error", () => {});
    child.stdin.on("error", () => {});
    child.stdin.end(JSON.stringify({ session_id: id }));
    child.unref();
  } catch {}
}

// The id, not the session file: a path is not typed into the shell when resuming.
function session(ctx: any): string | undefined {
  try {
    const id = ctx?.sessionManager?.getSessionId?.();
    if (typeof id === "string" && id) return id;
  } catch {}
}

export default function (pi: any) {
  // omp marks the shells it starts with OMPCODE=1, so an omp started inside one is not this terminal's.
  if (process.env.OMPCODE === "1") return;
  const activate = (_event: any, ctx: any) => {
    if (ctx?.hasUI !== true) return;
    report(session(ctx));
  };
  pi.on("session_start", activate);
  pi.on("session_switch", activate);
}
