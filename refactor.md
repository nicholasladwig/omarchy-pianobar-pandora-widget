# Refactor plan — omarchy-pianobar-pandora-widget

Repo: `nicholasladwig/omarchy-pianobar-pandora-widget` (branch `main`, v1.4.12, working tree clean)
Reviewed against: Omarchy shell at `/usr/share/omarchy/shell`, pianobar 2024.12.21, Python 3.14.7, one monitor.
All numbers below were measured on this machine on 2026-09-26, with the widget's pianobar session live.

---

## 1. Verdict

**The architecture is right and it already matches the first-party Omarchy pattern.** Keep it. There is
exactly one thing wrong at the design level — the widget asks a Python process for the answer once per
second, forever — and it is costing about 4% of a CPU core continuously. Everything else on this list is
small.

**Do not rewrite it in another language.** Section 7 has the measured reasoning. In short: the per-call
cost of Python is ~40 ms, and the fix is to stop making ~86,400 calls a day, not to make each call 38 ms
cheaper. A compiled helper would also have to be distributed as a committed binary, because
`omarchy plugin add` only clones and enables — there is no build step — and no plugin on this system ships
a binary.

Priorities, in order of value per line changed:

| # | Change | Why | Effort |
|---|---|---|---|
| 1 | Stop polling `bridge.py status` at 1 Hz; read `state.json` from QML | ~150 s CPU/hour → ~7 s CPU/hour | ~1 day |
| 2 | Stop capturing the tmux pane when the Advanced view is closed | 2 subprocesses/s + up to 7 KB/s of dead payload | 1 hour |
| 3 | Vertical-bar support (`bar.vertical`) | Required by the bar contract; currently broken on left/right bars | 30 min |
| 4 | Replace the character-math ticker with the `omarchy.media` clip+animation pattern | Deletes ~15 lines, correct with proportional fonts, no per-tick JS | 1 hour |
| 5 | Move pure logic into `Model.js` | Every other plugin has one; makes the math testable | 2 hours |
| 6 | Small correctness/security/doc fixes (§5, §6) | Each is 1–10 lines | 2 hours |

---

## 2. Measurements

Per invocation, averaged over 20 runs, with the managed tmux session running:

| Path | Wall | CPU |
|---|---|---|
| `python3 bridge.py status` (what the widget calls every second) | 42 ms | ~41 ms |
| Python interpreter start (`python3 -c pass`) | 10.4 ms | — |
| The module imports at the top of `bridge.py` | 30.7 ms | — |
| `tmux has-session` | 2.2 ms | — |
| `tmux list-panes` + `capture-pane -S -35` | 5.1 ms | — |
| `status` JSON payload | 3,204 bytes (851 of them `console`, cap 7,000) | — |

Extrapolated at the current 1 Hz, per bar instance (one per monitor):

- **86,400 `python3` spawns per day**, each spawning 1–3 `tmux` children → **~250,000 processes/day**.
- **~150 s of CPU per hour ≈ 4.1% of one core**, whether or not anything is playing, whether or not an
  account is configured, and whether or not the panel is open.

For scale, the polling rates of every other widget installed here:

| Widget | Interval | What it spawns |
|---|---|---|
| `limehawk.vpn` | 5 s | one script |
| `nick.agents` | 30 s | one script |
| `io.github.olivoil.hurricane-tracker` | minutes | HTTP |
| `nick.tray` | 250 ms | nothing (in-process) |
| **this widget** | **1 s** | **`python3` + up to 3 `tmux`** |

The 1 s timers elsewhere are debounces and clock ticks, not process spawns. This widget is the most
expensive poller on the machine by roughly 5–40×.

---

## 3. What is already correct (do not churn it)

Verified by reading the shell source, not assumed:

- `omarchy plugin validate .` exits 0. `qmllint -I $OMARCHY_PATH/shell BarWidget.qml Panel.qml` is clean.
  `python3 -m py_compile bridge.py` is clean.
- The `BarWidget.qml` + `Loader{Panel.qml}` + `injectPanel()` shape is **exactly** what first-party
  `omarchy.clock` does (`plugins/panels/clock/BarWidget.qml:97`). It is not a deviation.
