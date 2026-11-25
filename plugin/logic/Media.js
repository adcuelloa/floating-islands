.pragma library

// What the media island shows, derived from Omarchy's media service. The
// service owns player selection (MPRIS, playback streams, the user's last
// choice); this only reads the player it chose. Metadata comes from other
// applications and is untrusted: shown as plain text, flattened and bounded.

var MAX_TEXT = 200

function clean(value) {
  var text = String(value || "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  return text.length > MAX_TEXT ? text.slice(0, MAX_TEXT) : text
}

// "unavailable": no media service (disabled, or not offered to this bar).
// "empty": the service has no player with something to show.
// "playing" / "paused": a player with a track.
function state(service, player) {
  if (!service) return "unavailable"
  if (!player) return "empty"
  var title = clean(player.trackTitle)
  var artist = clean(player.trackArtist)
  if (!title && !artist) return "empty"
  return player.isPlaying ? "playing" : "paused"
}

function describe(player) {
  var title = player ? clean(player.trackTitle) : ""
  var artist = player ? clean(player.trackArtist) : ""
  return {
    title: title || artist,
    artist: title ? artist : "",
    canPrevious: !!player && player.canGoPrevious === true,
    canNext: !!player && player.canGoNext === true,
    canPlayPause: !!player && (player.canTogglePlaying === true || player.canPlay === true || player.canPause === true)
  }
}

// Progress 0..1, or -1 when the player does not report a usable position.
function progress(player) {
  if (!player || player.positionSupported === false || player.lengthSupported === false) return -1
  var length = Number(player.length)
  var position = Number(player.position)
  if (!(length > 0) || !(position >= 0)) return -1
  return Math.max(0, Math.min(1, position / length))
}
