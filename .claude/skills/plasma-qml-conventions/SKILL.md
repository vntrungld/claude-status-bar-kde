---
name: plasma-qml-conventions
description: Use when editing QML under package/contents in this Plasma 6 plasmoid — covers PlasmoidItem structure, compact/full representations, popup expansion, config binding, and the executable DataSource polling pattern.
user-invocable: false
---

# Plasma 6 QML Conventions (this plasmoid)

## Overview

This applet targets Plasma 6 (`X-Plasma-API-Minimum-Version: 6.0`, Qt6/KF6). The
imports and root type differ from Plasma 5; getting them wrong makes the widget
fail to load with no visible error. These are the conventions the code already
follows — match them.

## Root component

- The root of `main.qml` is `PlasmoidItem` (from `org.kde.plasma.plasmoid`), NOT
  `Item` or the old `Plasmoid` type.
- Provide both `compactRepresentation` (panel) and `fullRepresentation` (popup).
  Pass shared state down as properties; don't reach up from the children.

## Popup expansion

- Toggle the popup via `root.expanded` (a `PlasmoidItem` property) — e.g.
  `onClicked: root.expanded = !root.expanded`. Do not invent a custom visibility
  flag; the panel manages the popup only through `expanded`.
- If the popup shows blank, the full representation needs a preferred size
  (`Layout.preferredWidth/Height` or implicit size) — the panel gives it none by
  default. (See commit history: "give popup a preferred size so it actually shows".)

## Config

- Config keys are declared in `config/main.xml` (`<kcfg>` / `<entry>`), surfaced by
  `config/config.qml`, and read at runtime as `plasmoid.configuration.<name>`
  (e.g. `plasmoid.configuration.showUsageOnPanel`). Adding a setting means editing
  all three, not just the UI.

## Polling external commands

- Shelling out uses `Plasma5Support.DataSource` with `engine: "executable"`
  (import `org.kde.plasma.plasma5support as Plasma5Support`).
- Pattern: keep `connectedSources: []`, call `connectSource(cmd)` to run, and in
  `onNewData` call `disconnectSource(source)` first so the same command can run
  again on the next tick. Parse `data["stdout"]`; on parse failure keep the
  previous value rather than clobbering state.
- The engine runs commands through `/bin/sh`, so `${XDG_DATA_HOME:-$HOME/.local/share}`
  in a command string is expanded by the shell — no manual env lookup in QML.
- Drive polling with a `Timer` (`triggeredOnStart: true`); gate optional pollers on
  a config flag via `running:` (see `usageTimer`).

## After editing QML

Changes under `package/` are cached — use the `/reload-plasmoid` skill to
re-register the package and restart plasmashell before checking the result.
