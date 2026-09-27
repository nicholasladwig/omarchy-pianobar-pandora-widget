.pragma library

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, Number(value) || 0))
}

function formatTime(value) {
  var seconds = Math.max(0, Math.floor(Number(value) || 0))
  return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
}

function elapsedFrom(state, nowMs, running) {
  var elapsed = Math.max(0, Number(state.elapsedSeconds) || 0)
  var duration = Math.max(0, Number(state.durationSeconds) || 0)
  if (running && state.title && !state.paused)
    elapsed += Math.max(0, nowMs / 1000 - (Number(state.clockStarted) || nowMs / 1000))
  elapsed = Math.floor(elapsed)
  return duration ? Math.min(duration, elapsed) : elapsed
}

function remainingFrom(state, nowMs, running) {
  return Math.max(0, Math.floor(Number(state.durationSeconds) || 0) - elapsedFrom(state, nowMs, running))
}

function actionName(action, paused) {
  var names = {
    "pause": paused ? "Resume playback" : "Pause playback",
    "next": "Next song",
    "love": "Loving song",
    "ban": "Banning song",
    "tired": "Putting song on shelf",
    "volume-down": "Decrease volume",
    "volume-up": "Increase volume",
    "station": "Change station"
  }
  return names[action] || "Command"
}

function passwordPrompt(consoleText) {
  var lines = String(consoleText || "").trim().split("\n")
  return /password/i.test(lines.length ? lines[lines.length - 1] : "")
}
