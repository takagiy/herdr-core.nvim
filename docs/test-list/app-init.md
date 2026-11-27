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
- [x] When the user presses New terminal, `setup` can offer the Neovim folder, home and this machine's spaces by path without duplicates, and start a shell in the chosen one.
- [x] When `picker` is set, `setup` can use it in place of the floating window and start nothing when it returns nil.
- [x] When `resources` holds a definition, `setup` can arm its monitor for each element its parent points at, list what it notifies there, and call its action with the item and its parent on the key.
- [x] When the plugin stops, `setup` can disarm the monitors.
- [x] When a terminal started another, `setup` can list the child under it and open it with Enter.
- [x] When `terminals` is given keys, `setup` can use them on the terminals in place of the usual ones.
- [x] When the user presses the rename key on a terminal, `setup` can ask for a name and label the terminal with it.
- [x] When `sidebar_keys` is still set, `setup` can tell the user where the keys go now.
- [x] When a resource cannot be used, `setup` can tell the user why and leave Neovim as it is.
- [x] When a terminal comes to the front, `setup` can give its row the background of the terminal in front, and take it away when a file comes to the front.
- [x] When the user chooses an action from the menu of a terminal, `setup` can run it on that terminal.
