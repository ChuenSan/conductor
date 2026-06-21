# Third Party Notices

## Ghostty Shell Integration

Conductor bundles Ghostty shell integration scripts so embedded terminals can
emit shell semantic markers such as current working directory, prompt, and
command completion metadata without requiring `/Applications/Ghostty.app`.

- Project: `ghostty-org/ghostty`
- URL: https://github.com/ghostty-org/ghostty/tree/main/src/shell-integration
- License: GPL-3.0-or-later

The vendored copy lives under `Vendor/ghostty-shell-integration/`; individual
files retain their upstream license headers. The full GPL-3.0 license text is
included at `docs/licenses/GPL-3.0.txt` and is copied into release app bundles
under `Contents/Resources/Legal/licenses/`.

## Skills Manager

Portions of the Skill Manager tool adapter model, default agent path table,
local skill scanner, installer, and sync semantics are adapted from:

- Project: `xingkongliang/skills-manager`
- URL: https://github.com/xingkongliang/skills-manager
- Commit reviewed: `b9c72b2`
- License: MIT

```text
MIT License

Copyright (c) 2026 Tianliang Zhang

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## CodexBar Provider Icons

Provider SVG icons and icon loading behavior are adapted from:

- Project: `steipete/CodexBar`
- URL: https://github.com/steipete/CodexBar
- License: MIT

Provider names and logos may be trademarks of their respective owners.

```text
MIT License

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
