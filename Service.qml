import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Polls Synology Chat through scripts/synochat and keeps the panel's data.
Item {
  id: root

  property var settings: ({})
  // The channel the panel is showing; no notifications for it while open.
  property var activeChannelId: null
  property bool panelOpen: false

  readonly property string script: String(Qt.resolvedUrl("scripts/synochat")).replace(/^file:\/\//, "")
  readonly property string server: String(setting("server", ""))
  readonly property string username: String(setting("username", ""))
  readonly property bool verifyTls: setting("verifyTls", "Off") === "On"
  readonly property bool notifications: setting("notifications", "On") === "On"
  // Undocumented in the settings UI: made-up data for screenshots.
  readonly property bool demo: String(setting("demo", "Off")) === "On"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 20, 5, 3600)

  property bool loaded: false
  property bool needsSetup: false
  property string lastError: ""
  property var channels: []
  readonly property var sortedChannels: Model.sortChannels(channels)
  readonly property int unread: Model.totalUnread(channels)

  property var posts: []
  property var postsChannelId: null
  readonly property bool loadingPosts: postsProcess.running
  readonly property bool sending: sendProcess.running

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(min, Math.min(max, n))
  }

  function command(args) {
    return ["env",
      "SYNOCHAT_SERVER=" + server,
      "SYNOCHAT_USER=" + username,
      "SYNOCHAT_VERIFY=" + (verifyTls ? "1" : "0"),
      "SYNOCHAT_DEMO=" + (demo ? "1" : "0"),
      script].concat(args)
  }

  function refresh() {
    if (channelsProcess.running) return
    channelsProcess.command = command(["channels"])
    channelsProcess.running = true
    watchdog.restart()
  }

  function loadPosts(id) {
    if (postsChannelId !== id) posts = []
    postsChannelId = id
    if (postsProcess.running) {
      postsProcess.reloadAfter = true
      return
    }
    postsProcess.channelId = id
    postsProcess.command = command(["posts", String(id), "40"])
    postsProcess.running = true
  }

  function markRead(id) {
    var ch = channels.find(function(c) { return c.id === id })
    if (!ch || ch.unread === 0) return
    channels = channels.map(function(c) {
      return c.id === id ? Object.assign({}, c, { unread: 0, mentions: 0 }) : c
    })
    Quickshell.execDetached(command(["read", String(id)]))
  }

  function send(id, text) {
    var message = String(text || "").trim()
    if (message === "" || sendProcess.running) return false
    lastError = ""
    sendProcess.channelId = id
    sendProcess.command = command(["send", String(id), message])
    sendProcess.running = true
    return true
  }

  function openLink(url) {
    Quickshell.execDetached(["xdg-open", String(url)])
  }

  function openFile(postId, name) {
    Quickshell.execDetached(command(["open-file", String(postId), String(name)]))
  }

  function openApp() {
    Quickshell.execDetached(["synology-chat"])
  }

  function setupInTerminal() {
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation",
      command(["setup"]).map(function(a) { return "'" + String(a).replace(/'/g, "'\\''") + "'" }).join(" ")])
    setupTimer.restart()
  }

  function applyChannels(raw, exitCode) {
    var result = Model.parse(raw, "channels")
    needsSetup = exitCode === 2
    if (result.error !== "") {
      lastError = needsSetup ? "" : result.error
      return
    }
    lastError = ""
    var next = result.items
    if (loaded && notifications) {
      Model.newlyUnread(channels, next).forEach(function(ch) {
        if (root.panelOpen && root.activeChannelId === ch.id) return
        Quickshell.execDetached(root.command(["notify", String(ch.id), ch.name, String(ch.count)]))
      })
    }
    channels = next
    loaded = true
    // Keep the open conversation live, and read since the user is looking at it.
    if (panelOpen && activeChannelId !== null) {
      var active = next.find(function(c) { return c.id === root.activeChannelId })
      if (active && active.unread > 0) {
        loadPosts(activeChannelId)
        markRead(activeChannelId)
      }
    }
  }

  Timer {
    interval: (root.panelOpen ? 5 : root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // After setup runs in a terminal, poll until it works.
  Timer {
    id: setupTimer
    interval: 3000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.refresh()
      if (!root.needsSetup || ticks > 40) stop()
    }
  }

  Timer {
    id: watchdog
    interval: 20000
    onTriggered: if (channelsProcess.running) channelsProcess.running = false
  }

  Process {
    id: channelsProcess
    stdout: StdioCollector { id: channelsOut; waitForEnd: true }
    onExited: function(exitCode) {
      watchdog.stop()
      root.applyChannels(channelsOut.text, exitCode)
    }
  }

  Process {
    id: postsProcess
    property var channelId: null
    property bool reloadAfter: false
    stdout: StdioCollector { id: postsOut; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parse(postsOut.text, "posts")
      if (result.error !== "") root.lastError = result.error
      else if (postsProcess.channelId === root.postsChannelId) root.posts = result.items
      if (postsProcess.reloadAfter) {
        postsProcess.reloadAfter = false
        Qt.callLater(function() { root.loadPosts(root.postsChannelId) })
      }
    }
  }

  Process {
    id: sendProcess
    property var channelId: null
    stdout: StdioCollector { id: sendOut; waitForEnd: true }
    onExited: function(exitCode) {
      var result = Model.parse(sendOut.text, "ok")
      if (exitCode !== 0) root.lastError = result.error || "Sending failed"
      if (sendProcess.channelId === root.postsChannelId) root.loadPosts(sendProcess.channelId)
    }
  }
}
