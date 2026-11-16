# integrations.lua

Integration definitions, their helpers, and checking and installing them.

- [x] When an integration resolves its folder, `directory` can prefer the variable, fall back to the path, and give nil when the folder is missing.
- [x] When a hook command is built, `hook_command` can pass every script option and quote what the shell would read.
- [x] When hooks are installed, the `json` step can add its commands and keep the user's hooks and settings.
- [x] When the hook arguments change, the `json` step can report outdated and replace its old commands.
- [x] When an agent lays out its hooks differently, the `json` step can write the agent's own entry under another key or the top level, and set top-level fields.
- [x] When the other fields of its entry change, the `json` step can report outdated and replace the old entry.
- [x] When a settings file is not JSON, the `json` step can fail with the file name.
- [x] When an extension file is placed, the `template` step can fill in the hook commands, create its folders and report outdated when the content differs.
- [x] When `json` is given several files, it can leave them alone when one lists the value, and otherwise add it to the first file that exists, around the user's comments.
- [x] When `json` edits a settings file, it can keep the user's comments, layout and comma style, and change only its own old entries and the values it sets.
- [x] When opencode 2 has not yet migrated the old settings, the opencode integration can leave `cli.json` alone and still report installed.
- [x] When TOML keys are set, the `toml` step can add, insert or replace each key in its table.
- [x] When a terminal's program is identified, `identify` and `program` can prefer the agent's report, then the script an interpreter runs, then the program name.
- [x] When any built-in integration is installed into an empty agent folder, it can report installed afterwards.
- [x] When the user passes definitions, `resolve` can replace only the named fields, add new integrations and drop disabled ones.
- [x] When an integration is checked or installed, `status` and `install` can report its state, nil for an absent agent, and why an install did not take.
