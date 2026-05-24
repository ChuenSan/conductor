# Tactile UI Polish Design

## Goal

Improve Conductor's everyday feel by removing unfinished edges, reducing "AI-generated dashboard" surfaces, and tightening high-frequency panels without adding broad new features.

## Scope

This first polish pass targets visible, repeated surfaces:

- Shell chrome and sidebar edges, especially bottom-left settings affordance and panel-to-window joins.
- Command Center and contextual search overlays.
- Settings shortcut page, especially the oversized shortcut card shown in the user's example.
- File Manager tray interaction with overlays.

Out of scope for this pass:

- New product features.
- Reworking terminal rendering, Ghostty integration, or document preview engines.
- Large navigation model changes.
- Broad theme redesign across every color token.

## Design Principles

1. **Tool, not landing page.** Panels should feel like a native productivity tool: compact, scannable, and calm. Avoid large hero-like headings, large explanatory cards, and decorative empty space.
2. **Edges must resolve.** Floating surfaces that touch window edges should have intentional radius, clipping, and separators. No half-rounded corners or shadows that look pasted on.
3. **One active layer per region.** The right edge cannot host unrelated floating elements at the same time. File Manager, terminal search, and contextual popovers must have clear precedence.
4. **Controls should feel mechanical.** Icon buttons need stable size, hover, active, disabled, tooltip, and hit target behavior. Avoid text pills where an icon or standard control communicates the action better.
5. **Density with breathing room.** Increase information density by removing oversized cards, not by making controls cramped.

## Target Changes

### 1. Shell Edge Cleanup

The sidebar bottom-left settings button and adjacent window corner should read as one resolved piece of chrome. The bottom edge should not show a floating rounded card abruptly ending above the window boundary.

Expected direction:

- Audit sidebar container clipping and bottom action placement.
- Align bottom controls to the sidebar's visual bounds.
- Prefer a subtle separator or flush rail over a separate floating tile.
- Keep click targets stable and accessible.

### 2. Command Center Polish

Command Center should remain fast and keyboard-first, but feel less like a generic generated palette.

Expected direction:

- Keep the search field and list as the primary content.
- Reduce decorative header weight.
- Tighten row heights and section spacing.
- Preserve visible shortcuts, disabled explanations, keyboard navigation, and existing search behavior.

### 3. Settings Shortcut Page Redesign

The shortcut page should stop presenting a large framed card inside a large panel. It should look like a settings table or command reference pane.

Expected direction:

- Replace the oversized shortcut guide card with a flatter list/table surface.
- Reduce the top title/subtitle block size.
- Keep grouping by section, but avoid large repeated section headers.
- Keep shortcut chips readable but less pill-heavy.
- Ensure the list scrolls within a restrained region without looking like a card inside a card.

### 4. Overlay Precedence

Right-edge overlays should never overlap in a way that makes the app feel accidental.

Expected direction:

- File Manager has priority over terminal search.
- Opening file manager closes or hides terminal search.
- Search bars should focus correctly when shown and release focus when hidden.
- Add a small regression check for the intended state rule where practical.

## Implementation Constraints

- Performance first: do not introduce broad layout invalidations, expensive geometry readers, or large animated stacks.
- Avoid new shared abstractions unless two or more surfaces genuinely use the same behavior.
- Prefer small edits to existing SwiftUI views over a full rewrite.
- Keep animations subtle and use existing `ConductorMotion` and reduced-motion behavior.
- Keep the app usable in both light and dark themes.

## Verification

Required checks:

- `swift run --package-path Apps/Conductor ConductorModelCheck`
- `swift build --package-path Apps/Conductor --product Conductor`
- Manual visual check of:
  - sidebar bottom-left corner,
  - Command Center,
  - Settings > Commands/Shortcuts,
  - terminal search followed by File Manager,
  - light theme surface boundaries where available.

## Success Criteria

- The sidebar corner no longer looks clipped, pasted, or unresolved.
- Shortcut/settings content feels like a native tool pane rather than a generated card page.
- Command Center remains fast and keyboard-first with less visual bulk.
- Search and File Manager overlays do not collide.
- No large new feature surface is added.
