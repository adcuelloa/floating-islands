import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./qmljs.mjs";

const R = load("logic/Routes.js");

// Stands in for BarSurface: one output's native calendar.
function surface(name, ready = true) {
  return {
    name,
    calendarOpened: false,
    openCalendar() { if (ready) this.calendarOpened = true; return this.calendarOpened; },
    closeCalendar() { this.calendarOpened = false; },
  };
}

// Stands in for WidgetHosting: records what reached the hosted widgets.
function hosting() {
  const calls = [];
  return {
    calls,
    summon: (id) => { calls.push(["summon", id]); return id === "omarchy.audio"; },
    hide: (id) => { calls.push(["hide", id]); return id === "omarchy.audio"; },
    isOpen: (id) => { calls.push(["isOpen", id]); return false; },
  };
}

// The shell's toggle: isPluginOpen ? hide : summon (shell.qml).
function toggle(id, focused, surfaces, host) {
  return R.isOpen(id, surfaces, host) ? R.hide(id, surfaces, host) : R.summon(id, focused, host);
}

test("summon opens the calendar on the focused output only", () => {
  const a = surface("eDP-1"), b = surface("DP-1"), host = hosting();
  assert.equal(R.summon("omarchy.clock", b, host), true);
  assert.equal(b.calendarOpened, true);
  assert.equal(a.calendarOpened, false);
  assert.equal(R.isOpen("omarchy.clock", [a, b], host), true);
  assert.deepEqual(host.calls, [], "the calendar never reaches the hosted widgets");
});

test("hide closes the calendar on every output and reports the state", () => {
  const a = surface("eDP-1"), b = surface("DP-1"), host = hosting();
  a.calendarOpened = b.calendarOpened = true;
  assert.equal(R.hide("omarchy.clock", [a, b], host), true);
  assert.equal(a.calendarOpened || b.calendarOpened, false);
  assert.equal(R.isOpen("omarchy.clock", [a, b], host), false);
  assert.equal(R.hide("omarchy.clock", [], host), false, "no bar surface, nothing to hide");
});

test("the shell's toggle round-trips, also when another output has it open", () => {
  const a = surface("eDP-1"), b = surface("DP-1"), host = hosting();
  toggle("omarchy.clock", a, [a, b], host);
  assert.equal(a.calendarOpened, true);
  toggle("omarchy.clock", a, [a, b], host);
  assert.equal(a.calendarOpened, false);
  b.calendarOpened = true;
  toggle("omarchy.clock", a, [a, b], host);
  assert.equal(a.calendarOpened || b.calendarOpened, false, "toggle closes it rather than opening a second");
});

test("summon fails without a surface or before the calendar is built", () => {
  const host = hosting();
  assert.equal(R.summon("omarchy.clock", null, host), false);
  const early = surface("eDP-1", false);
  assert.equal(R.summon("omarchy.clock", early, host), false);
});

test("every other id goes to the hosted widgets unchanged", () => {
  const a = surface("eDP-1"), host = hosting();
  assert.equal(R.summon("omarchy.audio", a, host), true);
  assert.equal(R.hide("omarchy.audio", [a], host), true);
  assert.equal(R.isOpen("omarchy.audio", [a], host), false);
  assert.equal(R.summon("not.installed", a, host), false);
  assert.deepEqual(host.calls, [["summon", "omarchy.audio"], ["hide", "omarchy.audio"], ["isOpen", "omarchy.audio"], ["summon", "not.installed"]]);
  assert.equal(a.calendarOpened, false);
});