- `open()` / `close()` / `opened` on the widget root satisfy `Bar.findPanelWidget`
  (`plugins/bar/Bar.qml:735`), so `omarchy-shell shell summon <id>` routes correctly.
- `bar.shell.updateEntryInline(moduleName, entry)` is a sanctioned, *scoped* plugin API — `PluginShellApi`
  restricts a plugin to its own bar entry (`shell.qml:649`). Clock and Tray use the same call.
- Theme binding through `bar.foreground` / `bar.urgent` / `bar.fontFamily` is the documented contract.
- Security posture of the helper is good and should be kept as-is:
  - the password goes to `secret-tool store` on **stdin**, never argv, and is never written to disk in
    plaintext (an existing plaintext `password =` line is actively removed);
  - every subprocess is an argv list — **no shell anywhere** — and `tmux send-keys -l -t <pane> -- <text>`
    passes the Advanced input literally;
  - config and state writes are `mkstemp` + `chmod 0600` + `os.replace`, i.e. atomic, into `0700` dirs;
  - console output is ANSI-stripped and every `Text` that renders external data sets
    `textFormat: Text.PlainText`;
  - setup refuses to clobber a pre-existing foreign `event_command` instead of silently replacing it.

Also worth recording: pianobar 2024.12.21 emits **no** `playbackpause` / `playbackstart` / `playbackstop`
event (confirmed against the binary's event table). The client-side pause/elapsed estimation in
`update_pause_state()` is therefore not a shortcut — it is the only option available. Keep it; just move
it to where it costs nothing (§4).

---

## 4. Finding 1 — the polling architecture (the whole point of this refactor)

### Now

```
pianobar --event--> eventcmd --> bridge.py event --> state.json      (a few times per song)
QML Timer 1 Hz -----------------> bridge.py status --> stdout JSON   (86,400 times per day)
```

`bridge.py status` recomputes `elapsed`/`remaining`/`total` from numbers it already wrote into
`state.json`, re-reads the pianobar config two or three times, runs three `shutil.which()` calls, probes
the FIFO, asks tmux whether the session exists, and — **whenever a session exists, even with the Advanced
view closed** — runs `tmux list-panes` and `tmux capture-pane`, regexes the result, and ships up to 7 KB
of pane text to a panel nobody is looking at.

### Target

```
pianobar --event--> eventcmd --> bridge.py event --> state.json      (unchanged)
QML FileView(state.json, watchChanges) ------------> now playing, station, upcoming, clock base
QML Timer (only while a track plays) --------------> elapsed/remaining, computed in JS
QML Timer 15 s idle / 5 s panel-open --------------> bridge.py env   (running, managed, configured, pkgs)
QML Timer 1 s, only while Advanced is open --------> bridge.py console
```

Three specific moves:

1. **`FileView { path: state.json; watchChanges: true; onFileChanged: reload() }`** — the shell's own
   idiom for exactly this shape of data (`plugins/agents/Agent.qml:16`). Because `write_state()` uses
   `os.replace`, the inode changes and `QFileSystemWatcher` can go quiet — the shell hit the same problem
   and documents it at `plugins/bar/Bar.qml:1166`. Mitigate the same way: also watch the cache **directory**,
   and keep a low-rate `reload()` (5 s) as a floor. A `reload()` is an in-process file read; it is not a
   process spawn.
2. **Compute the clock in QML.** `state.json` already carries `durationSeconds`, `elapsedSeconds`,
   `clockStarted` and `paused` — everything needed. Delete `elapsed`/`remaining`/`total` from
   `status()`. Run the 1 Hz display timer only when `title && !paused && (clocks enabled || panel open)`.
3. **Split `status` into `env` and `console`.** `env` returns only the facts that need a process
   (`running`, `managed`, `configured`, `account`, `missingPackages`) and is called on: startup, panel
   open, after every control/account command, and on the 15 s/5 s timer. `console` is called only while
   the Advanced view is open.

### Expected result

| | Now | After |
|---|---|---|
| Process spawns/day (idle) | ~86,400 python + ~86,400 tmux | ~5,760 python |
| Process spawns/day (playing, Advanced closed) | ~86,400 python + ~250,000 tmux | ~5,760 python |
| CPU/hour per bar instance | ~150 s (4.1% of a core) | ~7 s (0.2% of a core) |
| Now-playing latency | up to 1 s | immediate (file watch) |

Acceptance test: `pgrep -c -f bridge.py` sampled over a minute of playback should be 0 almost always;
`ps -eo etimes,args | grep bridge.py` should show no invocation older than a second; the bar label must
still update within a second of a track change, and within 15 s of pianobar being killed from outside.

---

## 5. Remaining findings

Ranked. Each one is small; the evidence is cited so it can be checked before changing anything.

**P1 — console captured when nobody is watching.** `status()` sets `value["console"]` whenever a managed
session exists (`bridge.py:168`), not when the Advanced view is open. Folded into §4.

**P2 — vertical bars are unsupported.** The bar contract says every widget must work in `top`, `bottom`,
`left` and `right`, and that text widgets fall back to an icon-only form on vertical bars
(`plugins/bar/README.md`, Orientation). `BarWidget` hands every widget a `vertical` property for this —
and `BarWidget.qml`/`Panel.qml` never reference it, so a left/right bar gets a 230–500 px horizontal
label. Fix as `omarchy.media` does: `visible: !bar.vertical` on the label, glyph only otherwise
(`plugins/services/media/BarWidget.qml:53`). ~4 lines.

**P2 — the ticker does its own font metrics.** `windowChars`/`effectiveWidth` divide by hard-coded 8 and
9 px per character (`BarWidget.qml:32-34`) and a 450 ms JS `Timer` rebuilds `(trackText + "     ").repeat(3)`
and slices it on every tick. That is only correct for a monospace bar font. `omarchy.media` gets this
right with a clipped `Item` plus `NumberAnimation on x`, which runs on the scene graph with no JS
(`plugins/services/media/BarWidget.qml:47-77`). Adopting it deletes `tickerOffset`, `tickerText`,
`windowChars`, `effectiveWidth` and the timer (~15 lines), keeps the min-width setting as the clip's
width, and lets the elapsed/remaining text be its own `Text` instead of being concatenated into the
scrolling string. Also copy media's `running: ... && !popupOpen` so the animation stops while the panel
is open.

**P2 — README describes a button that no longer exists.** "Click Stop there to end the managed session"
is stale: since 1.4.4 the Stop button is `visible: !root.player.configured` (`Panel.qml:136`), so once an
account is saved there is no way to stop the player except Remove Account. Either restore a Stop control
(e.g. long-press or a modifier on Play) or fix the README. My recommendation is to restore it — "stop the
thing I started" is a reasonable expectation, and Remove Account is a destructive detour.

**P2 — helper path is not percent-decoded.** `Qt.resolvedUrl("bridge.py").toString().replace(/^file:\/\//, "")`
(`BarWidget.qml:36`) leaves `%20` in place, so the widget breaks for any user whose `$HOME` contains a
space or a non-ASCII character. One line: wrap it in `decodeURIComponent()`.

**P3 — `state.json` read-modify-write races.** `event()` and `update_pause_state()` both read, mutate and
replace the file. pianobar fires `songfinish` + `stationfetchplaylist` + `songstart` in quick succession,
and a pause can land in the middle. `os.replace` keeps the file valid, but an update can be lost. Six
lines of `fcntl.flock` on a lock file in the cache dir closes it.

**P3 — a bad event value silently drops the whole update.** `int(data.get("stationCount", "0"))`
(`bridge.py:58`) raises `ValueError` on garbage; `main()` catches it and exits 1, so pianobar's hook
fails and *no* state is written for that event. A four-line tolerant `as_int()` helper fixes it.

**P3 — `send()` ignores short writes.** `os.write(fd, payload)` (`bridge.py:142`) can in principle write
fewer bytes than given for the multi-byte station payload. A two-line loop removes the class of bug.

**P3 — the same config file is parsed two or three times per `status`.** `configured()` and the `account`
lookup each call `config_values()` (`bridge.py:169-170`). Read once, pass it down.

**P3 — the version string lives in two places.** `manifest.json` and `BarWidget.qml:12` must be bumped
together or the panel lies about what is installed. Either read the manifest with a `FileView` (~8 lines)
or add it to the release checklist and accept the duplication.

**P3 — dead payload.** `coverArt` is written to state and shipped in every `status`, and nothing renders
it. Either drop it or use it (a small cover thumbnail in the panel would be the natural use).

**P3 — README is carrying a changelog.** Thirteen "Version 1.4.x does…" sentences sit in the install
section. Move them to `CHANGELOG.md` and let the README describe the current behavior only. This also
removes the temptation to keep appending a paragraph per patch release.

---

## 6. Security review

Nothing here is urgent. The good parts are listed in §3; these are the gaps.

**Low — secrets typed into the Advanced field.** Input goes to `tmux send-keys -l -t <pane> -- <text>`,
so it appears in that tmux command's argv (same-user visible in `/proc`) and then lands in the pane
scrollback, which `console_output()` reads straight back into the panel. Normal use never involves a
secret, but pianobar will prompt for a password if the config is ever in a state where
`password_command` is missing. Mitigations, cheapest first: (a) say so in the Advanced view's one-line
hint and in the README; (b) when the captured pane's last line matches `/password/i`, flip the field to
`password: true` — about five lines in `Panel.qml`.

**Low — a second pianobar can attach to the same FIFO.** Observed live during this review: starting a
stray `pianobar` while the widget's session was running printed "Control fifo … opened" in the second
process, and control keys then go to whichever reader wins. `start()` does guard against this
(`bridge.py:394-397`), but only at start time. Worth one line in the README's troubleshooting section;
a runtime check would cost another process per poll and is not worth it.

**Resolved — system dependency installation.** The widget now only reports missing dependencies. It does
not invoke a package manager or cross a privilege boundary, which permits standard Marketplace installation.

**Informational — file permissions are the user's whole security boundary.** `~/.config/pianobar/config`
is written `0600` and the cache dir `0700`, which is right. Note that the plugin sets those modes on the
files it writes but does not repair a pre-existing world-readable config it inherits. A one-line
`os.chmod(CONFIG_FILE, 0o600)` in `write_config()` (already effectively achieved via the temp-file mode)
covers it — verify rather than assume.

---

## 7. Should it be rewritten in another language?

**No.** The reasoning, with the numbers:

| Option | Steady-state cost after §4 | Distribution | Verdict |
|---|---|---|---|
| **Python 3 (today)** | ~5,760 spawns/day × 40 ms ≈ 7 s CPU/hour | stdlib only; Omarchy ships Python 3 | **Keep** |
| Rust / Go / C | ~5,760 × ~2 ms ≈ 0.3 s CPU/hour | needs a committed binary per arch, or a build step `omarchy plugin add` does not have | No |
| POSIX sh + jq | comparable or worse (more subprocesses) | jq is another dependency | No |
| Pure QML/JS, no helper | ~0 | — | Partly — see below |

Three things make this decision, not taste:

1. **The saving does not exist after the real fix.** A compiled helper buys back ~7 s of CPU per hour.
   Deleting the 1 Hz poll buys back ~143 s per hour. Doing the second makes the first irrelevant.
2. **Omarchy plugins install by `git clone`.** `omarchy plugin add` clones and enables; it runs no build
   and no package hooks (the README already says this). A Rust helper means committing prebuilt binaries
   to the repo — in a project whose own README tells users to *read the source before installing*. That
   trades a reviewable 463-line script for an unreviewable blob, and adds an architecture matrix and a
   signing question. That is a real regression in trustworthiness, not a neutral change.
3. **Nothing else here does it.** Of the seven plugins installed on this machine, helpers are bash
   (`omasettings`) and JavaScript `Model.js` files (`hass`, `hurricane-tracker`, `hyprmoncfg`, `nick.tray`);
   the first-party plugins use QML plus `Model.js`. Not one ships a compiled binary. This widget is
   already the only one with a Python helper; a binary would make it the only one with a binary.

The partial exception is worth naming: **more of this belongs in QML/JS than currently is.** The clock
math, the ticker math, the action names and the settings clamps are pure functions that every other
plugin would keep in a `Model.js`. Moving them there is the "rewrite" that actually pays — it deletes
Python from the per-second path, matches the house style, and makes the logic testable without a
subprocess. What must stay in Python is the part that genuinely needs care: atomic config rewriting with
`0600` modes, Secret Service calls, and the FIFO. Those run on user action, a handful
of times per session, where 40 ms is invisible.

One more structural question, answered so it does not get re-litigated: **keep tmux.** It supplies a pty
(pianobar wants a terminal), detachment, and the scrollback the Advanced view reads. Replacing it means
hand-rolling a pty with Python's `pty` module — more code, more failure modes, no win.

---

## 8. Phased plan

Each phase is independently shippable and independently revertable.

**Phase 1 — kill the poll (the only phase that really matters).**
- Add `Model.js` with `formatTime`, `elapsedFrom(state, now)`, `remainingFrom(...)`, `actionName(...)`.
- Add `FileView` on `state.json` + directory watch + 5 s floor reload.
- Split `bridge.py status` into `env` and `console`; delete the computed `elapsed`/`remaining`/`total`
  and the `console` key from the env path; read the config once per invocation.
- Retime the QML: env at 15 s (5 s while the panel is open), console at 1 s only while Advanced is open,
  display clock at 1 s only while a track is playing and unpaused.
- Verify: `pgrep -f bridge.py` is empty almost always; track changes still appear within a second;
  killing pianobar from a terminal clears the bar within 15 s; the Advanced view still scrolls live.

**Phase 2 — bar rendering.**
- `bar.vertical` fallback to glyph-only.
- Replace the ticker with the clipped `NumberAnimation` pattern; time text becomes its own `Text`.
- `decodeURIComponent` on the helper path.
- Verify: `omarchy bar position left` then `right` then back to `top`; a non-monospace bar font; a
  `$HOME` containing a space (test with `HOME=/tmp/a b`).

**Phase 3 — helper hardening.**
- `flock` around state read-modify-write; tolerant `as_int()`; short-write loop in `send()`.
- Confirm `0600` on an inherited config.
- Verify: skip tracks rapidly while pausing; `state.json` stays valid and pause never sticks wrong.

**Phase 4 — surface and docs.**
- Restore a Stop control (or correct the README — pick one).
- Report missing packages without installing them; add the Advanced-field secret warning.
- `CHANGELOG.md`; trim the README to current behavior; add the second-instance FIFO note to troubleshooting.
- Optionally: `barWidget.defaults` + `barWidget.schema` in the manifest. Measured caveat — this shell
  registers that metadata (`shell.qml:1406-1408`) but nothing in it renders a form today, so this is
  marketplace polish and future-proofing, not a functional gap. ~18 lines of JSON; worth it only if you
  want the manifest to be the single source of truth for defaults.
- Optionally: an `IpcHandler` exposing `playPause` / `next`, so Hyprland media keys can bind to the widget.

**Line-count honesty.** This is not a "make it smaller" refactor; it is a "make it stop doing work"
refactor. Expect `bridge.py` 463 → ~390, the two QML files to lose ~30 lines to `Model.js` (~80 lines) and
~15 to the ticker rewrite, plus ~25 lines of new `FileView`/timer wiring. Net total is roughly flat.
What changes by two orders of magnitude is processes per day.

## 9. Explicitly not recommended

- Rewriting the helper in Rust, Go, or C (§7).
- Replacing tmux (§7).
- Restructuring `BarWidget.qml` + `Loader{Panel.qml}` — it already matches `omarchy.clock` (§3).
- "Fixing" the client-side pause/elapsed estimate — pianobar 2024.12.21 emits no playback events, so
  there is nothing better to read (§3).
- Replacing `bar.shell.updateEntryInline` — it is the sanctioned, scoped API (§3).
- Micro-optimizing the Python imports. Measured: lazy-importing `subprocess`/`shutil`/`re` would save
  ~12 ms on the event path, which fires a few times per song — under a second of CPU per day. Not worth
  the readability cost.
