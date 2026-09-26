# Pianobar Pandora Widget for Omarchy Bar

Play Pandora from the Omarchy Quattro bar, the current Waybar-style bar in Omarchy. The widget manages pianobar in a detached tmux session: no extra terminal is needed. It shows a slowly scrolling song title, an on-click dropdown with the current and upcoming tracks, station switching, playback controls, and account setup. Right click opens the same running pianobar session in a terminal for its full command interface.

## Install

```sh
omarchy plugin add https://github.com/nicholasladwig/omarchy-pianobar-pandora-widget.git --enable
```

The plugin requires `pianobar`, `python3`, `tmux`, and `secret-tool`. On Omarchy, use `omarchy pkg add pianobar python tmux libsecret` for missing packages.

If you installed an earlier version:

```sh
omarchy plugin update io.github.nicholasladwig.pianobar-pandora-widget
```

## First use

1. Left click the music note to open the dropdown.
2. Click the account icon, enter your Pandora username and password, review the config changes, check the consent box, and click the check mark. This saves the password in the desktop Secret Service and starts pianobar in a detached tmux session. Your password does not appear in the plugin's config or process arguments.
3. If pianobar asks for an initial station, open the station list in the dropdown and select one. Later starts use pianobar's existing station configuration.

After you check the consent box and save your account, the plugin creates the control FIFO and sets `user`, `password_command`, `fifo`, and `event_command` in `~/.config/pianobar/config`. It preserves unrelated pianobar settings. Clicking Play later does not change the config. If that config already has a different `event_command`, setup stops with an error so you can arrange a wrapper for both hooks; it does not silently discard the previous hook. An existing plaintext `password` line is removed when you save an account through the widget.

The widget does not auto-start on login. Click Play in the dropdown when you want to start it. The detached session remains running when the dropdown closes. To quit pianobar, right click the widget and use `q` in its terminal.

## Controls

- Bar: music note only when idle; music note and a slowly scrolling artist and title while playing. Left click opens or closes the dropdown. Middle click pauses or resumes. Right click attaches a terminal to the same pianobar session.
- Dropdown: Play, save account, open terminal, pause or resume, next, love, ban, tired of song for a month, volume down or up, upcoming tracks, and station selection.
- Terminal: every pianobar command and prompt remains available, including creating and editing stations, bookmarks, history, and song details.

The GUI control keys follow pianobar's default key bindings. If you customized these bindings, update `ACTIONS` and the station command in `bridge.py` to match. Pianobar's FIFO accepts keypresses, not semantic commands.

## Data and security

The password is stored through `secret-tool` in your session's Secret Service collection. Pianobar's `password_command` retrieves it when pianobar starts. The username and other pianobar settings are in `~/.config/pianobar/config` with mode `0600` after account setup. The event bridge writes only song and station metadata to `$XDG_CACHE_HOME/io.github.nicholasladwig.pianobar-pandora-widget/state.json` (or `~/.cache/...`) with user-only permissions. The plugin never sends account data anywhere except to pianobar and the local Secret Service.

The plugin runs with your user permissions inside the Omarchy shell. Review the source before installation. It uses the normal pianobar process for Pandora traffic and no privileged commands.

## Troubleshooting

```sh
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nicholasladwig.pianobar-pandora-widget
omarchy plugin list --json
python3 ~/.config/omarchy/plugins/io.github.nicholasladwig.pianobar-pandora-widget/bridge.py status
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

If Play does not start music, check for an error in the dropdown. Choose a station if one is requested. If you previously started pianobar in another terminal, close that process before starting the widget-managed session. Right click to inspect pianobar's own output. If the secret store is locked, unlock it in your desktop session before saving the account or starting pianobar.

## Update and remove

```sh
omarchy plugin update io.github.nicholasladwig.pianobar-pandora-widget
omarchy plugin remove io.github.nicholasladwig.pianobar-pandora-widget
```

Before removal, quit pianobar from the right-click terminal, then remove the plugin's `event_command` and `password_command` lines from `~/.config/pianobar/config` if you do not want them retained. The Secret Service entry is keyed by application `io.github.nicholasladwig.pianobar-pandora-widget` and account username; remove it with `secret-tool clear application io.github.nicholasladwig.pianobar-pandora-widget account YOUR_USERNAME` if desired. Keep the FIFO if another tool uses it. Do not delete your whole pianobar config.

## Development and publication

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
python3 -m py_compile bridge.py
```

The [Omarchy development guide](https://plugins.omarchy.org/develop.html) defines the Quattro bar widget contract. The [publishing guide](https://plugins.omarchy.org/publish.html) requires a **public** GitHub repository before marketplace submission. This repository is public for marketplace submission. The submission category is Widgets; tags are Bar, Media, and Quickshell.

Pianobar's [remote control and event command interface](https://github.com/promyloph/pianobar) supplies the data and controls. Pandora is a trademark of Pandora Media; this project is independent and unaffiliated.
