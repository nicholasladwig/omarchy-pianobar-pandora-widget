import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.nicholasladwig.pianobar-pandora-widget"

  property var player: ({})
  property string pluginVersion: "1.4.12"
  property string errorText: ""
  property string actionFeedback: ""
  property string pendingAction: ""
  property int tickerOffset: 0
  property string accountPayload: ""
  property string advancedPayload: ""
  readonly property string trackText: player.running && player.title ? player.artist + " — " + player.title : ""
  readonly property int playingWidth: Math.max(120, Math.min(500, Number(setting("playingWidth", 230)) || 230))
  readonly property bool showElapsed: setting("showElapsed", true) === true
  readonly property bool showRemaining: setting("showRemaining", true) === true
  readonly property bool showTotal: setting("showTotal", false) === true
  readonly property string timeText: {
    if (!trackText) return ""
    var fields = []
    if (showElapsed) fields.push(formatTime(player.elapsed))
    if (showRemaining) fields.push("-" + formatTime(player.remaining))
    if (showTotal) fields.push(formatTime(player.total))
    return fields.length ? "  " + fields.join(" / ") : ""
  }
  readonly property int effectiveWidth: Math.max(playingWidth, 55 + timeText.length * 8)
  readonly property int windowChars: Math.max(8, Math.floor((effectiveWidth - 30 - timeText.length * 8) / 9))
  readonly property string tickerText: trackText.length <= windowChars ? trackText : (trackText + "     ").repeat(3).slice(tickerOffset, tickerOffset + windowChars)
  onTrackTextChanged: tickerOffset = 0
  readonly property string helper: Qt.resolvedUrl("bridge.py").toString().replace(/^file:\/\//, "")
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function formatTime(value) {
    var seconds = Math.max(0, Math.floor(Number(value) || 0))
    var minutes = Math.floor(seconds / 60)
    var remainder = String(seconds % 60).padStart(2, "0")
    return minutes + ":" + remainder
  }

  function setOption(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[name] = value
    root.settings = entry
    if (panelLoader.item && typeof panelLoader.item.applyPersistedSettings === "function")
      panelLoader.item.applyPersistedSettings(entry)
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function showFeedback(message) {
    actionFeedback = message
    feedbackTimer.restart()
  }

  function actionName(action) {
    var names = {
      "pause": player.paused ? "Resume playback" : "Pause playback",
      "next": "Next song",
      "love": "Loving song",
      "ban": "Banning song",
      "tired": "Putting song on shelf",
      "volume-down": "Decrease volume",
      "volume-up": "Increase volume",
      "station": "Change station"
    }
    return names[action] || "COMMAND"
  }

  function openSettings() { if (panelLoader.item) panelLoader.item.openSettings() }
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = ["python3", helper, "status"]
    statusProcess.running = true
  }

  function saveAccount(username, password) {
    if (accountProcess.running) return
    errorText = ""
    accountPayload = JSON.stringify({ username: username, password: password }) + "\n"
    accountProcess.command = ["python3", helper, "account"]
    accountProcess.running = true
  }

  function sendAdvanced(text) {
    if (advancedProcess.running) { showFeedback("Command is already being sent"); return }
    errorText = ""
    pendingAction = "Command"
    showFeedback("Sending command…")
    advancedPayload = JSON.stringify({ text: text }) + "\n"
    advancedProcess.command = ["python3", helper, "input"]
    advancedProcess.running = true
  }

  function sendSpecialKey(key) {
    if (controlProcess.running) { showFeedback("Command is already being sent"); return }
    errorText = ""
    pendingAction = key.toUpperCase()
    showFeedback("Sending " + pendingAction.toLowerCase() + "…")
    controlProcess.command = ["python3", helper, "key", key]
    controlProcess.running = true
  }

  function runCommand(name) {
    if (controlProcess.running) { showFeedback("Command is already being sent"); return }
    errorText = ""
    pendingAction = name === "start" ? "Start playback" : (name === "stop" ? "Stop playback" : name)
    showFeedback("Sending " + pendingAction.toLowerCase() + "…")
    controlProcess.command = ["python3", helper, name]
    controlProcess.running = true
  }

  function control(action, index) {
    if (controlProcess.running) { showFeedback("Command is already being sent"); return }
    errorText = ""
    pendingAction = actionName(action)
    showFeedback(pendingAction + "…")
    var args = ["python3", helper, "control", action]
    if (index !== undefined) args.push(String(index))
    controlProcess.command = args
    controlProcess.running = true
  }

  function togglePlayback() {
    if (player.running) control("pause")
    else runCommand("start")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  Component.onCompleted: refresh()

  Timer {
    interval: 450
    running: root.trackText.length > root.windowChars
    repeat: true
    onTriggered: root.tickerOffset = (root.tickerOffset + 1) % (root.trackText.length + 5)
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: feedbackTimer
    interval: 2600
    onTriggered: root.actionFeedback = ""
  }

  Process {
    id: statusProcess
    stdout: StdioCollector { id: statusOutput; waitForEnd: true }
    onExited: function(exitCode) {
      try { root.player = exitCode === 0 ? JSON.parse(String(statusOutput.text || "{}")) : ({}) }
      catch (e) { root.player = ({}) }
    }
  }

  Process {
    id: accountProcess
    stdinEnabled: true
    onStarted: { write(root.accountPayload); root.accountPayload = "" }
    stderr: StdioCollector { id: accountError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = String(accountError.text || "Could not save account").trim()
      root.refresh()
    }
  }

  Process {
    id: advancedProcess
    stdinEnabled: true
    onStarted: { write(root.advancedPayload); root.advancedPayload = "" }
    stderr: StdioCollector { id: advancedError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = String(advancedError.text || "Player input failed").trim()
      else root.showFeedback(root.pendingAction + " sent")
      root.refresh()
    }
  }

  Process {
    id: controlProcess
    stderr: StdioCollector { id: controlError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = String(controlError.text || "Player command failed").trim()
      else root.showFeedback(root.pendingAction)
      root.refresh()
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.trackText ? "♫ " + root.tickerText + root.timeText : "♫"
    fixedWidth: root.trackText ? Style.space(root.effectiveWidth) : Style.space(34)
    tooltipText: root.trackText || (root.player.running ? "Choose a station" : "Open Pandora widget")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.togglePlayback()
      else if (buttonCode === Qt.RightButton) root.openSettings()
    }
  }
}
