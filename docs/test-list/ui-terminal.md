# ui/terminal.lua

Terminal buffers in Neovim.

- [ ] When a terminal is shown, its buffer can be named `herdr://<name>`, or `herdr://<address>` when it has no name.
- [ ] When a terminal on another machine is shown, its buffer can be named `herdr://<machine>/<name or address>`.
- [ ] When a `herdr://` buffer is opened, the buffer can run `hc attach` for that terminal.
- [ ] When the cursor enters a terminal window, the window can switch to terminal mode.
- [ ] When the user turns automatic terminal mode off, the window can stay in normal mode on entry.
- [ ] When the buffer of a terminal window is wiped, the terminal's program can keep running in the core.
