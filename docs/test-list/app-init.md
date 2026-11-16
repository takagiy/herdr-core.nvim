# app/init.lua

Starting the plugin.

- [x] When `setup` runs, the plugin can start following the core's events, show the saved layout and open the sidebar.
- [x] When Neovim is started with a file or by another program, the plugin can still show the saved layout.
- [x] When `hc` is missing, `setup` can tell the user and leave Neovim as it is.
- [x] When local windows change before the initial layout arrives, setup can leave the stored layout untouched.
- [x] When cleanup is called repeatedly before setup runs again, the plugin can stop safely and restart.
- [x] When a shell is created through hc, the plugin can show it in the requested placement.
- [x] When restoration completes through the event subscription, local window changes can be saved afterward.
- [x] When a terminal keeps a conversation whose agent is gone, `setup` can clear its labels and type the integration's resume command once.
- [x] When an installed agent lacks its hook, `setup` can show the Setup panel with that integration.
- [x] When the user presses New terminal, `setup` can offer the Neovim folder, home and this machine's spaces without duplicates, and start a shell in the chosen one.
- [x] When `picker` is set, `setup` can use it in place of the floating window and start nothing when it returns nil.
