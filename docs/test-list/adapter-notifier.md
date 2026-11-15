# adapter/notifier.lua

Notifications to the user.

- [x] When notifying on Windows, the default notifier can show an OS notification with the terminal's name and state.
- [x] When notifying on macOS or Linux, the default notifier can show an OS notification with the terminal's name and state.
- [x] When the user sets a notifier, the notifier adapter can call it in place of the default.
- [x] When the OS notification fails, the notifier adapter can report the failure without stopping the plugin.
