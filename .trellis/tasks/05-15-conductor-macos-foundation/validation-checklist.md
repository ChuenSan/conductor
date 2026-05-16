# Conductor Foundation Validation Checklist

Use this checklist for the next human pass. Automated checks prove model and smoke routes;
human validation still matters for real Ghostty/AppKit interaction.

## Automated Checks

Run:

```bash
cd Apps/Conductor
./Scripts/check-conductor.sh
```

Expected smoke output:

```text
status=ok
panes=2
terminals=2
zoomed=false
```

The full check prepares GhosttyKit, builds the SwiftPM executable, runs model checks,
runs app smoke automation, runs long-output stress automation, verifies rapid tab and
complex workspace model stress, verifies both outputs,
builds `.build/Conductor.app`, validates Trellis context, verifies automation did not
modify persisted user state, and fails if a Conductor process is left behind.

For manual validation, build the clickable bundle:

```bash
cd Apps/Conductor
./Scripts/build-app-bundle.sh
open .build/Conductor.app
```

## Manual Validation

### Terminal Tabs

- Open the command palette with `Cmd-K` and run basic pane/tab commands.
- Create five tabs in one pane with `Cmd-T` or the toolbar.
- Run a different command in each tab, such as `echo tab-1`, `echo tab-2`.
- Switch tabs by clicking.
- Switch tabs with `Cmd-[` and `Cmd-]`.
- Confirm terminal contents actually change with the selected tab.
- Close inactive, active, first, middle, and last tabs.
- Move selected tabs with `Cmd-Shift-,` and `Cmd-Shift-.`.
- Use tab context menus to close other tabs and close tabs to the right.
- Use `Cmd-Option-M` or the tab context menu to move a tab to the next pane.
- Use `Cmd-Option-Shift-M` or the tab context menu to move a tab to a new split.
- Drag tabs inside one pane and across panes, including dropping at the end of a tab strip.
- Confirm closing the only terminal creates a replacement shell.

### Panes / Splits

- Split right with toolbar and `Cmd-D`.
- Split down with toolbar and `Cmd-Shift-D`.
- Confirm repeated splitting stops before panes become useless.
- Drag horizontal and vertical split dividers.
- Use `Cmd-Shift-=` or toolbar `均分` to equalize.
- Use `Cmd-Z` or toolbar `放大` / `还原` to toggle focused pane zoom.
- Use `Cmd-Option-Arrow` to move focus across panes.
- Use `Cmd-Shift-Arrow` to resize the focused split.
- Close panes with the pane close button.
- Confirm nested split trees collapse without blank regions.

### Focus

- Click each pane and type; input should go to the visually active terminal.
- Switch tabs, then type; input should go to the newly selected terminal.
- Close the focused tab and type; input should go to the selected replacement/survivor.
- Use pane focus shortcuts and confirm active chrome follows.

### Ghostty Behavior

- Paste multiline text.
- Use Ctrl-C / Ctrl-D in a shell.
- Run a long output command: `yes conductor | head -10000`.
- Run `./Scripts/stress-conductor.sh` for the automated long-output route.
- Confirm terminal output stays inside Ghostty and UI chrome remains responsive.
- Change title from shell if available and confirm tab title updates.
- Trigger working-directory changes and confirm the status bar shows the focused cwd.
- Trigger OSC desktop notifications and confirm compact unread metadata appears without rendering transcript in SwiftUI.
- Trigger progress, command-finished, search, and readonly states when available and confirm status bar metadata updates.
- Confirm startup-sensitive Ghostty actions such as cell size, color/config changes, and bell are not claimed as handled yet; these need a dedicated lifecycle validation pass before Conductor returns them as handled.
- Open the native menu bar commands and confirm invalid commands are disabled.

### Known Follow-Up Areas

- Directional pane focus now prefers split-tree geometry, but should eventually become
  fully frame/position-aware for complex uneven layouts.
- Resize split actions are mapped to split fractions, but should be tuned against Ghostty's
  expected amount semantics during manual shortcut testing.
- Workspace model and theme persistence are implemented. Process/session restoration is not.
