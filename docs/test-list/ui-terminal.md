# ui/terminal.lua

Terminal buffers in Neovim.

- [x] When a terminal is shown, its buffer can be named `herdr://<name>`, or `herdr://<address>` when it has no name.
- [x] When a terminal on another machine is shown, its buffer can be named `herdr://<machine>/<name or address>`.
- [x] When a `herdr://` buffer is opened, the buffer can run `hc attach` for that terminal.
- [x] When the cursor enters a terminal window, the window can switch to terminal mode.
- [x] When the user turns automatic terminal mode off, the window can stay in normal mode on entry.
- [x] When the buffer of a terminal window is wiped, the terminal's program can keep running in the core.
- [x] When a terminal URI already has a read buffer, attach can reuse that buffer without a duplicate name.
- [x] When a terminal is opened again while its attach is still running, the plugin can reuse that buffer.
- [x] When a terminal is opened again after its attach exited, the plugin can start a new attach in the windows that showed it.
