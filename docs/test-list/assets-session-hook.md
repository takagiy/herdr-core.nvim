# assets/session-hook.lua

The script agents' hooks run with `nvim -l`.

- [x] When a conversation starts in an hc terminal, the hook can label the terminal with the integration and the conversation id.
- [x] When a conversation starts, the hook can also label the terminal's first process id, so a resume can tell a restarted terminal from an agent the user quit.
- [x] When a conversation ends, the hook can clear both labels.
- [x] When the payload names the id with another field, the hook can find it among the known field names.
- [x] When `--id` names fields, the hook can read only those, in order.
- [x] When `--id-env` names a set variable, the hook can take the id from it before the payload.
- [x] When `--parent-id-env` holds another conversation's id, the hook can leave the labels alone.
- [x] When it runs outside an hc terminal or gets no id, the hook can do nothing.
- [x] When `--reply` is given, the hook can return that text to print in every case.
