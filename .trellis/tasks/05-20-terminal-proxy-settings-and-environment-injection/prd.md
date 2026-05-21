# Terminal Proxy Settings And Environment Injection

## Goal

Add functional proxy settings under Settings and inject enabled proxy values into newly created terminal processes.

## Requirements

- Persist proxy settings in appearance/preferences storage.
- Support HTTP, HTTPS, ALL/SOCKS, and NO_PROXY values.
- Allow enabling/disabling injection for new terminals.
- Provide a settings panel section for proxy controls.
- Inject both uppercase and lowercase proxy environment variables into Ghostty surface process environment.
- Keep existing Conductor terminal hook environment variables.
- Make clear that proxy changes apply to newly created terminal processes.

## Validation

- `swift build`
- `swift run ConductorModelCheck`
- `git diff --check`
- Rebuild and restart the local app.
