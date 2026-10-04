#!/usr/bin/env python3
"""Small local bridge from pianobar's event command and control FIFO to Quattro."""
import errno
import fcntl
import hashlib
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
import urllib.request
from urllib.parse import urlparse
from contextlib import contextmanager

PLUGIN_ID = "io.github.nicholasladwig.pianobar-pandora-widget"
CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "pianobar"
CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / PLUGIN_ID
STATE = CACHE / "state.json"
FIFO = CONFIG / "ctl"
CONFIG_FILE = CONFIG / "config"
SESSION = "omarchy-pianobar-pandora-widget"
ACTION_BINDINGS = {
    "pause": (("act_songpausetoggle", "act_songpausetoggle2"), ("p", " ")),
    "next": ("act_songnext", "n"),
    "love": ("act_songlove", "+"),
    "ban": ("act_songban", "-"),
    "tired": ("act_songtired", "t"),
    "volume-down": ("act_voldown", "("),
    "volume-up": ("act_volup", ")"),
    "volume-reset": ("act_volreset", "^"),
    "station": ("act_stationchange", "s"),
}


def reported_error(data):
    """Return only an actual pianobar failure, never a success status line."""
    message = str(data.get("pRetStr", "")).strip()
    if data.get("pRet", "0") in ("0", ""):
        return ""
    if message.lower() in ("everything is fine", "everything is fine :)"):
        return ""
    return message


def as_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def read_state():
    try:
        return json.loads(STATE.read_text())
    except (OSError, ValueError):
        return {}


def cover_art_path(url):
    """Return a per-song cache path so QML does not reuse a stale image.

    QML caches decoded images by URL and filesystem URLs are not watched, so
    a fixed filename would keep showing the first song's art. Deriving the
    name from the art URL makes each song load a fresh file.
    """
    suffix = Path(urlparse(url).path).suffix.lower()
    if suffix not in (".jpg", ".jpeg", ".png", ".gif", ".webp"):
        suffix = ".jpg"
    digest = hashlib.sha1(url.encode("utf-8")).hexdigest()[:16]
    return CACHE / ("cover-" + digest + suffix)


def fetch_cover_art(url, previous):
    """Download the album art to the cache so QML can read a local file.

    Pandora's image CDN rejects requests that do not pass through the
    configured proxy, and the Omarchy shell runs without proxy environment
    variables, so QML's own Image loader cannot reach it. This process
    inherits the proxy settings (urllib reads them) and can.
    """
    if not url:
        return ""
    target = cover_art_path(url)
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            payload = response.read(10 * 1024 * 1024)
    except (OSError, ValueError):
        return ""
    if not payload:
        return ""
    try:
        target.write_bytes(payload)
        os.chmod(target, 0o600)
    except OSError:
        return ""
    for stale in CACHE.glob("cover-*"):
        if stale != target and stale.suffix.lower() in (".jpg", ".jpeg", ".png", ".gif", ".webp"):
            try:
                stale.unlink()
            except OSError:
                pass
    return str(target)


@contextmanager
def state_lock():
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(CACHE, 0o700)
    lock_path = CACHE / "state.lock"
    with open(lock_path, "a", encoding="utf-8") as lock:
        os.chmod(lock_path, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def event(name):
    data = {}
    for line in sys.stdin:
        key, sep, value = line.rstrip("\n").partition("=")
        if sep:
            data[key] = value
    with state_lock():
        previous = read_state()
        stations = [data.get(f"station{i}", "") for i in range(min(max(0, as_int(data.get("stationCount"))), 1000))]
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
        now = time.time()
        playback_event = name in ("songstart", "stationfetchplaylist") and bool(data.get("title"))
        result = {
            "durationSeconds": max(0, as_int(data.get("songDuration"))) if playback_event else previous.get("durationSeconds", 0),
            "elapsedSeconds": max(0, as_int(data.get("songPlayed"))) if playback_event else previous.get("elapsedSeconds", 0),
            "clockStarted": now if playback_event else previous.get("clockStarted", now),
            "paused": False if playback_event else previous.get("paused", False),
            "station": data.get("stationName") or previous.get("station", ""),
            "stations": stations,
            "title": data.get("title", "") if has_song and data.get("title") else (previous.get("title", "") if has_song else ""),
            "artist": data.get("artist", "") if has_song and data.get("artist") else (previous.get("artist", "") if has_song else ""),
            "album": data.get("album", "") if has_song and data.get("album") else (previous.get("album", "") if has_song else ""),
            "coverArt": data.get("coverArt", "") if has_song and data.get("coverArt") else (previous.get("coverArt", "") if has_song else ""),
            "coverArtPath": fetch_cover_art(data.get("coverArt", ""), previous) if has_song and data.get("coverArt") else (previous.get("coverArtPath", "") if has_song else ""),
            "rating": data.get("rating", "") if has_song else "",
            "upcoming": upcoming if name in ("songstart", "stationfetchplaylist") else (previous.get("upcoming", []) if has_song else []),
            "waitingForStation": name == "usergetstations" or (previous.get("waitingForStation", False) and name not in ("stationfetchplaylist", "songstart")),
            "error": reported_error(data),
            "updated": now,
        }
        write_state(result)


def update_pause_state():
    with state_lock():
        value = read_state()
        if not value.get("title"):
            return
        now = time.time()
        if value.get("paused", False):
            value["paused"] = False
            value["clockStarted"] = now
        else:
            value["elapsedSeconds"] = float(value.get("elapsedSeconds", 0) or 0) + max(0, now - float(value.get("clockStarted", now)))
            value["paused"] = True
        write_state(value)


def write_state(value):
    CACHE.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix="state-", dir=CACHE)
    try:
        with os.fdopen(fd, "w") as output:
            json.dump(value, output, ensure_ascii=False)
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
        data = payload.encode("utf-8")
        while data:
            written = os.write(fd, data)
            if written <= 0:
                raise RuntimeError("Could not write the full player command")
            data = data[written:]
    finally:
        os.close(fd)


