# E2E through the real hc

Follows the [scope and policy](../adr/e2e-with-real-hc.md) and the [toolchain](../adr/e2e-toolchain.md). Each nested item becomes one real test whose name matches it and whose comments carry Given/When/Then. An item gets `[x]` only after its test was seen failing and then passing. Items checked with several input methods run once per method.

Neovim, the plugin, hc, the Node.js dummy agent, the shell and the notification service are all real. Main operations go through keys and mouse input, not direct calls to internal functions or replaced communication. An echo of typed text does not count as input and output working; the test checks a reply that the program produced.

## Test runs

- Ordinary tests and E2E run separately.
  - [x] When hc is not on the PATH, `mise run test` can run only the ordinary tests.
  - [x] When `mise run test-e2e` runs, it can run only the E2E cases and fail when none are collected.
  - [x] When Neovim, hc or Node.js is missing, E2E can fail with the missing executable instead of skipping.

- E2E runs in its own environment and cleans up after success and failure.
  - [x] When E2E runs next to another hc session, it can leave that session's terminals, settings and saved layout unchanged.
  - [x] When E2E ends by success, failure or timeout, it can stop only the processes it started.

## Starting and reattaching terminals

- Talk to the dummy agent and keep using it after its window closes.
  - [x] When the user types into a dummy agent opened from the sidebar, Neovim can show the agent's reply through a real attach.
  - [x] When the terminal buffer is wiped and the agent is opened again from the sidebar, the plugin can reattach to the same agent.
  - [x] When Neovim exits and a new Neovim starts the plugin, the plugin can reattach to the same agent.
  - [x] When the dummy agent exits, the plugin can close only the windows that showed it.

- Start real shells from the plugin.
  - [x] When the user presses the keys for a new terminal in a tab, a vertical split and a horizontal split, the plugin can open a working shell in each place.
  - [x] When a new shell is opened from a terminal window, it can start in that terminal's current folder, including folders with spaces and Japanese names.
  - [x] When a new shell is opened from a file window, it can start in Neovim's current folder.
  - [x] When a new shell is opened from a space heading with `n` or a click on `+`, it can start in that space's folder.

## Sidebar

- Open a terminal from the list.
  - [x] When the user chooses a terminal already shown in another tab, the plugin can move to its window without opening another.
  - [x] When the user chooses a terminal that no window shows, the plugin can open it in a new tab where the user can type into it.
  - [x] When the user opens a `herdr://` URI directly, the plugin can attach that buffer to the terminal without a duplicate buffer name error.

- Name and pin a terminal, then open Neovim again.
  - [x] When the user names a terminal with `r`, the plugin can write the `herdr-core-nvim.name` label and show the name in the sidebar while the `herdr://` buffer name stays the same.
  - [x] When the user presses `p` twice on a terminal, the plugin can pin it and unpin it in the `herdr.pinned` label and the sidebar.
  - [x] When Neovim restarts, the sidebar can show the names and pins stored in hc.

- Fold the list and open it again.
  - [x] When the user folds and unfolds a space heading with Enter or a click, the sidebar can hide and show its terminal rows while the terminals keep running.
  - [x] When the user clicks `«` and then `»`, the sidebar can collapse to a strip and expand again without changing the terminal windows.

## Spaces

- Group terminals by the folder they run in.
  - [x] When a program starts in a subfolder of a git repository, the plugin can put it in the repository root's space.
  - [x] When a program starts outside any git repository, the plugin can put it in its start folder's space.
  - [x] When the user moves a shell into another repository with `cd`, the plugin can move it to that repository's space.
  - [x] When one of two terminals in the same tab moves to another repository, the plugin can change only that terminal's space.

## Saving and restoring the layout

- Change the layout and start Neovim again.
  - [x] When Neovim restarts, the plugin can restore the tab order, the splits and the terminal in each window.
  - [x] When a window was closed before Neovim restarted, the plugin can leave it closed while its terminal keeps running in hc.
  - [x] When Neovim starts with a file, the plugin can restore the saved layout and keep the file's window.

## Several Neovims

- Connect two Neovims to the same E2E hc environment.
  - [x] When one Neovim names or pins a terminal, the other Neovim's sidebar can show the change.
  - [x] When one Neovim adds a tab or split or closes a terminal window, the other Neovim can reach the same layout without bringing the closed window back.
  - [x] When a second Neovim starts with an empty screen, it can restore the saved layout without overwriting it.
  - [x] When one Neovim moves focus or collapses its sidebar, the other Neovim can keep its own focus and sidebar.

## Status, unread and notifications

- Send real status reports from the dummy agent.
  - [x] When the dummy agent reports `working`, `blocked` and `done` with OSC 7501, hc and the sidebar can show each status.
  - [x] When a terminal nobody looks at becomes blocked or done, the plugin can run the OS notification command successfully, and on Linux dunst can log it.
  - [x] When a terminal shown in the focused Neovim becomes blocked or done, the plugin can update the sidebar without a notification.
  - [x] When the user opens a done terminal in the focused Neovim, both Neovims can show it as read through `herdr.seen`.
  - [x] When the user presses `u` on a read done terminal, the plugin can mark it unread in its label and the sidebar.

## CI and failure records

These items check the CI workflow and its runs rather than Lua behavior.

- Run E2E on Linux with the pinned hc, daily and on pull requests.
  - [x] When the E2E workflow is read, it can be scheduled daily around 6:00 in Japan (21:00 UTC) and started by hand.
  - [ ] When CI runs on Linux, it can verify the SHA-256 of the hc version in `mise.toml`, run every case with that version and record the version.
  - [ ] When Renovate proposes a newer hc version, CI can run the E2E on that pull request with the new version.
  - [ ] When the workflow is started by hand with an hc version, CI can run the E2E with that version instead.
  - [x] When a downloaded release does not match its checksum, the installer can fail without running the extracted hc.
  - [x] When a case fails or times out in CI, the run can keep the case name, screen, messages and hc state and logs as an artifact and still clean up.

## Optional

Decided after the main paths are done, by value and complexity.

- Keep a trace of operations and screens.
  - [ ] When a traced case fails, CI can provide the operations, times and screens in order.

## Out of scope

Remote machines, real Claude Code and Codex authentication and model replies, notifications appearing on a real desktop, exact screen matches, and videos or replay viewers.
