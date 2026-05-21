# Fix renderable file performance

## Goal

HTML and other renderable files should open and preview without making Conductor feel stuck. Files that macOS can render natively should use an AppKit-backed preview surface instead of flowing through SwiftUI text previews or the CodeEdit source editor by default.

## What I Already Know

- The user reports that HTML is still very laggy after the md/log performance pass.
- The previous pass bounded text previews and routes larger text files into the AppKit large-text viewer, but `.html`/`.htm` are still classified as source/text in several paths.
- The file manager and workspace file surfaces are terminal-adjacent tool UI; they must not push large or render-heavy content into SwiftUI state.
- The app already uses AppKit bridges for expensive runtime surfaces.

## Requirements

- Route HTML-like files (`html`, `htm`, `xhtml`, `webarchive`) to a native render preview instead of CodeEdit/source text by default.
- Route other macOS-renderable file types such as PDF, SVG, common audio/video, and common office/iWork files to the same in-app preview surface where practical.
- Keep image files on the existing image preview path.
- Keep markdown on the existing markdown/large-text paths.
- Preserve bounded text preview for small text/source files that are not better treated as renderable.
- File manager selection preview and workspace file tabs must share the same renderable classification so behavior is predictable.
- Do not read full renderable file contents into SwiftUI just to preview them.

## Acceptance Criteria

- Opening an `.html`/`.htm` file from the file manager opens an in-app rendered preview and does not instantiate the CodeEdit source editor.
- Selecting `.html` in the file manager previews via an AppKit native preview surface, not `FileManagerSourcePreview`.
- PDF/SVG/common media and document formats show an in-app native preview where macOS Quick Look can render them.
- `./Scripts/check-conductor.sh` passes from `Apps/Conductor`.

## Out Of Scope

- Building a full HTML DOM inspector or browser developer tools.
- Editing rendered HTML in place.
- Replacing the existing Markdown editor/preview.

## Technical Notes

- Likely files:
  - `Apps/Conductor/Sources/Conductor/UI/ConductorFileWorkspaceView.swift`
  - `Apps/Conductor/Sources/Conductor/UI/FileManagerPanel.swift`
  - a small reusable AppKit preview representable if no existing Quick Look wrapper exists.
