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
  property bool showSettings: false
  property bool showAdvanced: false
  property bool showAccount: false
  property bool allowConfigChanges: false
  property bool confirmAccountRemoval: false
  property string username: ""
  property string password: ""

  function open() { root.showSettings = false; root.confirmAccountRemoval = false; root.controller.show() }
  function openSettings() { root.showSettings = true; root.controller.show() }
  function close() { root.confirmAccountRemoval = false; root.controller.hide() }
  function toggle() {
    if (root.opened && !root.showSettings) close()
    else open()
  }
  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(hostWidget || root, direction)
    return false
  }
  function action(name, index) { if (hostWidget) hostWidget.control(name, index) }
  function applyPersistedSettings(entry) { root.settings = entry }
  function saveAccount() {
    if (!hostWidget || !username || !password || !allowConfigChanges) return
    hostWidget.saveAccount(username, password)
    password = ""
    pwField.text = ""
    showAccount = false
    allowConfigChanges = false
  }
  function editAccount() {
    username = root.player.account || ""
    showAccount = true
    allowConfigChanges = false
    confirmAccountRemoval = false
  }
  function removeAccount() {
    if (!hostWidget) return
    if (!confirmAccountRemoval) {
      confirmAccountRemoval = true
      return
    }
    hostWidget.runCommand("remove-account")
    confirmAccountRemoval = false
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
      blocked: root.showAccount || root.showAdvanced
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Column {
          visible: !root.showSettings
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
          text: root.player.title || (root.player.missingPackages && root.player.missingPackages.length ? "Install player packages below, then save your account" : (root.player.running ? "Choose a station below" : "Save your account, then press Play"))
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
        Text {
          width: parent.width
          visible: !!root.player.title
          text: "ELAPSED " + (root.hostWidget ? root.hostWidget.formatTime(root.player.elapsed) : "0:00")
            + "  ·  REMAINING -" + (root.hostWidget ? root.hostWidget.formatTime(root.player.remaining) : "0:00")
            + "  ·  TOTAL " + (root.hostWidget ? root.hostWidget.formatTime(root.player.total) : "0:00")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
          textFormat: Text.PlainText
        }
        Row {
          spacing: Style.space(6)
          PanelActionButton { iconText: "󰐊"; visible: !root.player.configured && !(root.player.missingPackages && root.player.missingPackages.length); tooltipText: "Start pianobar"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (hostWidget) hostWidget.runCommand("start") }
          PanelActionButton { iconText: "󰏔"; visible: !!(root.player.missingPackages && root.player.missingPackages.length); tooltipText: "Install missing player packages with Polkit"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (hostWidget) hostWidget.runCommand("install") }
          PanelActionButton { iconText: "󰓛"; visible: !root.player.configured; tooltipText: "Stop pianobar"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (hostWidget) hostWidget.runCommand("stop") }
          PanelActionButton { iconText: "󰌆"; visible: !root.player.configured; tooltipText: "Save Pandora account"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: { root.showAccount = !root.showAccount; root.allowConfigChanges = false } }
          PanelActionButton { iconText: "󰏘"; visible: !!root.player.configured; tooltipText: "Edit saved Pandora account"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.editAccount() }
          PanelActionButton { iconText: root.confirmAccountRemoval ? "󰄬" : "󰆴"; visible: !!root.player.configured; tooltipText: root.confirmAccountRemoval ? "Click again to remove the saved account and stop Pianobar" : "Remove saved Pandora account"; foreground: root.confirmAccountRemoval ? Color.urgent : root.foreground; fontFamily: root.fontFamily; onClicked: root.removeAccount() }
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
          Text {
            width: parent.width
            text: "Saving updates ~/.config/pianobar/config (user, password command, FIFO, event hook) and stores your password in Secret Service."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
          }
          Text {
            width: parent.width
            text: (root.allowConfigChanges ? "☑ " : "☐ ") + "I agree to these changes"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.allowConfigChanges = !root.allowConfigChanges
            }
          }
          PanelActionButton {
            iconText: "󰄬"
            tooltipText: root.allowConfigChanges ? "Save account and start playback" : "Agree to config changes first"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.saveAccount()
          }
        }
        Row {
          spacing: Style.space(6)
          PanelActionButton { iconText: !root.player.running || root.player.paused ? "󰐊" : "󰐎"; tooltipText: !root.player.running ? "Start playback" : (root.player.paused ? "Resume playback" : "Pause playback"); foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (root.hostWidget) root.hostWidget.togglePlayback() }
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
        Rectangle {
          id: stationButton
          width: stationButtonText.implicitWidth + Style.space(22)
          height: Style.space(30)
          radius: height / 2
          border.width: Style.space(1)
          border.color: root.showStations ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
          color: stationButtonMouse.containsMouse || root.showStations
            ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            : "transparent"
          Text {
            id: stationButtonText
            anchors.centerIn: parent
            text: root.showStations ? "STATIONS  ×" : "STATIONS"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            textFormat: Text.PlainText
          }
          MouseArea {
            id: stationButtonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.showStations = !root.showStations; root.showAdvanced = false }
          }
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
        Rectangle {
          id: advancedButton
          width: advancedButtonText.implicitWidth + Style.space(22)
          height: Style.space(30)
          radius: height / 2
          border.width: Style.space(1)
          border.color: root.showAdvanced ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
          color: advancedButtonMouse.containsMouse || root.showAdvanced
            ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
            : "transparent"
          Text {
            id: advancedButtonText
            anchors.centerIn: parent
            text: root.showAdvanced ? "ADVANCED  ×" : "ADVANCED"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            textFormat: Text.PlainText
          }
          MouseArea {
            id: advancedButtonMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.showAdvanced = !root.showAdvanced; root.showStations = false }
          }
        }
        Column {
          visible: root.showAdvanced
          width: parent.width
          spacing: Style.space(6)
          Text {
            width: parent.width
            text: "PIANOBAR COMMANDS · Enter a key or prompt answer below. ? shows help."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
          }
          Flickable {
            id: consoleScroll
            width: parent.width
            height: visible ? Style.space(220) : 0
            contentWidth: width
            contentHeight: consoleText.implicitHeight
            clip: true
            onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
            Text {
              id: consoleText
              width: consoleScroll.width
              text: root.player.console || "Start pianobar to see its command output"
              color: root.foreground
              font.family: "monospace"
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WrapAnywhere
              textFormat: Text.PlainText
            }
          }
          TextField {
            id: commandField
            width: parent.width
            placeholderText: "Command key or answer, then Enter"
            onAccepted: {
              if (root.hostWidget) root.hostWidget.sendAdvanced(text)
              text = ""
            }
          }
          Row {
            spacing: Style.space(6)
            PanelActionButton { iconText: "?"; tooltipText: "Pianobar help"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (root.hostWidget) root.hostWidget.sendAdvanced("?") }
            PanelActionButton { iconText: "↑"; tooltipText: "Up"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (root.hostWidget) root.hostWidget.sendSpecialKey("Up") }
            PanelActionButton { iconText: "↓"; tooltipText: "Down"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (root.hostWidget) root.hostWidget.sendSpecialKey("Down") }
            PanelActionButton { iconText: "↵"; tooltipText: "Enter"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (root.hostWidget) root.hostWidget.sendSpecialKey("Enter") }
            PanelActionButton { iconText: "Esc"; tooltipText: "Escape"; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: if (root.hostWidget) root.hostWidget.sendSpecialKey("Escape") }
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
        Text {
          width: parent.width
          text: root.hostWidget ? root.hostWidget.pluginVersion : ""
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignRight
          textFormat: Text.PlainText
        }
        }

        Column {
          visible: root.showSettings
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: "PANDORA BAR SETTINGS"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Text {
            text: "Minimum width while playing: " + (root.hostWidget ? root.hostWidget.playingWidth : 230) + " px"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Row {
            spacing: Style.space(8)
            PanelActionButton {
              iconText: "−"
              tooltipText: "Narrower"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.hostWidget) root.hostWidget.setOption("playingWidth", Math.max(120, root.hostWidget.playingWidth - 20))
            }
            PanelActionButton {
              iconText: "+"
              tooltipText: "Wider"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.hostWidget) root.hostWidget.setOption("playingWidth", Math.min(500, root.hostWidget.playingWidth + 20))
            }
          }
          Repeater {
            model: [
              { key: "showElapsed", label: "Elapsed time" },
              { key: "showRemaining", label: "Remaining time" },
              { key: "showTotal", label: "Total time" }
            ]
            Rectangle {
              id: settingRow
              required property var modelData
              width: content.width
              height: Style.space(28)
              color: toggleMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ((root.hostWidget && root.hostWidget[settingRow.modelData.key]) ? "☑ " : "☐ ") + settingRow.modelData.label
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
              MouseArea {
                id: toggleMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.hostWidget) root.hostWidget.setOption(settingRow.modelData.key, !root.hostWidget[settingRow.modelData.key])
              }
            }
          }
          PanelActionButton {
            iconText: "󰅁"
            tooltipText: "Back to player"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.showSettings = false
          }
        }
      }
    }
  }
}
