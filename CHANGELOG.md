# Changelog

## 1.5.3

- Removed the privileged package-installation action so Marketplace standard installation can apply. Missing dependencies are reported without requesting elevation.

## 1.5.2

- Rechecks the live terminal prompt inside the helper immediately before it reads or sends Advanced text, closing the UI refresh race for password prompts.

## 1.5.1

- Blocks every Advanced input path when a password prompt is detected and directs the user to Edit Account, so credentials cannot reach tmux arguments or scrollback.

## 1.5.0

- Replaced the one-second status subprocess with watched local state, an in-process clock, and low-rate environment checks.
- Fetches tmux output only while the Advanced panel is open.
- Uses clipped scene-graph scrolling and supports icon-only vertical bars.
- Restored Stop playback, reports missing packages, and warns about Advanced command secrets.
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
