#!/usr/bin/env python3
"""Small local bridge from pianobar's event command and control FIFO to Quattro."""
import errno
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import stat
import sys
import tempfile
import time

PLUGIN_ID = "io.github.nicholasladwig.pianobar-pandora-widget"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "pianobar"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / PLUGIN_ID
STATE = CACHE / "state.json"
FIFO = CONFIG / "ctl"
CONFIG_FILE = CONFIG / "config"
SESSION = "omarchy-pianobar-pandora-widget"
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
        "waitingForStation": name == "usergetstations" or (previous.get("waitingForStation", False) and name not in ("stationfetchplaylist", "songstart")),
        "error": data.get("pRetStr", "") if data.get("pRet", "0") not in ("0", "") else "",
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
    value["managed"] = managed_session()
    value["configured"] = configured()
    if not running:
        value["title"] = ""
        value["upcoming"] = []
        value["waitingForStation"] = False
    print(json.dumps(value, ensure_ascii=False))


def config_values():
    values = {}
    try:
        lines = CONFIG_FILE.read_text().splitlines()
    except OSError:
        return values
    for line in lines:
        key, sep, value = line.partition("=")
        if sep and not key.lstrip().startswith("#"):
            values[key.strip()] = value.strip()
    return values


def configured():
    values = config_values()
    return bool(values.get("user") and (values.get("password_command") or values.get("password")))


def managed_session():
    if not shutil.which("tmux"):
        return False
    return subprocess.run(["tmux", "has-session", "-t", "=" + SESSION],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def ensure_runtime():
    CONFIG.mkdir(mode=0o700, parents=True, exist_ok=True)
    if FIFO.exists():
        if not stat.S_ISFIFO(FIFO.stat().st_mode):
            raise RuntimeError(f"{FIFO} exists and is not a FIFO")
    else:
        os.mkfifo(FIFO, 0o600)
    values = config_values()
    old_hook = values.get("event_command", "")
    hook = str(Path(__file__).resolve().parent / "eventcmd")
    if old_hook and old_hook != hook:
        raise RuntimeError("Another pianobar event_command is configured; remove or chain it before starting")
    try:
        lines = CONFIG_FILE.read_text().splitlines()
    except OSError:
        lines = []
    replacements = {"fifo": str(FIFO), "event_command": hook}
    write_config(lines, replacements)


def write_config(lines, replacements):
    kept = []
    for line in lines:
        key, sep, _ = line.partition("=")
        if not sep or key.strip() not in replacements or key.lstrip().startswith("#"):
            kept.append(line)
    kept.extend(f"{key} = {value}" for key, value in replacements.items() if value is not None)
    CONFIG.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="config-", dir=CONFIG)
    try:
        with os.fdopen(fd, "w") as out:
            out.write("\n".join(kept) + "\n")
        os.chmod(temporary, 0o600)
        os.replace(temporary, CONFIG_FILE)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def save_account():
    if not shutil.which("secret-tool"):
        raise RuntimeError("secret-tool is required to save your password")
    payload = json.loads(sys.stdin.readline())
    username = str(payload.get("username", "")).strip()
    password = str(payload.get("password", ""))
    if not username or not password or any(c in username for c in "\r\n="):
        raise RuntimeError("Enter a valid username and password")
    result = subprocess.run(["secret-tool", "store", "--label=Pianobar Pandora Widget",
                             "application", PLUGIN_ID, "account", username],
                            input=password, text=True, capture_output=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not save password in Secret Service")
    try:
        lines = CONFIG_FILE.read_text().splitlines()
    except OSError:
        lines = []
    command = "secret-tool lookup application " + shlex.quote(PLUGIN_ID) + " account " + shlex.quote(username)
    write_config(lines, {"user": username, "password": None, "password_command": command})
    ensure_runtime()
    start()


def start():
    if not shutil.which("pianobar") or not shutil.which("tmux"):
        raise RuntimeError("Install pianobar and tmux to play from the widget")
    if not configured():
        raise RuntimeError("Save your Pandora account in the widget first")
    ensure_runtime()
    if managed_session():
        return
    try:
        fd = fifo_fd()
        os.close(fd)
        raise RuntimeError("Pianobar is already running outside the widget; close it before starting here")
    except RuntimeError as exc:
        if not str(exc).startswith("Pianobar is not running"):
            raise
    result = subprocess.run(["tmux", "new-session", "-d", "-s", SESSION, "pianobar"],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not start pianobar")


def open_terminal():
    if not managed_session():
        start()
    result = subprocess.run(["omarchy-launch-terminal", "tmux", "attach-session", "-t", "=" + SESSION],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not open terminal")


def main():
    if len(sys.argv) < 2:
        raise RuntimeError("Usage: bridge.py event NAME | status | control ACTION [INDEX]")
    if sys.argv[1] == "event" and len(sys.argv) == 3:
        event(sys.argv[2])
    elif sys.argv[1] == "status" and len(sys.argv) == 2:
        status()
    elif sys.argv[1] == "account" and len(sys.argv) == 2:
        save_account()
    elif sys.argv[1] == "start" and len(sys.argv) == 2:
        start()
    elif sys.argv[1] == "terminal" and len(sys.argv) == 2:
        open_terminal()
    elif sys.argv[1] == "control" and len(sys.argv) >= 3:
        action = sys.argv[2]
        if action == "station" and len(sys.argv) == 4:
            index = sys.argv[3]
            if not re.fullmatch(r"\d{1,3}", index):
                raise RuntimeError("Invalid station index")
            try:
                waiting = json.loads(STATE.read_text()).get("waitingForStation", False)
            except (OSError, ValueError):
                waiting = False
            send(("" if waiting else "s") + index + "\n")
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
