.pragma library

function parse(raw, key) {
  try {
    var data = JSON.parse(String(raw || "").trim() || "{}")
    if (data.error) return { error: String(data.error), items: [] }
    return { error: "", items: data[key] || [] }
  } catch (e) {
    return { error: "Unexpected reply from the chat helper", items: [] }
  }
}

// Unread first, then most recent activity.
function sortChannels(channels) {
  return channels.slice().sort(function(a, b) {
    if ((b.unread > 0) !== (a.unread > 0)) return b.unread > 0 ? 1 : -1
    return b.lastPostAt - a.lastPostAt
  })
}

function totalUnread(channels) {
  var n = 0
  for (var i = 0; i < channels.length; i++) n += channels[i].unread || 0
  return n
}

// Channels whose unread count grew since the previous poll.
function newlyUnread(previous, channels) {
  var before = {}
  for (var i = 0; i < previous.length; i++) before[previous[i].id] = previous[i].unread || 0
  return channels.filter(function(ch) {
    return before[ch.id] !== undefined && (ch.unread || 0) > before[ch.id]
  }).map(function(ch) {
    return { id: ch.id, name: ch.name, count: ch.unread - before[ch.id] }
  })
}

function pad(n) { return n < 10 ? "0" + n : String(n) }

function formatTime(ms) {
  if (!ms) return ""
  var d = new Date(ms)
  var now = new Date()
  var hm = pad(d.getHours()) + ":" + pad(d.getMinutes())
  if (d.toDateString() === now.toDateString()) return hm
  var days = Math.floor((now - d) / 86400000)
  if (days < 7) return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][d.getDay()] + " " + hm
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

function escapeHtml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

var URL_RE = /(https?:\/\/[^\s<>"']+[^\s<>"'.,;:!?)\]])/g

// Links longer than this are shown shortened; the full URL stays the target.
// Hundreds of characters with no break point (tracking-laden eBay links) send
// the text layout into a loop that eats memory until the shell dies.
var LINK_LABEL_MAX = 60

function linkLabel(url) {
  return url.length > LINK_LABEL_MAX ? url.slice(0, LINK_LABEL_MAX - 1) + "…" : url
}

// Plain message -> rich text with clickable links, keeping line breaks.
function richText(text, linkColor) {
  var parts = String(text || "").split(URL_RE)
  var html = ""
  for (var i = 0; i < parts.length; i++) {
    if (i % 2 === 1) html += '<a href="' + escapeHtml(parts[i]) + '" style="color:' + linkColor + '">' + escapeHtml(linkLabel(parts[i])) + "</a>"
    else html += escapeHtml(parts[i])
  }
  return html.replace(/\n/g, "<br>")
}

function formatSize(bytes) {
  if (!bytes) return ""
  var units = ["B", "KB", "MB", "GB"]
  var i = 0
  var n = bytes
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
  return (i === 0 ? n : n.toFixed(1)) + " " + units[i]
}

function fileIcon(file) {
  var ext = String(file.name || "").split(".").pop().toLowerCase()
  if (file.image) return "󰋩"
  if (file.snippet) return "󰈙"
  if (["zip", "rar", "7z", "gz", "tar"].indexOf(ext) !== -1) return "󰗄"
  if (["pdf"].indexOf(ext) !== -1) return "󰈦"
  if (["doc", "docx", "odt"].indexOf(ext) !== -1) return "󰈬"
  if (["xls", "xlsx", "ods", "csv"].indexOf(ext) !== -1) return "󰈛"
  return "󰈔"
}

function channelIcon(ch) {
  if (ch.type === "synobot" || ch.type === "chatbot") return "󰚩"
  if (ch.direct) return "󰀄"
  return "󰐙"
}

function channelDetail(ch) {
  var parts = []
  if (ch.unread > 0) parts.push(ch.unread + " new")
  if (ch.mentions > 0) parts.push(ch.mentions + (ch.mentions === 1 ? " mention" : " mentions"))
  if (ch.lastPostAt) parts.push(formatTime(ch.lastPostAt))
  return parts.join(" · ")
}

// A stable, readable color per user, tuned for dark or light themes.
function userColor(userId, dark) {
  var hues = [8, 32, 48, 95, 145, 172, 195, 215, 250, 280, 310, 335]
  var h = hues[Math.abs(Number(userId) || 0) % hues.length] / 360
  return dark ? Qt.hsla(h, 0.6, 0.68, 1) : Qt.hsla(h, 0.65, 0.38, 1)
}

function initials(name) {
  var words = String(name || "?").trim().split(/\s+/)
  var s = words[0].charAt(0) + (words.length > 1 ? words[words.length - 1].charAt(0) : "")
  return s.toUpperCase()
}
