import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.nicholasladwig.pianobar-pandora-widget"

  property var player: ({})
  property string errorText: ""
  property string output: ""
  property int tickerOffset: 0
  property string accountPayload: ""
  readonly property string trackText: player.running && player.title ? player.artist + " — " + player.title : ""
  readonly property string tickerText: trackText.length <= 24 ? trackText : (trackText + "     " + trackText).slice(tickerOffset, tickerOffset + 24)
  onTrackTextChanged: tickerOffset = 0
  readonly property string helper: Qt.resolvedUrl("bridge.py").toString().replace(/^file:\/\//, "")
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

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
    output = ""
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

  function runCommand(name) {
    if (controlProcess.running) return
    errorText = ""
    controlProcess.command = ["python3", helper, name]
    controlProcess.running = true
  }

  function control(action, index) {
    if (controlProcess.running) return
    errorText = ""
    var args = ["python3", helper, "control", action]
    if (index !== undefined) args.push(String(index))
    controlProcess.command = args
    controlProcess.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  Component.onCompleted: refresh()

  Timer {
    interval: 350
    running: root.trackText.length > 24
    repeat: true
    onTriggered: root.tickerOffset = (root.tickerOffset + 1) % (root.trackText.length + 5)
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
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
    id: controlProcess
    stderr: StdioCollector { id: controlError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.errorText = String(controlError.text || "Pianobar command failed").trim()
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
    text: root.trackText ? "♫ " + root.tickerText : "♫"
    fixedWidth: root.trackText ? Style.space(230) : Style.space(34)
    tooltipText: root.trackText || (root.player.running ? "Choose a station" : "Open Pandora widget")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.control("pause")
      else if (buttonCode === Qt.RightButton) root.runCommand("terminal")
    }
  }
}
