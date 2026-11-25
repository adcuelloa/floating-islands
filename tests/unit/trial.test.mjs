import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./qmljs.mjs";

const Trial = load("logic/Trial.js");
const Settings = load("logic/Settings.js");

test("no trial recorded: never stale (persistent activation)", () => {
  assert.equal(Trial.isStale("", "abc"), false);
  assert.equal(Trial.isStale(undefined, ""), false);
});

test("a trial is stale in any other Hyprland instance, or with none", () => {
  assert.equal(Trial.isStale("abc_123", "abc_123"), false);
  assert.equal(Trial.isStale("abc_123", "def_456"), true);
  assert.equal(Trial.isStale("abc_123", ""), true);
});

test("malformed trial markers are ignored rather than trusted", () => {
  assert.equal(Trial.isStale("../../etc", "x"), false);
  assert.equal(Settings.read({ islands: { trialInstance: "a b" } }, "islands").trialInstance, "");
  assert.equal(Settings.read({ islands: { trialInstance: "a_b-1.2" } }, "islands").trialInstance, "a_b-1.2");
});

test("ending a trial deselects only this bar and drops the marker", () => {
  const bar = { id: "floating-islands", position: "top", islands: { density: "compact", trialInstance: "x" }, layout: { right: [] } };
  Trial.endTrial(bar, "floating-islands", "islands");
  assert.deepEqual(JSON.parse(JSON.stringify(bar)), { position: "top", islands: { density: "compact" }, layout: { right: [] } });
  const legacy = { id: "islands.bar", position: "top", islands: { density: "compact", trialInstance: "x" } };
  Trial.endTrial(legacy, "islands.bar", "islands");
  assert.deepEqual(JSON.parse(JSON.stringify(legacy)), { position: "top", islands: { density: "compact" } });
  const other = { id: "someone.else", islands: { trialInstance: "x" } };
  Trial.endTrial(other, "floating-islands", "islands");
  assert.equal(other.id, "someone.else");
});

// Trial 4: the self-deselect at a new login left `"islands": {}` behind, so
// shell.json no longer matched its pretrial copy (rollback.sh drops it).
test("ending a trial removes a settings object the marker alone created", () => {
  const bar = { id: "floating-islands", position: "top", islands: { trialInstance: "x" } };
  Trial.endTrial(bar, "floating-islands", "islands");
  assert.deepEqual(JSON.parse(JSON.stringify(bar)), { position: "top" });
});
