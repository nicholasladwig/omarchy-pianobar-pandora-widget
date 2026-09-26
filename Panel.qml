import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.nicholasladwig.pianobar-pandora-widget"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var player: hostWidget ? hostWidget.player : ({})
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property bool showStations: false
  property bool showAccount: false
  property string username: ""
  property string password: ""

  function open() { root.controller.show() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) close(); else open() }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(hostWidget || root, direction)
    return false
  }
  function action(name, index) { if (hostWidget) hostWidget.control(name, index) }
  function saveAccount() {
    if (!hostWidget || !username || !password) return
    hostWidget.saveAccount(username, password)
    password = ""
    pwField.text = ""
    showAccount = false
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(390))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.showAccount
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: root.player.running ? (root.player.station || "Pandora") : "Pianobar is not running"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
        Text {
          width: parent.width
          text: root.player.title || (root.player.running ? "Choose a station below" : "Save your account, then press Play")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
        }
        Text {
          width: parent.width
          visible: !!root.player.artist
          text: root.player.artist + (root.player.album ? " · " + root.player.album : "")
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
        Row {
          spacing: Style.space(6)
          PanelActionButton { iconText: "󰐊"; tooltipText: "Start pianobar"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (hostWidget) hostWidget.runCommand("start") }
          PanelActionButton { iconText: "󰌆"; tooltipText: "Save Pandora account"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.showAccount = !root.showAccount }
          PanelActionButton { iconText: "󰆍"; tooltipText: "Open pianobar in terminal"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (hostWidget) hostWidget.runCommand("terminal") }
        }
        Column {
          visible: root.showAccount
          width: parent.width
          spacing: Style.space(5)
          TextField {
            width: parent.width
            placeholderText: "Pandora email or username"
            text: root.username
            onTextChanged: root.username = text
          }
          TextField {
            id: pwField
            width: parent.width
            placeholderText: "Pandora password"
            password: true
            text: root.password
            onTextChanged: root.password = text
            onAccepted: root.saveAccount()
            Keys.onEscapePressed: root.showAccount = false
          }
          PanelActionButton {
            iconText: "󰄬"
            tooltipText: "Save account and start playback"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.saveAccount()
          }
        }
        Row {
          spacing: Style.space(6)
          PanelActionButton { iconText: "󰐎"; tooltipText: "Pause or resume"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.action("pause") }
          PanelActionButton { iconText: "󰒭"; tooltipText: "Next song"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.action("next") }
          PanelActionButton { iconText: "󰋑"; tooltipText: "Love song"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.action("love") }
          PanelActionButton { iconText: "󰂭"; tooltipText: "Ban song"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.action("ban") }
          PanelActionButton { iconText: "󰔌"; tooltipText: "Tired of song"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.action("tired") }
          PanelActionButton { iconText: "󰖀"; tooltipText: "Volume down"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.action("volume-down") }
          PanelActionButton { iconText: "󰕾"; tooltipText: "Volume up"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.action("volume-up") }
        }
        Text {
          text: "UP NEXT"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
        Repeater {
          model: root.player.upcoming || []
          Text {
            required property var modelData
            width: content.width
            text: modelData.artist + " — " + modelData.title
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            textFormat: Text.PlainText
          }
        }
        Text {
          visible: !(root.player.upcoming && root.player.upcoming.length)
          text: "No upcoming songs reported"
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        PanelActionButton {
          iconText: "󰓇"
          tooltipText: root.showStations ? "Hide stations" : "Switch station"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.showStations = !root.showStations
        }
        Flickable {
          visible: root.showStations
          width: parent.width
          height: visible ? Math.min(stationColumn.implicitHeight, Style.space(250)) : 0
          contentWidth: width
          contentHeight: stationColumn.implicitHeight
          clip: true
          Column {
            id: stationColumn
            width: parent.width
            spacing: Style.space(4)
            Repeater {
              model: root.player.stations || []
              Rectangle {
                required property string modelData
                required property int index
                width: stationColumn.width
                height: stationText.implicitHeight + Style.space(10)
                color: stationMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
                Text {
                  id: stationText
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width
                  text: modelData
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                  textFormat: Text.PlainText
                }
                MouseArea {
                  id: stationMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.action("station", index); root.showStations = false }
                }
              }
            }
          }
        }
        Text {
          width: parent.width
          visible: (hostWidget && !!hostWidget.errorText) || !!root.player.error
          text: hostWidget && hostWidget.errorText ? hostWidget.errorText : (root.player.error || "")
          color: Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
        }
      }
    }
  }
}
