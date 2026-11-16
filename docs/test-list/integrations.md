# integrations.lua

Integration definitions, their helpers, and checking and installing them.

- [x] When an integration resolves its folder, `directory` can prefer the variable, fall back to the path, and give nil when the folder is missing.
- [x] When a hook command is built, `hook_command` can pass every script option and quote what the shell would read.
- [x] When hooks are installed, the `hooks` step can add its commands and keep the user's hooks and settings.
- [x] When the hook arguments change, the `hooks` step can report outdated and replace its old commands.
- [x] When a settings file is not JSON, the `hooks` step can fail with the file name.
- [x] When TOML keys are set, the `toml` step can add, insert or replace each key in its table.
- [x] When a terminal's program is identified, `identify` and `program` can prefer the agent's report, then the script an interpreter runs, then the program name.
- [x] When the user passes definitions, `resolve` can replace only the named fields, add new integrations and drop disabled ones.
- [x] When an integration is checked or installed, `status` and `install` can report its state, nil for an absent agent, and why an install did not take.
