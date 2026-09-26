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
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: function(data) {
      try { root.player = JSON.parse(data || "{}") } catch (e) { root.player = ({}) }
    } }
  }

  Process {
    id: controlProcess
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: function(data) { if (data.trim()) root.errorText = data.trim() } }
    onExited: root.refresh()
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
    text: root.player.running && root.player.title ? "♫ " + (root.player.artist + " — " + root.player.title).slice(0, 48) : "♫ Pandora"
    tooltipText: root.player.running ? (root.player.station || "Pianobar") : "Pianobar is not running"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.control("pause")
      else if (buttonCode === Qt.RightButton) root.control("next")
    }
  }
}
