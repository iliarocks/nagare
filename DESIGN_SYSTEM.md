# Nagare interaction and visual system

Nagare should feel quiet, direct, and local-first on every device. Platform
controls may adapt to iPhone or Mac, but the meaning of an interaction should
not change with the device.

## Visual hierarchy

- Navigation and selection use a hierarchy of neutral black, white, and gray.
  Neutral navigation styling is scoped to navigation itself; destructive
  actions remain red and other semantic actions keep their distinct meaning.
- Content leads; chrome recedes. Materials, shadows, and rounded surfaces are
  used for temporary layers, not as decoration on every row.
- Item rows use one shared rhythm: a full-width hit target, comfortable
  vertical padding, and a neutral grouped background for adjacent selections.

## Interaction hierarchy

- The visible row is the primary target. Small trailing controls may perform a
  distinct action, but whitespace never becomes inert.
- Creation is the only flow that requests focus automatically. Opening an
  existing document preserves the user's focus and selection.
- Autosaved overlays dismiss with Escape or a click on the backdrop. A
  successful single-choice action, such as choosing a date or project, also
  dismisses immediately. Multi-field editors remain open so related values can
  be changed together.
- Destructive actions remain explicit and use platform-standard confirmation
  or destructive roles.

## Layout and motion

- Temporary desktop surfaces share one material, 18-point continuous corners,
  a subtle separator, and the same short scale-and-fade transition.
- Scrollable document content fades into the bottom edge instead of ending at
  a hard padding boundary.
- Motion confirms a state change; it should not delay input or navigation.

## Lifecycle and feedback

- App-wide work such as day roll-forward, imports, and sync reconciliation is
  owned by the root scene lifecycle, never by whichever page happens to mount.
- Autosave is the default. UI copy and dismissal behavior must not imply that a
  separate Save action is required.
- iCloud preference changes apply immediately by rebuilding the data session
  around the same local store. “Sync Now” reconciles changes already delivered
  to the device; network delivery remains controlled by iCloud.

New UI should reuse the primitives in `PlatformViewModifiers.swift` before
adding screen-specific styling or presentation behavior.
