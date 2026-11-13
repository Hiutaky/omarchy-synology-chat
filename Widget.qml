import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Synology Chat in the bar. The icon carries the unread count; the panel
// lists channels and direct messages, and opens one to read and reply.
Panel {
  id: root
  moduleName: "hiutaky.synology-chat"
  ipcTarget: "hiutaky.synology-chat"
  manageIpc: false

  // "list" or "chat"; setup is derived from the service.
  property string view: "list"
  property var channel: null
  property int cursorIndex: -1

  readonly property string glyph: "󰭹"
  readonly property string stage: chat.needsSetup ? "setup" : view
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string linkColor: String(Color.accent)
  readonly property bool darkTheme: Color.background.hslLightness < 0.5
  readonly property color mineFill: Qt.alpha(Color.accent, 0.16)
  readonly property color otherFill: Qt.alpha(foreground, 0.05)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property var channels: chat.sortedChannels

  function openChannel(ch) {
    if (!ch) return
    channel = ch
    view = "chat"
    chat.activeChannelId = ch.id
    chat.loadPosts(ch.id)
    chat.markRead(ch.id)
    Qt.callLater(function() { messageField.forceActiveFocus() })
  }

  function backToList() {
    view = "list"
    chat.activeChannelId = null
    messageField.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function sendMessage() {
    if (!channel) return
    if (chat.send(channel.id, messageField.text)) messageField.text = ""
  }

  function moveCursor(dy) {
    if (channels.length === 0) return
    if (cursorIndex < 0) cursorIndex = 0
    else cursorIndex = Math.max(0, Math.min(channels.length - 1, cursorIndex + dy))
    channelList.positionViewAtIndex(cursorIndex, ListView.Contain)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    chat.panelOpen = opened
    if (opened) {
      cursorIndex = -1
      chat.refresh()
      if (view === "chat" && channel) openChannel(channel)
      else Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      pendingProcess.running = true
    } else {
      chat.activeChannelId = null
    }
  }

  Service {
    id: chat
    settings: root.settings
  }

  // There is one widget per monitor but only one of them owns this IPC target,
  // so opening goes through the shell, which picks the focused monitor's bar.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.shellCall("summon") }
    function show(): void { root.shellCall("summon") }
    function toggle(): void { root.shellCall("toggle") }
    function close(): void { Quickshell.execDetached(["omarchy-shell", "shell", "hide", root.moduleName]) }
    function hide(): void { Quickshell.execDetached(["omarchy-shell", "shell", "hide", root.moduleName]) }
    function refresh(): string { chat.refresh(); return "ok" }
    function unread(): int { return chat.unread }
    function openChannel(id: int): void {
      Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" > \"$2\" && omarchy-shell shell summon \"$3\" '{}'",
        "sh", String(id), root.pendingFile, root.moduleName])
    }
  }

  readonly property string pendingFile: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-synochat.open-channel"

  function shellCall(method) {
    Quickshell.execDetached(["omarchy-shell", "shell", method, moduleName, "{}"])
  }

  // Picks up a channel requested through `openChannel` when this panel opens.
  Process {
    id: pendingProcess
    command: ["sh", "-c", "f=\"$1\"; [ -f \"$f\" ] && cat \"$f\" && rm -f \"$f\"", "sh", root.pendingFile]
    stdout: StdioCollector { id: pendingOut; waitForEnd: true }
    onExited: {
      var id = parseInt(String(pendingOut.text || "").trim(), 10)
      if (!isFinite(id)) return
      var ch = chat.channels.find(function(c) { return c.id === id })
      if (ch) root.openChannel(ch)
      else root.pendingChannelId = id
    }
  }

  // A channel asked for before the first channel list arrived.
  property var pendingChannelId: null
  Connections {
    target: chat
    function onChannelsChanged() {
      if (root.pendingChannelId === null || !root.opened) return
      var ch = chat.channels.find(function(c) { return c.id === root.pendingChannelId })
      root.pendingChannelId = null
      if (ch) root.openChannel(ch)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    foreground: chat.unread > 0 ? root.urgent : (chat.loaded ? root.barForeground : Qt.darker(root.barForeground, 1.55))
    tooltipText: root.opened ? "" : (chat.needsSetup ? "Synology Chat: not set up"
      : chat.lastError !== "" ? "Synology Chat: " + chat.lastError
      : chat.unread > 0 ? "Synology Chat: " + chat.unread + " unread" : "Synology Chat")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) chat.openApp()
      else if (buttonCode === Qt.RightButton) chat.refresh()
      else root.toggle()
    }

    Rectangle {
      visible: chat.unread > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(1)
      anchors.topMargin: Style.space(2)
      height: Math.round(Style.font.caption * 1.25)
      width: Math.max(height, badgeText.implicitWidth + Style.space(5))
      radius: height / 2
      color: root.urgent

      Text {
        id: badgeText
        anchors.centerIn: parent
        text: chat.unread > 99 ? "99+" : String(chat.unread)
        color: Color.background
        font.family: root.fontFamily
        font.pixelSize: Math.round(Style.font.caption * 0.9)
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: root.view === "chat" ? messageField : keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.cappedContentHeight(Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { if (dy !== 0 && root.stage === "list") root.moveCursor(dy) }
      onActivateRequested: {
        if (root.stage === "setup") chat.setupInTerminal()
        else if (root.stage === "list" && root.cursorIndex >= 0) root.openChannel(root.channels[root.cursorIndex])
      }
      onCloseRequested: root.stage === "chat" ? root.backToList() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = t.toLowerCase()
        if (key === "r") chat.refresh()
        else if (key === "o") { chat.openApp(); root.close() }
      }

      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(10)

        // ------------------------------------------------------------ header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          PanelActionButton {
            visible: root.stage === "chat"
            iconText: "󰁍"
            tooltipText: "Back (Esc)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.backToList()
          }

          Text {
            text: root.stage === "chat" && root.channel ? Model.channelIcon(root.channel) : root.glyph
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Text {
              Layout.fillWidth: true
              text: root.stage === "chat" && root.channel ? root.channel.name : "Synology Chat"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              Layout.fillWidth: true
              text: root.stage === "chat" ? (chat.loadingPosts && chat.posts.length === 0 ? "Loading…" : chat.posts.length + " recent messages")
                : root.stage === "setup" ? "Not set up"
                : chat.unread > 0 ? chat.unread + (chat.unread === 1 ? " unread message" : " unread messages") : (chat.loaded ? "No unread messages" : "Connecting…")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          PanelActionButton {
            iconText: "󰏌"
            tooltipText: "Open Synology Chat (o)"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: { chat.openApp(); root.close() }
          }
        }

        PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

        Text {
          visible: chat.lastError !== ""
          Layout.fillWidth: true
          text: chat.lastError
          textFormat: Text.PlainText
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // ------------------------------------------------------------- setup
        ColumnLayout {
          visible: root.stage === "setup"
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            Layout.fillWidth: true
            text: "Connect to your Synology NAS: enter the DSM address, user and password in a terminal. The password is stored in the system keyring."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          ActionRow {
            Layout.fillWidth: true
            icon: "󰌆"
            label: "Set up Synology Chat"
            detail: "Opens a terminal"
            hasCursor: true
            onActivated: chat.setupInTerminal()
          }
        }

        // ------------------------------------------------------ channel list
        ListView {
          id: channelList
          visible: root.stage === "list"
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.space(2)
          boundsBehavior: Flickable.StopAtBounds
          model: root.channels
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: ActionRow {
            required property var modelData
            required property int index
            width: channelList.width
            icon: Model.channelIcon(modelData)
            label: modelData.name
            detail: Model.channelDetail(modelData)
            current: modelData.unread > 0
            hasCursor: root.cursorIndex === index
            onHoveredRow: root.cursorIndex = index
            onActivated: root.openChannel(modelData)
          }
        }

        // ------------------------------------------------------ conversation
        ListView {
          id: postList
          visible: root.stage === "chat"
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.space(8)
          boundsBehavior: Flickable.StopAtBounds
          model: chat.posts
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
          onCountChanged: Qt.callLater(positionViewAtEnd)
          onVisibleChanged: if (visible) Qt.callLater(positionViewAtEnd)

          delegate: Item {
            id: postItem
            required property var modelData
            required property int index
            readonly property var prev: index > 0 ? chat.posts[index - 1] : null
            // Consecutive messages from the same person within 5 minutes share one header.
            readonly property bool grouped: prev !== null && prev.authorId === modelData.authorId && modelData.at - prev.at < 300000
            readonly property bool mine: modelData.mine
            readonly property color authorColor: Model.userColor(modelData.authorId, root.darkTheme)
            readonly property real avatarSize: Style.space(28)
            readonly property real gutter: mine ? 0 : avatarSize + Style.space(8)
            readonly property real maxBubble: Math.round((width - gutter) * 0.82)
            readonly property real pad: Style.space(8)
            readonly property bool hasAttachment: modelData.file !== null || modelData.links.some(function(l) { return l.title !== "" })
            readonly property real contentWidth: hasAttachment ? maxBubble - pad * 2
              : Math.min(maxBubble - pad * 2, Math.max(measure.implicitWidth + 2, grouped ? Style.space(40) : header.implicitWidth))

            width: postList.width - Style.space(10)
            height: bubble.height + (grouped ? 0 : Style.space(4))

            Text {
              id: measure
              visible: false
              text: Model.richText(modelData.text, root.linkColor)
              textFormat: Text.RichText
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            // Avatar of the other person, on the first message of a group.
            Item {
              id: avatarBox
              visible: !postItem.mine && !postItem.grouped
              anchors.left: parent.left
              anchors.bottom: bubble.bottom
              width: postItem.avatarSize
              height: postItem.avatarSize

              Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: postItem.authorColor
                visible: avatarImage.status !== Image.Ready

                Text {
                  anchors.centerIn: parent
                  text: Model.initials(modelData.author)
                  color: Color.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Image {
                id: avatarImage
                anchors.fill: parent
                visible: false
                source: modelData.avatar ? "file://" + modelData.avatar : ""
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }

              Rectangle {
                id: avatarMask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
              }

              MultiEffect {
                anchors.fill: parent
                visible: avatarImage.status === Image.Ready
                source: avatarImage
                maskEnabled: true
                maskSource: avatarMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
              }
            }

            Rectangle {
              id: bubble
              anchors.top: parent.top
              anchors.topMargin: postItem.grouped ? 0 : Style.space(4)
              x: postItem.mine ? parent.width - width : postItem.gutter
              width: postItem.contentWidth + postItem.pad * 2
              height: bubbleColumn.implicitHeight + postItem.pad * 2
              radius: Style.space(10)
              color: postItem.mine ? root.mineFill : root.otherFill
              border.width: 1
              border.color: postItem.mine ? Qt.alpha(root.foreground, 0.12) : Qt.alpha(postItem.authorColor, 0.35)

              Column {
                id: bubbleColumn
                x: postItem.pad
                y: postItem.pad
                width: postItem.contentWidth
                spacing: Style.space(3)

                Row {
                  id: header
                  visible: !postItem.grouped
                  spacing: Style.space(6)
                  layoutDirection: postItem.mine ? Qt.RightToLeft : Qt.LeftToRight
                  anchors.right: postItem.mine ? parent.right : undefined

                  Text {
                    id: authorText
                    text: postItem.mine ? "You" : modelData.author
                    textFormat: Text.PlainText
                    color: postItem.mine ? root.dim : postItem.authorColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Text {
                    text: Model.formatTime(modelData.at)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    height: authorText.height
                    verticalAlignment: Text.AlignVCenter
                  }
                }

                TextEdit {
                  id: messageText
                  visible: modelData.text !== ""
                  width: parent.width
                  text: Model.richText(modelData.text, root.linkColor)
                  textFormat: TextEdit.RichText
                  readOnly: true
                  selectByMouse: true
                  wrapMode: TextEdit.Wrap
                  color: root.foreground
                  selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  onLinkActivated: function(link) { chat.openLink(link) }

                  HoverHandler {
                    cursorShape: messageText.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.IBeamCursor
                  }
                }

                // Link previews the server fetched (title of the page).
                Repeater {
                  model: modelData.links.filter(function(l) { return l.title !== "" })
                  CursorSurface {
                    required property var modelData
                    width: parent.width
                    foreground: root.foreground
                    fill: root.hoverFill
                    bordered: true
                    hasCursor: linkMouse.containsMouse
                    implicitHeight: linkColumn.implicitHeight + Style.space(10)

                    MouseArea {
                      id: linkMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: chat.openLink(parent.modelData.url)
                    }

                    Column {
                      id: linkColumn
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(8)
                      anchors.rightMargin: Style.space(8)
                      spacing: Style.space(1)

                      Text {
                        width: parent.width
                        text: "󰌹  " + parent.parent.modelData.title
                        textFormat: Text.PlainText
                        color: root.linkColor
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                      }

                      Text {
                        visible: text !== ""
                        width: parent.width
                        text: parent.parent.modelData.description
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                // Image preview: click opens the full image.
                Image {
                  id: thumb
                  visible: modelData.file !== null && modelData.file.image && modelData.file.thumb !== "" && status === Image.Ready
                  source: modelData.file && modelData.file.thumb ? "file://" + modelData.file.thumb : ""
                  asynchronous: true
                  fillMode: Image.PreserveAspectFit
                  width: Math.min(parent.width, Style.space(300), sourceSize.width)
                  height: sourceSize.width > 0 ? width * sourceSize.height / sourceSize.width : 0

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chat.openFile(modelData.id, modelData.file.name)
                  }
                }

                // Any other attachment (or an image without preview): click downloads and opens it.
                CursorSurface {
                  visible: modelData.file !== null && !thumb.visible
                  width: parent.width
                  foreground: root.foreground
                  fill: root.hoverFill
                  bordered: true
                  hasCursor: fileMouse.containsMouse
                  implicitHeight: fileRow.implicitHeight + Style.space(10)

                  MouseArea {
                    id: fileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: chat.openFile(modelData.id, modelData.file.name)
                  }

                  RowLayout {
                    id: fileRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)

                    Text {
                      text: modelData.file ? Model.fileIcon(modelData.file) : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.icon
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 0

                      Text {
                        Layout.fillWidth: true
                        text: modelData.file ? modelData.file.name : ""
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideMiddle
                      }

                      Text {
                        Layout.fillWidth: true
                        visible: modelData.file !== null && modelData.file.preview !== ""
                        text: modelData.file ? modelData.file.preview.split("\n").slice(0, 2).join(" ") : ""
                        textFormat: Text.PlainText
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }

                    Text {
                      text: (modelData.file ? Model.formatSize(modelData.file.size) : "") + "  󰇚"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }
        }

        TextField {
          id: messageField
          visible: root.stage === "chat"
          Layout.fillWidth: true
          placeholderText: chat.sending ? "Sending…" : "Write a message, Enter to send"
          enabled: !chat.sending
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          onAccepted: root.sendMessage()
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              root.backToList()
              event.accepted = true
            } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
              postList.flick(0, (event.key === Qt.Key_PageUp ? 1 : -1) * postList.height * 4)
              event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
              root.switchPanel(event.key === Qt.Key_Backtab || (event.modifiers & Qt.ShiftModifier) ? -1 : 1)
              event.accepted = true
            }
          }
          // The field keeps focus while sending is disabled and back after.
          onEnabledChanged: if (enabled && root.stage === "chat") forceActiveFocus()
        }
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property string icon: ""
    property string label: ""
    property string detail: ""
    signal activated()
    signal hoveredRow()

    foreground: root.foreground
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: actionRow.hoveredRow()
      onClicked: actionRow.activated()
    }

    RowLayout {
      id: actionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      Text {
        text: actionRow.icon
        textFormat: Text.PlainText
        color: actionRow.hasCursor || actionRow.current ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.preferredWidth: Style.space(20)
        horizontalAlignment: Text.AlignHCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: actionRow.label
          textFormat: Text.PlainText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: actionRow.current
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          visible: actionRow.detail !== ""
          text: actionRow.detail
          textFormat: Text.PlainText
          color: actionRow.current ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
