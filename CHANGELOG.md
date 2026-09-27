# Changelog

## 1.5.0

- Replaced the one-second status subprocess with watched local state, an in-process clock, and low-rate environment checks.
- Fetches tmux output only while the Advanced panel is open.
- Uses clipped scene-graph scrolling and supports icon-only vertical bars.
- Restored Stop playback, shows package names before Polkit installation, and warns about Advanced command secrets.
- Prevents account setup from replacing an existing unreadable Pianobar config.
- Adds locked state updates, tolerant event number parsing, complete FIFO writes, and a shared JavaScript model.

## 1.4.12

- Refreshed the published player preview.

## 1.4.11

- Uses player action wording in control feedback.

## 1.4.10

- Added action feedback in the player panel.

## 1.4.9

- Placed Stations and Advanced controls side by side.

## 1.4.1–1.4.8

- Added the initial self-contained player, account storage, timing settings, station and Advanced views, version indicator, and theme support.
