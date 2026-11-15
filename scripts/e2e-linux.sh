#!/usr/bin/env bash
# Runs the E2E on Linux with a real notification service. CI and `mise run test-e2e-linux` (Docker) both use it.
set -euo pipefail
sudo=""
[ "$(id -u)" = 0 ] || sudo=sudo
$sudo apt-get update -qq
$sudo env DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y -qq \
    ca-certificates curl git xz-utils dbus xvfb xauth dunst libnotify-bin >/dev/null
if ! command -v mise >/dev/null; then
    curl -fsSL https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
fi
mise trust --quiet
mise install
eval "$(mise env -s bash)"
export HERDR_E2E_ARTIFACTS="${HERDR_E2E_ARTIFACTS:-$PWD/artifacts/e2e}"
export HERDR_E2E_DUNST_LOG="$HERDR_E2E_ARTIFACTS/dunst.log"
mkdir -p "$HERDR_E2E_ARTIFACTS"
hc_dir="$(mktemp -d)/hc"
node scripts/install-hc.mjs "$hc_dir" "${HC_VERSION:-}" | tee "$HERDR_E2E_ARTIFACTS/installer.log"
export PATH="$hc_dir/bin:$PATH"
hc --version | tee "$HERDR_E2E_ARTIFACTS/hc-version.txt"
dbus-run-session -- xvfb-run -a bash -euo pipefail -c '
    dunst --print > "$HERDR_E2E_DUNST_LOG" 2>&1 &
    trap "kill $! 2>/dev/null || true" EXIT
    mise run test-e2e
'
