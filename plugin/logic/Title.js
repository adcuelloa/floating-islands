.pragma library

// Window titles come from applications and are untrusted: they are shown as
// plain text only, flattened to one line, and bounded.

var MAX_LENGTH = 512

function displayTitle(title, appId) {
  var text = String(title || "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  if (!text) text = String(appId || "").replace(/\s+/g, " ").trim()
  return text.length > MAX_LENGTH ? text.slice(0, MAX_LENGTH) : text
}

var KINDS = [
  { kind: "terminal", pattern: /(alacritty|kitty|foot|ghostty|wezterm|konsole|xterm|terminal|rio)/ },
  { kind: "code", pattern: /(^code$|vscode|codium|cursor|neovide|nvim|zed|jetbrains|idea|pycharm|webstorm|clion|sublime|helix|emacs)/ },
  { kind: "browser", pattern: /(chrom|firefox|brave|zen|librewolf|vivaldi|epiphany|qutebrowser|floorp|thorium|webapp)/ },
  { kind: "note", pattern: /(obsidian|notion|typora|logseq|libreoffice|soffice|writer|xournal|joplin|evince|papers|zathura|okular)/ }
]

// A coarse category for the title island's monochrome icon.
function appKind(appId) {
  var id = String(appId || "").toLowerCase()
  if (!id) return "window"
  for (var i = 0; i < KINDS.length; i++) {
    if (KINDS[i].pattern.test(id)) return KINDS[i].kind
  }
  return "window"
}

// The title island's app icon from a desktop entry (Quickshell's
// DesktopEntries.heuristicLookup, as Omarchy's dock matches windows): a theme
// icon name resolved by `themedPath` (Quickshell.iconPath(name, true), "" when
// the theme lacks it), an absolute path, or a file URL. "" means "draw the
// design's symbol instead". Entries come from installed .desktop files, so
// anything else is refused rather than handed to an Image.
function appIconSource(entry, themedPath) {
  var name = entry && entry.icon ? String(entry.icon) : ""
  if (!name || name.length > 512) return ""
  if (name.indexOf("file:///") === 0) return name
  if (name.charAt(0) === "/") return "file://" + name
  if (!/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(name)) return ""
  var found = themedPath ? String(themedPath(name) || "") : ""
  return found
}
