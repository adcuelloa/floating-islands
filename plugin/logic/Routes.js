.pragma library

// The shell's summon, hide and isOpen calls on the active bar
// (shell.bar.summonBarWidget etc.). This bar draws omarchy.clock itself, so
// that id means the native calendar: summon opens it on the focused output,
// hide closes it everywhere, and it is open while any output shows it, so the
// shell's toggle (isOpen ? hide : summon) also closes one opened elsewhere.
// Every other id goes to the hosted widgets.
var CALENDAR_ID = "omarchy.clock"

// surfaces: objects with openCalendar(), closeCalendar() and calendarOpened.
function summon(id, focused, hosting) {
  if (String(id || "") !== CALENDAR_ID) return hosting.summon(id)
  return !!focused && focused.openCalendar() === true
}

function hide(id, surfaces, hosting) {
  if (String(id || "") !== CALENDAR_ID) return hosting.hide(id)
  for (var i = 0; i < surfaces.length; i++) surfaces[i].closeCalendar()
  return surfaces.length > 0
}

function isOpen(id, surfaces, hosting) {
  if (String(id || "") !== CALENDAR_ID) return hosting.isOpen(id)
  for (var i = 0; i < surfaces.length; i++) if (surfaces[i].calendarOpened === true) return true
  return false
}
