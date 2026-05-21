# Replace Environment Settings With Shell Startup Settings

## Goal

Remove the just-added global environment variable settings and replace them with a more concrete Shell Startup settings feature that affects newly created terminal processes.

## Requirements

- Remove the Settings > Environment page, environment variable preference model, and injection logic.
- Add Shell Startup settings under Settings:
  - default shell preset: zsh, bash, fish, login shell, custom
  - custom shell path
  - launch as login shell
  - optional startup command
- New terminal processes must use the configured shell command.
- Preserve Conductor hook environment and proxy injection.
- Make it clear changes apply to newly created terminals.

## Validation

- `swift build`
- `swift run ConductorModelCheck`
- `git diff --check`
- Rebuild and restart the local app.
