import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.nicholasladwig.pianobar-pandora-widget"

  property string pluginVersion: "1.5.3"
  property var state: ({})
  property var environment: ({})
  property string consoleText: ""
  property string errorText: ""
  property string actionFeedback: ""
  property string pendingAction: ""
  property string accountPayload: ""
  property string advancedPayload: ""
  property double displayNow: Date.now()
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/" + moduleName
  readonly property string statePath: cacheDir + "/state.json"
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("bridge.py").toString().replace(/^file:\/\//, ""))
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool advancedOpen: panelLoader.item ? panelLoader.item.showAdvanced === true : false
  readonly property bool advancedPasswordPrompt: Model.passwordPrompt(consoleText)
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property int playingWidth: Model.clamp(setting("playingWidth", 230), 120, 500)
  readonly property bool showElapsed: setting("showElapsed", true) === true
  readonly property bool showRemaining: setting("showRemaining", true) === true
  readonly property bool showTotal: setting("showTotal", false) === true
  readonly property int elapsed: Model.elapsedFrom(state, displayNow, environment.running === true)
  readonly property int remaining: Model.remainingFrom(state, displayNow, environment.running === true)
  readonly property int total: Math.max(0, Math.floor(Number(state.durationSeconds) || 0))
  readonly property var player: {
    var result = {}
    for (var stateKey in state) result[stateKey] = state[stateKey]
    for (var environmentKey in environment) result[environmentKey] = environment[environmentKey]
    result.elapsed = elapsed
    result.remaining = remaining
    result.total = total
    result.console = consoleText
    if (!result.running) {
      result.title = ""
      result.upcoming = []
      result.waitingForStation = false
    }
    return result
  }
  readonly property string trackText: player.running && player.title ? player.artist + " — " + player.title : ""
  readonly property string timeText: {
    if (!trackText) return ""
    var fields = []
    if (showElapsed) fields.push(Model.formatTime(elapsed))
    if (showRemaining) fields.push("-" + Model.formatTime(remaining))
    if (showTotal) fields.push(Model.formatTime(total))
    return fields.length ? fields.join(" / ") : ""
  }

  function formatTime(value) { return Model.formatTime(value) }

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

  function parseState(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      state = parsed && typeof parsed === "object" ? parsed : ({})
    } catch (e) { state = ({}) }
  }

  function refreshEnv() {
    if (envProcess.running) return
    envProcess.command = ["python3", helper, "env"]
    envProcess.running = true
  }

  function refreshConsole() {
    if (!advancedOpen || consoleProcess.running) return
    consoleProcess.command = ["python3", helper, "console"]
    consoleProcess.running = true
  }

  function saveAccount(username, password) {
    if (accountProcess.running) return
    errorText = ""
    accountPayload = JSON.stringify({ username: username, password: password }) + "\n"
    accountProcess.command = ["python3", helper, "account"]
    accountProcess.running = true
  }

  function sendAdvanced(text) {
    if (advancedPasswordPrompt) { showFeedback("Use Edit Account to save the password securely"); return }
    if (advancedProcess.running) { showFeedback("Command is already being sent"); return }
    errorText = ""
    pendingAction = "Command"
    showFeedback("Sending command…")
    advancedPayload = JSON.stringify({ text: text }) + "\n"
    advancedProcess.command = ["python3", helper, "input"]
    advancedProcess.running = true
  }

  function sendSpecialKey(key) {
    if (advancedPasswordPrompt) { showFeedback("Use Edit Account to save the password securely"); return }
    if (controlProcess.running) { showFeedback("Command is already being sent"); return }
    errorText = ""
    pendingAction = key
    showFeedback("Sending " + key.toLowerCase() + "…")
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
    pendingAction = Model.actionName(action, player.paused === true)
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
  onOpenedChanged: refreshEnv()
  onAdvancedOpenChanged: {
    if (advancedOpen) refreshConsole()
    else consoleText = ""
  }
  Component.onCompleted: refreshEnv()

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseState(text())
    onFileChanged: reload()
    onLoadFailed: root.state = ({})
  }

  FileView {
    path: root.cacheDir
    watchChanges: true
    printErrors: false
    onFileChanged: stateFile.reload()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: stateFile.reload()
  }

  Timer {
    interval: root.opened ? 5000 : 15000
    running: true
    repeat: true
    onTriggered: root.refreshEnv()
  }

  Timer {
    interval: 1000
    running: root.advancedOpen
    repeat: true
    onTriggered: root.refreshConsole()
  }

  Timer {
    interval: 1000
    running: !!root.trackText && !root.player.paused && (root.showElapsed || root.showRemaining || root.showTotal || root.opened)
    repeat: true
    onTriggered: root.displayNow = Date.now()
  }

  Timer {
    id: feedbackTimer
    interval: 2600
    onTriggered: root.actionFeedback = ""
  }

  Process {
    id: envProcess
    stdout: StdioCollector { id: envOutput; waitForEnd: true }
    onExited: function(exitCode) {
      try { root.environment = exitCode === 0 ? JSON.parse(String(envOutput.text || "{}")) : ({}) }
      catch (e) { root.environment = ({}) }
    }
  }

  Process {
    id: consoleProcess
    stdout: StdioCollector { id: consoleOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try { root.consoleText = JSON.parse(String(consoleOutput.text || "{}"))["console"] || "" }
      catch (e) { root.consoleText = "" }
    }
  }

  Process {
    id: accountProcess
    stdinEnabled: true
    onStarted: { write(root.accountPayload); root.accountPayload = "" }
    stderr: StdioCollector { id: accountError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = String(accountError.text || "Could not save account").trim()
      root.refreshEnv()
      stateFile.reload()
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
      root.refreshConsole()
    }
  }

  Process {
    id: controlProcess
    stderr: StdioCollector { id: controlError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = String(controlError.text || "Player command failed").trim()
      else root.showFeedback(root.pendingAction)
      root.refreshEnv()
      stateFile.reload()
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
    text: "♫"
    labelVisible: false
    fixedWidth: root.vertical ? Style.space(34) : (root.trackText ? Style.space(root.playingWidth) : Style.space(34))
    tooltipText: root.trackText || (root.player.running ? "Choose a station" : "Open Pandora widget")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.togglePlayback()
      else if (buttonCode === Qt.RightButton) root.openSettings()
    }

    Row {
      id: labelRow
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(6)

      Text {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        text: "♫"
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }

      Item {
        id: scrollClip
        width: root.trackText && !root.vertical ? Math.max(0, labelRow.width - glyph.implicitWidth - labelRow.spacing - (timeLabel.visible ? timeLabel.implicitWidth + labelRow.spacing : 0)) : 0
        height: glyph.implicitHeight
        clip: true
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && !!root.trackText

        Text {
          id: trackLabel
          anchors.verticalCenter: parent.verticalCenter
          text: root.trackText
          color: root.bar ? root.bar.barForeground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          textFormat: Text.PlainText
          property bool needsScroll: implicitWidth > scrollClip.width

          NumberAnimation on x {
            running: trackLabel.needsScroll && !root.opened && !root.vertical
            loops: Animation.Infinite
            duration: Math.max(6000, trackLabel.implicitWidth * 25)
            from: scrollClip.width
            to: -trackLabel.implicitWidth
            easing.type: Easing.Linear
          }
        }
      }

      Text {
        id: timeLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: !root.vertical && !!root.timeText
        text: root.timeText
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        textFormat: Text.PlainText
      }
    }
  }
}
