// Installed by herdr-core.nvim: labels the hc terminal with this pi session so it can be resumed.
import { spawn } from "node:child_process";
import path from "node:path";

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

// The session file resumes from any folder; the id is the fallback.
function session(ctx: any): string | undefined {
  try {
    const file = ctx?.sessionManager?.getSessionFile?.();
    if (typeof file === "string" && (path.posix.isAbsolute(file) || path.win32.isAbsolute(file))) return file;
  } catch {}
  try {
    const id = ctx?.sessionManager?.getSessionId?.();
    if (typeof id === "string" && id) return id;
  } catch {}
}

export default function (pi: any) {
  pi.on("session_start", (_event: any, ctx: any) => {
    // Print, JSON and RPC modes have no terminal to resume in.
    if (ctx?.mode !== "tui") return;
    report(session(ctx));
  });
}
