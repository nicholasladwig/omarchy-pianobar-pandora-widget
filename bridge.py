#!/usr/bin/env python3
"""Small local bridge from pianobar's event command and control FIFO to Quattro."""
import errno
import json
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
import time

PLUGIN_ID = "io.github.nicholasladwig.pianobar-pandora-widget"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "pianobar"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / PLUGIN_ID
STATE = CACHE / "state.json"
FIFO = CONFIG / "ctl"
ACTIONS = {"pause": "p", "next": "n", "love": "+", "ban": "-", "tired": "t", "volume-down": "(", "volume-up": ")", "volume-reset": "^"}


def event(name):
    data = {}
    for line in sys.stdin:
        key, sep, value = line.rstrip("\n").partition("=")
        if sep:
            data[key] = value
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(CACHE, 0o700)
    try:
        previous = json.loads(STATE.read_text())
    except (OSError, ValueError):
        previous = {}
    stations = [data.get(f"station{i}", "") for i in range(min(int(data.get("stationCount", "0")), 1000))]
    if not stations and name != "usergetstations":
        stations = previous.get("stations", [])
    upcoming = []
    for i in range(5):
        if f"titleNext{i}" not in data:
            break
        upcoming.append({"title": data.get(f"titleNext{i}", ""), "artist": data.get(f"artistNext{i}", ""), "album": data.get(f"albumNext{i}", "")})
    # Only playback transitions clear the current song. Administrative events
    # often have no song payload and must leave the displayed track intact.
    if name == "songfinish":
        has_song = bool(previous.get("title")) and previous.get("title") != data.get("title")
    elif name in ("songstart", "stationfetchplaylist"):
        has_song = bool(data.get("title"))
    else:
        has_song = bool(data.get("title") or previous.get("title"))
    result = {
        "station": data.get("stationName") or previous.get("station", ""),
        "stations": stations,
        "title": data.get("title", "") if has_song and data.get("title") else (previous.get("title", "") if has_song else ""),
        "artist": data.get("artist", "") if has_song and data.get("artist") else (previous.get("artist", "") if has_song else ""),
        "album": data.get("album", "") if has_song and data.get("album") else (previous.get("album", "") if has_song else ""),
        "coverArt": data.get("coverArt", "") if has_song and data.get("coverArt") else (previous.get("coverArt", "") if has_song else ""),
        "rating": data.get("rating", "") if has_song else "",
        "upcoming": upcoming if name in ("songstart", "stationfetchplaylist") else (previous.get("upcoming", []) if has_song else []),
        "updated": time.time(),
    }
    fd, temporary = tempfile.mkstemp(prefix="state-", dir=CACHE)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(result, output, ensure_ascii=False)
        os.chmod(temporary, 0o600)
        os.replace(temporary, STATE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def fifo_fd():
    try:
        if not stat.S_ISFIFO(FIFO.stat().st_mode):
            raise RuntimeError(f"{FIFO} is not a FIFO")
        return os.open(FIFO, os.O_WRONLY | os.O_NONBLOCK)
    except FileNotFoundError:
        raise RuntimeError(f"Missing {FIFO}; run mkfifo {FIFO}") from None
    except OSError as exc:
        if exc.errno == errno.ENXIO:
            raise RuntimeError("Pianobar is not running or is not reading the control FIFO") from None
        raise


def send(payload):
    fd = fifo_fd()
    try:
        os.write(fd, payload.encode("utf-8"))
    finally:
        os.close(fd)


def status():
    try:
        running_fd = fifo_fd()
        os.close(running_fd)
        running = True
    except (RuntimeError, OSError):
        running = False
    try:
        value = json.loads(STATE.read_text())
    except (OSError, ValueError):
        value = {}
    value["running"] = running
    if not running:
        value["title"] = ""
        value["upcoming"] = []
    print(json.dumps(value, ensure_ascii=False))


def main():
    if len(sys.argv) < 2:
        raise RuntimeError("Usage: bridge.py event NAME | status | control ACTION [INDEX]")
    if sys.argv[1] == "event" and len(sys.argv) == 3:
        event(sys.argv[2])
    elif sys.argv[1] == "status" and len(sys.argv) == 2:
        status()
    elif sys.argv[1] == "control" and len(sys.argv) >= 3:
        action = sys.argv[2]
        if action == "station" and len(sys.argv) == 4:
            index = sys.argv[3]
            if not re.fullmatch(r"\d{1,3}", index):
                raise RuntimeError("Invalid station index")
            send("s" + index + "\n")
        elif action in ACTIONS and len(sys.argv) == 3:
            send(ACTIONS[action])
        else:
            raise RuntimeError("Unknown action")
    else:
        raise RuntimeError("Invalid arguments")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
