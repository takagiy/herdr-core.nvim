# adapter/hc.lua

Calls to the `hc` CLI, turned into core events.

- [x] When starting a terminal, the hc adapter can call `terminal.run` with its folder, name and labels, keep it, clear agent identity variables and return its address.
- [x] When typing into a terminal or setting several labels, the hc adapter can run `hc send` or one `hc label`.
- [x] When hc reports the foreground arguments or the agent's own name, the hc adapter can keep them on the terminal.
- [x] When `hc ls --json` lists terminals, the hc adapter can turn each into a terminal event.
- [x] When `hc events` prints a status, foreground, labels or exit change, the hc adapter can turn it into the matching event.
- [x] When `hc events` prints a doc change, the hc adapter can read the doc through `hc connect` and return a layout event with its value and version.
- [x] When `hc events` reports that events were missed, the hc adapter can apply the fresh snapshot in that notification and refetch the layout without racing another terminal-list request.
- [x] When writing a label, the hc adapter can run `hc label` and report a failure as an event.
- [x] When reading the layout, the hc adapter can return the doc's value and version.
- [x] When hc lists a terminal another one started, the hc adapter can keep its parent's address, with the machine for a remote one.
- [x] When some tabs of the saved layout are broken, the hc adapter can drop only those tabs and return the rest.
- [x] When writing the layout and another client wrote first, the hc adapter can report a conflict.
- [x] When attaching to a terminal, the hc adapter can give the command line for `hc attach`.
- [x] When a terminal runs on another machine, the hc adapter can address it as `<machine>/<address>`.
- [x] When `hc` is missing or the core cannot start, the hc adapter can report why.
- [x] When hc reports the same folder with backslashes in one place and slashes in another, the hc adapter can report both as the same folder.
- [x] When the event stream closes, the hc adapter can report that it closed.

- [x] 終了済みターミナルを初期一覧と再同期の一覧から除外する。
- [x] 終了済みターミナルのラベルが変わっても一覧に復活させない。
