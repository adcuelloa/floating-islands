import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./qmljs.mjs";

const W = load("logic/Workspaces.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

test("block and slot numbering follows Omarchy's blocks of ten", () => {
  assert.equal(W.blockOf(1), 0);
  assert.equal(W.blockOf(10), 0);
  assert.equal(W.blockOf(11), 1);
  assert.equal(W.slotOf(13), 3);
  assert.equal(W.slotOf(20), 10);
});

test("parses the monitor-workspaces state file", () => {
  const blocks = plain(W.parseBlocks("0\teDP-1\tPanel\n1\tHDMI-A-1\tTV\n\nbad line\nx\tDP-1\tz"));
  assert.deepEqual(blocks, { "eDP-1": 0, "HDMI-A-1": 1 });
  assert.equal(W.blockFor(blocks, "HDMI-A-1", 3), 1);
  assert.equal(W.blockFor({}, "DP-2", 23), 2);
  assert.equal(W.blockFor({}, "DP-2", -1), 0);
});

test("first five always show; higher ones while they exist; guests last", () => {
  const list = [
    { id: 1, monitorName: "eDP-1", windows: 2 },
    { id: 3, monitorName: "eDP-1", windows: 0 },
    { id: 7, monitorName: "eDP-1", windows: 1 },
    { id: 12, monitorName: "eDP-1", windows: 1 },
    { id: 14, monitorName: "HDMI-A-1", windows: 1 },
  ];
  const entries = plain(W.entries(0, list, "eDP-1", 7));
  assert.deepEqual(entries.map((e) => e.id), [1, 2, 3, 4, 5, 7, 12]);
  assert.deepEqual(entries.find((e) => e.id === 1), { id: 1, slot: 1, label: "1", active: false, occupied: true, guest: false, firstGuest: false });
  assert.equal(entries.find((e) => e.id === 3).occupied, false);
  assert.equal(entries.find((e) => e.id === 7).active, true);
  assert.deepEqual(entries.at(-1), { id: 12, slot: 2, label: "12", active: false, occupied: true, guest: true, firstGuest: true });
});

test("slot ten is labelled 0", () => {
  const entries = plain(W.entries(0, [{ id: 10, monitorName: "eDP-1", windows: 1 }], "eDP-1", 10));
  assert.equal(entries.at(-1).label, "0");
});

test("focus dispatch matches the stock widget and quotes the connector", () => {
  assert.equal(W.focusDispatch(3, 0, "eDP-1"), 'o.workspaces.focus(3, "eDP-1")');
  assert.equal(W.focusDispatch(14, 0, "eDP-1"), 'hl.dsp.focus({ workspace = "14" })');
  assert.equal(W.focusDispatch(2, 0, 'a"b\\c'), 'o.workspaces.focus(2, "a\\"b\\\\c")');
  assert.equal(W.focusDispatch(0, 0, "eDP-1"), "");
  assert.equal(W.focusDispatch("1; rm -rf", 0, "eDP-1"), "");
});

test("scrolling steps along the row and stops at the ends", () => {
  const ids = [1, 2, 3, 4, 5];
  assert.equal(W.scrollTarget(ids, 3, 1), 2);
  assert.equal(W.scrollTarget(ids, 3, -1), 4);
  assert.equal(W.scrollTarget(ids, 1, 1), -1);
  assert.equal(W.scrollTarget(ids, 5, -3), -1);
  assert.equal(W.scrollTarget(ids, 9, 1), -1);
});
