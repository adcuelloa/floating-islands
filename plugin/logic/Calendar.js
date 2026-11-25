.pragma library

// Month grids, keyboard movement and locale choice for the calendar panel.
// Dates are handled as local calendar days ({ year, month, day }, month
// 0-based) and built at local noon, so a day with no midnight (a DST jump
// at 00:00) still names itself.

// The languages the design ships, with the locale tags it uses.
var LOCALES = {
  en: "en-GB",
  es: "es-ES",
  ja: "ja-JP"
}

// "auto" follows the Omarchy language (Commons.I18n.formatLocale).
function resolveLocale(setting, omarchyLocale) {
  if (Object.prototype.hasOwnProperty.call(LOCALES, setting)) return LOCALES[setting]
  var tag = String(omarchyLocale || "")
  return /^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})*$/.test(tag) ? tag : "en-GB"
}

function language(tag) {
  return String(tag || "").split(/[-_]/)[0].toLowerCase()
}

// Date patterns per language, matching the design's Intl output
// ("28 October" / "October 2026", "28 de octubre" / "octubre de 2026",
// "10月28日" / "2026年10月"). Other languages get the English shape with
// their own month and day names.
function patterns(tag) {
  var lang = language(tag)
  if (lang === "ja") return { longDate: "M月d日", monthTitle: "yyyy年M月", weekdayFormat: "short", shortDate: "M月d日" }
  if (lang === "es") return { longDate: "d 'de' MMMM", monthTitle: "MMMM 'de' yyyy", weekdayFormat: "narrow", shortDate: "d MMM" }
  return { longDate: "d MMMM", monthTitle: "MMMM yyyy", weekdayFormat: "narrow", shortDate: "d MMM" }
}

// QML's Locale.firstDayOfWeek already uses Date.getDay() numbering (Sunday 0
// ... Saturday 6), unlike C++ Qt::DayOfWeek (Monday 1 ... Sunday 7); 7 is
// still read as Sunday in case a caller passes the C++ value.
function weekStartFromLocale(firstDayOfWeek) {
  var n = Number(firstDayOfWeek)
  if (n === 7) return 0
  return n >= 0 && n <= 6 && Math.floor(n) === n ? n : 1
}

function weekdayOrder(weekStart) {
  var out = []
  for (var i = 0; i < 7; i++) out.push((weekStart + i) % 7)
  return out
}

function dateAt(year, month, day) {
  return new Date(year, month, day, 12, 0, 0, 0)
}

function dayOf(date) {
  return { year: date.getFullYear(), month: date.getMonth(), day: date.getDate() }
}

function keyOf(d) {
  return d.year * 10000 + (d.month + 1) * 100 + d.day
}

function daysInMonth(year, month) {
  return new Date(year, month + 1, 0, 12).getDate()
}

// Always six weeks, so the panel keeps its height from month to month.
function monthGrid(year, month, weekStart, today, selected) {
  var first = dateAt(year, month, 1)
  var offset = (first.getDay() - weekStart + 7) % 7
  var todayKey = today ? keyOf(today) : -1
  var selectedKey = selected ? keyOf(selected) : -1
  var cells = []
  for (var i = 0; i < 42; i++) {
    var d = dayOf(dateAt(year, month, 1 - offset + i))
    var key = keyOf(d)
    cells.push({
      year: d.year,
      month: d.month,
      day: d.day,
      key: key,
      outside: d.month !== month,
      today: key === todayKey,
      selected: key === selectedKey
    })
  }
  return cells
}

function addDays(d, n) {
  return dayOf(dateAt(d.year, d.month, d.day + n))
}

// The same day n months on, clamped to the target month's length.
function addMonths(d, n) {
  var first = dateAt(d.year, d.month + n, 1)
  var year = first.getFullYear()
  var month = first.getMonth()
  return { year: year, month: month, day: Math.min(d.day, daysInMonth(year, month)) }
}

// Keyboard: arrows move a day or a week, Page Up/Down a month, Home returns
// to today. Right-to-left layouts swap left and right before calling this.
function move(selected, today, command) {
  if (command === "left") return addDays(selected, -1)
  if (command === "right") return addDays(selected, 1)
  if (command === "up") return addDays(selected, -7)
  if (command === "down") return addDays(selected, 7)
  if (command === "previousMonth") return addMonths(selected, -1)
  if (command === "nextMonth") return addMonths(selected, 1)
  if (command === "today") return { year: today.year, month: today.month, day: today.day }
  return selected
}