def env_status():
    try:
        running_fd = fifo_fd()
        os.close(running_fd)
        running = True
    except (RuntimeError, OSError):
        running = False
    values = config_values()
    is_configured = configured(values)
    print(json.dumps({
        "running": running,
        "missingPackages": missing_packages(),
        "managed": managed_session(),
        "configured": is_configured,
        "account": values.get("user", "") if is_configured else "",
    }, ensure_ascii=False))


def console_status():
    print(json.dumps({"console": console_output() if managed_session() else ""}, ensure_ascii=False))


def config_values():
    values = {}
    try:
        lines = CONFIG_FILE.read_text().splitlines()
    except FileNotFoundError:
        return values
    except OSError as exc:
        raise RuntimeError(f"Could not read {CONFIG_FILE}: {exc.strerror or exc}") from exc
    for line in lines:
        key, sep, value = line.partition("=")
        if sep and not key.lstrip().startswith("#"):
            values[key.strip()] = value.strip()
    return values


def configured(values=None):
    values = config_values() if values is None else values
    return bool(values.get("user") and (values.get("password_command") or values.get("password")))


def config_lines():
    try:
        return CONFIG_FILE.read_text().splitlines()
    except FileNotFoundError:
        return []
    except OSError as exc:
        raise RuntimeError(f"Could not read {CONFIG_FILE}: {exc.strerror or exc}") from exc


def missing_packages():
    names = {"pianobar": "pianobar", "tmux": "tmux", "secret-tool": "libsecret"}
    return [package for executable, package in names.items() if not shutil.which(executable)]


def console_output():
    try:
        result = subprocess.run(["tmux", "capture-pane", "-p", "-S", "-35", "-t", pane_id()],
                                capture_output=True, text=True, errors="replace", timeout=2)
    except subprocess.TimeoutExpired:
        return ""
    if result.returncode:
        return ""
    # Preserve readable pianobar output without terminal styling/control codes.
    output = re.sub(r"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))", "", result.stdout)
    return output[-7000:].strip()


def password_prompt_active():
    lines = [line.strip() for line in console_output().splitlines() if line.strip()]
    return bool(lines and re.search(r"password", lines[-1], re.IGNORECASE))


