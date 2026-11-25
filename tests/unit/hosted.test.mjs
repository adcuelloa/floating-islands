import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./qmljs.mjs";

const fresh = () => load("logic/Hosted.js");

// Applies the operations as the island applies them to its ListModel.
function apply(current, ops) {
  const work = current.slice();
  for (const op of ops) {
    if (op.op === "remove") work.splice(op.index, 1);
    else if (op.op === "move") work.splice(op.to, 0, work.splice(op.from, 1)[0]);
    else work.splice(op.index, 0, op.id);
  }
  return work;
}

test("unchanged ids need no operation (a rewritten shell.json keeps every widget)", () => {
  const H = fresh();
  assert.deepEqual(Array.from(H.reconcile(["a", "b", "c"], ["a", "b", "c"])), []);
});

test("reconcile reaches the new order for removals, inserts and moves", () => {
  const H = fresh();
  const cases = [
    [["a", "b", "c"], ["c", "a", "b"]],
    [["a", "b", "c"], ["b"]],
    [[], ["a", "b"]],
    [["a", "b"], []],
    [["a", "b", "c", "d"], ["d", "x", "b", "a"]],
    [["a", "b", "c"], ["c", "b", "a", "e"]],
  ];
  for (const [from, to] of cases) {
    assert.deepEqual(apply(from, H.reconcile(from, to)), to, `${from} -> ${to}`);
  }
});

test("kept widgets are moved, never removed and re-inserted", () => {
  const H = fresh();
  const ops = Array.from(H.reconcile(["a", "b", "c"], ["c", "b", "a"]));
  assert.ok(ops.every((op) => op.op === "move"));
});

test("uniqueIds keeps the first of duplicates and skips malformed entries", () => {
  const H = fresh();
  assert.deepEqual(Array.from(H.uniqueIds([{ id: "a" }, { id: "b" }, { id: "a" }, null, { id: 3 }, {}])), ["a", "b"]);
  assert.deepEqual(Array.from(H.uniqueIds(undefined)), []);
});

test("settingsById takes the first entry's settings", () => {
  const H = fresh();
  const map = H.settingsById([{ id: "a", settings: { step: 5 } }, { id: "a", settings: { step: 9 } }, { id: "b" }]);
  assert.equal(map.a.step, 5);
  assert.deepEqual({ ...map.b }, {});
});

test("componentFor remembers live components and covers a null snapshot entry", () => {
  const H = fresh();
  const live = { name: "live" };
  assert.equal(H.componentFor("w", { component: live }, true), live);
  assert.equal(H.componentFor("w", { component: null }, true), live, "falls back to the last live one");
  const next = { name: "reloaded" };
  assert.equal(H.componentFor("w", { component: next }, true), next, "the registry wins when live");
  assert.equal(H.componentFor("w", { component: null }, true), next);
});

test("componentFor forgets an id the registry dropped, but not while there is no registry", () => {
  const H = fresh();
  const live = { name: "live" };
  H.componentFor("w", { component: live }, true);
  assert.equal(H.componentFor("w", null, false), null);
  assert.equal(H.componentFor("w", { component: null }, true), live, "kept while the registry was unknown");
  assert.equal(H.componentFor("w", null, true), null);
  assert.equal(H.componentFor("w", { component: null }, true), null, "forgotten once dropped");
});

test("componentFor never invents a component for an id it never saw live", () => {
  const H = fresh();
  assert.equal(H.componentFor("never", { component: null }, true), null);
});
