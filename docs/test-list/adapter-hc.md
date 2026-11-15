# adapter/hc.lua

Calls to the `hc` CLI, turned into core events.

- [ ] When starting a terminal, the hc adapter can run `hc run --bg` with its folder, name and labels and return its address.
- [ ] When `hc ls --json` lists terminals, the hc adapter can turn each into a terminal event.
- [ ] When `hc events` prints a status, foreground, labels or exit change, the hc adapter can turn it into the matching event.
- [ ] When `hc events` prints a doc change, the hc adapter can turn it into a layout event with the new version.
- [ ] When `hc events` reports that events were missed, the hc adapter can ask for a fresh terminal list.
- [ ] When writing a label, the hc adapter can run `hc label` and report a failure as an event.
- [ ] When reading the layout, the hc adapter can return the doc's value and version.
- [ ] When writing the layout and another client wrote first, the hc adapter can report a conflict.
- [ ] When attaching to a terminal, the hc adapter can give the command line for `hc attach`.
- [ ] When a terminal runs on another machine, the hc adapter can address it as `<machine>/<address>`.
- [ ] When `hc` is missing or the core cannot start, the hc adapter can report why.