def send_input():
    if not managed_session():
        raise RuntimeError("Start pianobar before sending a command")
    if password_prompt_active():
        raise RuntimeError("Password prompts are handled through Edit Account")
    value = json.loads(sys.stdin.readline())
    answer = str(value.get("text", ""))
    if len(answer) > 256 or any(ord(c) < 32 or ord(c) == 127 for c in answer):
        raise RuntimeError("Command input must be one line of at most 256 characters")
    if password_prompt_active():
        raise RuntimeError("Password prompts are handled through Edit Account")
    if answer:
        result = subprocess.run(["tmux", "send-keys", "-l", "-t", pane_id(), "--", answer],
                                capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr.strip() or "Could not send pianobar input")
    result = subprocess.run(["tmux", "send-keys", "-t", pane_id(), "Enter"],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not submit pianobar input")


def send_special_key(key):
    if key not in ("Escape", "Up", "Down", "Tab", "Enter"):
        raise RuntimeError("Unsupported key")
    if not managed_session():
        raise RuntimeError("Start pianobar before sending a key")
    result = subprocess.run(["tmux", "send-keys", "-t", pane_id(), key],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not send pianobar key")


def managed_session():
    if not shutil.which("tmux"):
        return False
    return subprocess.run(["tmux", "has-session", "-t", "=" + SESSION],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def pane_id():
    result = subprocess.run(["tmux", "list-panes", "-t", "=" + SESSION, "-F", "#{pane_id}"],
                            capture_output=True, text=True, timeout=2)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not find the pianobar tmux pane")
    pane = result.stdout.splitlines()
    if not pane:
        raise RuntimeError("The pianobar tmux session has no active pane")
    return pane[0]


def action_key(action):
    if action not in ACTION_BINDINGS:
        raise RuntimeError("Unknown action")
    config_key, default = ACTION_BINDINGS[action]
    if action == "pause":
        keys, fallbacks = config_key, default
    else:
        keys, fallbacks = (config_key,), (default,)
    values = config_values()
    for key, fallback in zip(keys, fallbacks):
        value = values.get(key, "")
        if value.lower() == "disabled":
            continue
        if value == "<Space>":
            return " "
        if len(value) == 1:
            return value
        return fallback
    raise RuntimeError(f"Pianobar's {', '.join(keys)} bindings are disabled")


def ensure_runtime():
    CONFIG.mkdir(mode=0o700, parents=True, exist_ok=True)
    if FIFO.exists():
        if not stat.S_ISFIFO(FIFO.stat().st_mode):
            raise RuntimeError(f"{FIFO} exists and is not a FIFO")
    else:
        os.mkfifo(FIFO, 0o600)
    check_event_command()
    hook = str(Path(__file__).resolve().parent / "eventcmd")
    lines = config_lines()
    replacements = {"fifo": str(FIFO), "event_command": hook}
    write_config(lines, replacements)


def check_event_command():
    old_hook = config_values().get("event_command", "")
    hook = str(Path(__file__).resolve().parent / "eventcmd")
    if old_hook and old_hook != hook:
        raise RuntimeError("Another pianobar event_command is configured; remove or chain it before setup")


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
        os.chmod(CONFIG_FILE, 0o600)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def save_account():
    if not shutil.which("secret-tool"):
        raise RuntimeError("secret-tool is required to save your password")
    check_event_command()
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
    lines = config_lines()
    command = "secret-tool lookup application " + shlex.quote(PLUGIN_ID) + " account " + shlex.quote(username)
    write_config(lines, {"user": username, "password": None, "password_command": command})
    ensure_runtime()
    start()


def remove_account():
    values = config_values()
    username = values.get("user", "")
    if not username:
        raise RuntimeError("No saved Pandora account was found")
    stop()
    if not shutil.which("secret-tool"):
        raise RuntimeError("secret-tool is required to remove the saved password")
    result = subprocess.run(["secret-tool", "clear", "application", PLUGIN_ID, "account", username],
                            capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not remove the password from Secret Service")
    lines = config_lines()
    write_config(lines, {"user": None, "password": None, "password_command": None})


def start():
    if not shutil.which("pianobar") or not shutil.which("tmux"):
        raise RuntimeError("Install pianobar and tmux to play from the widget")
    if not configured():
        raise RuntimeError("Save your Pandora account in the widget first")
    values = config_values()
    hook = str(Path(__file__).resolve().parent / "eventcmd")
    if values.get("event_command") != hook or values.get("fifo") != str(FIFO) or not FIFO.is_fifo():
        raise RuntimeError("Save your account in the widget to authorize pianobar setup")
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


def stop():
    if not managed_session():
        return
    result = subprocess.run(["tmux", "kill-session", "-t", "=" + SESSION],
                            capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not stop pianobar")


def main():
    if len(sys.argv) < 2:
        raise RuntimeError("Usage: bridge.py event NAME | env | console | control ACTION [INDEX]")
    if sys.argv[1] == "event" and len(sys.argv) == 3:
        event(sys.argv[2])
    elif sys.argv[1] in ("env", "status") and len(sys.argv) == 2:
        env_status()
    elif sys.argv[1] == "console" and len(sys.argv) == 2:
        console_status()
    elif sys.argv[1] == "account" and len(sys.argv) == 2:
        save_account()
    elif sys.argv[1] == "start" and len(sys.argv) == 2:
        start()
    elif sys.argv[1] == "stop" and len(sys.argv) == 2:
        stop()
    elif sys.argv[1] == "remove-account" and len(sys.argv) == 2:
        remove_account()
    elif sys.argv[1] == "input" and len(sys.argv) == 2:
        send_input()
    elif sys.argv[1] == "key" and len(sys.argv) == 3:
        send_special_key(sys.argv[2])
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
            send(("" if waiting else action_key("station")) + index + "\n")
        elif action in ACTION_BINDINGS and len(sys.argv) == 3:
            send(action_key(action))
            if action == "pause":
                update_pause_state()
        else:
            raise RuntimeError("Unknown action")
    else:
        raise RuntimeError("Invalid arguments")


def _selfcheck():
    assert cover_art_path("http://c/x/1080W_1080H.jpg").suffix == ".jpg"
    assert cover_art_path("http://c/x/y.png").suffix == ".png"
    assert cover_art_path("http://c/x/y.bmp").suffix == ".jpg"
    assert cover_art_path("http://c/x").suffix == ".jpg"
    assert cover_art_path("http://c/x/a.jpg") != cover_art_path("http://c/x/b.jpg")
    assert fetch_cover_art("", "") == ""


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selfcheck":
        _selfcheck()
        print("selfcheck ok")
        raise SystemExit(0)
    try:
        main()
    except (RuntimeError, OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
