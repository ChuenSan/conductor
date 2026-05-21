# Terminal Environment Variable Settings

## Goal

Add functional global environment variable settings that can be injected into newly created terminal processes.

## Requirements

- Persist global environment variables in preferences.
- Allow enabling/disabling injection for new terminals.
- Support adding, editing, deleting, enabling, disabling, and marking variables as sensitive.
- Provide quick templates for common developer variables.
- Inject enabled variables into new Ghostty terminal process environment.
- Merge with proxy environment values, with explicit environment variables taking precedence over proxy values for duplicate keys.
- Provide an injection preview and copyable shell `export` lines.

## Validation

- `swift build`
- `swift run ConductorModelCheck`
- `git diff --check`
- Rebuild and restart the local app.
