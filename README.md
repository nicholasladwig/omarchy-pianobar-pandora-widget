# Pianobar Pandora Widget for Omarchy Bar

A Pandora music widget for the **Omarchy Quattro bar** (Omarchy's current replacement for Waybar). It shows the current track and the next five songs, switches stations, and offers playback, rating, and volume controls. The full pianobar command-line interface stays available in the terminal where pianobar runs.

## Requirements

- Omarchy Quattro with the Omarchy shell plugin manager
- `pianobar` and `python3` (`omarchy pkg add pianobar python` on Omarchy)
- A Pandora account configured in pianobar; this plugin never reads or stores credentials

## Install from a private repository

Authenticate Git for the private repository first. Then:

```sh
omarchy plugin add git@github.com:nicholasladwig/omarchy-pianobar-pandora-widget.git --enable
```

The repository root is the plugin folder. The plugin ID is `io.github.nicholasladwig.pianobar-pandora-widget`.

## Connect pianobar

The widget needs pianobar's built-in `event_command` and control FIFO. Locate the installed plugin folder, generally `~/.config/omarchy/plugins/io.github.nicholasladwig.pianobar-pandora-widget`. Add these lines to `~/.config/pianobar/config`, using your actual home directory in `event_command` (pianobar does not expand `~` in a command path):

```ini
fifo = /home/YOUR_USER/.config/pianobar/ctl
event_command = /home/YOUR_USER/.config/omarchy/plugins/io.github.nicholasladwig.pianobar-pandora-widget/eventcmd
```

Create the FIFO once:

```sh
mkdir -p ~/.config/pianobar
mkfifo ~/.config/pianobar/ctl
```

If `ctl` already exists as a FIFO, keep it. Restart pianobar after changing its config. Start pianobar in a terminal; the widget connects to that running process. If you already use `event_command`, make a wrapper that invokes both your existing hook and this plugin's `eventcmd`, passing the original event name and stdin payload to each. Pianobar accepts only one `event_command` path.

The bar should discover the widget when enabled. Place it with:

```sh
omarchy bar move io.github.nicholasladwig.pianobar-pandora-widget --section right
```

## Controls

- Left click: open or close the panel. Middle click: pause or resume. Right click: next song.
- Panel: pause or resume, next song, love, ban, tired of song for a month, volume down or up.
- Station icon: show the station list; click a station to switch.
- Escape: close the panel. The panel includes the next five songs reported by pianobar.
- Advanced operations such as creating and editing stations, bookmarks, song history, and explanation remain available in the running pianobar terminal. Its original keybindings and prompts work normally.

The widget uses pianobar's default action bindings. If you changed `act_songpause`, `act_songnext`, `act_songlove`, `act_songban`, `act_songtired`, `act_voldown`, `act_volup`, `act_volreset`, or `act_stationchange`, update `ACTIONS` and the station command in `bridge.py` to match. Pianobar's FIFO receives keypresses, not semantic commands.

## Data and security

The event bridge writes song and station metadata to `$XDG_CACHE_HOME/io.github.nicholasladwig.pianobar-pandora-widget/state.json` (or `~/.cache/...`) with user-only permissions. It stores no Pandora password or audio. The widget reads this file every two seconds. The plugin runs with your user permissions inside the Omarchy shell; review the source before installation. Its only external program is Python, and it uses no privileged commands or network API of its own.

## Troubleshooting

```sh
omarchy plugin validate ~/.config/omarchy/plugins/io.github.nicholasladwig.pianobar-pandora-widget
omarchy plugin list --json
python3 ~/.config/omarchy/plugins/io.github.nicholasladwig.pianobar-pandora-widget/bridge.py status
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

If no track appears, verify `event_command`, restart pianobar, and wait for a new song or station selection. If controls fail, check that `~/.config/pianobar/ctl` is a FIFO and pianobar is running with the same config. Station switching uses pianobar's numeric station selection from the event-provided sorted list; customized station selection bindings need a matching bridge change.

## Update and remove

```sh
omarchy plugin update io.github.nicholasladwig.pianobar-pandora-widget
omarchy plugin remove io.github.nicholasladwig.pianobar-pandora-widget
```

Before removing, remove this plugin's `event_command` line from pianobar's config (or restore your prior event hook), then restart pianobar. You can remove its cache directory and FIFO if no other tool uses them. Do not delete your pianobar config or credentials.

## Development and publication

Validate changes with:

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml
python3 -m py_compile bridge.py
```

The [Omarchy development guide](https://plugins.omarchy.org/develop.html) defines the Quattro bar widget contract. The [publishing guide](https://plugins.omarchy.org/publish.html) requires a **public** GitHub repository before marketplace submission. This repository is private by request, so marketplace listing is deferred until its owner chooses to make it public. Its root manifest, README, license, and safe install and removal instructions are ready for that step.

Pianobar's [remote control and event command interface](https://github.com/promyloph/pianobar) supplies the data and controls. Pandora is a trademark of Pandora Media; this project is independent and unaffiliated.
