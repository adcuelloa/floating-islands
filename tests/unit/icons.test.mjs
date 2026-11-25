import test from "node:test";
import assert from "node:assert/strict";
import { load } from "./qmljs.mjs";

const Icons = load("theme/Icons.js");

const ALL_KEYS = [
  "grid",
  "terminal", "browser", "code", "note", "empty", "generic",
  "previous", "next", "play", "pause",
  "controlCenter", "nightlight", "stayAwake", "doNotDisturb",
  "speaker", "speakerMuted", "brightness", "wifi", "bluetooth", "chevron",
];

test("every icon exports normalized PathSvg data with absolute subpath moves", () => {
  for (const key of ALL_KEYS) {
    const icon = Icons[key];
    assert.ok(icon && typeof icon === "object", `${key} should be an object`);
    const stroke = icon.stroke || "";
    const fill = icon.fill || "";
    assert.ok(stroke.length > 0 || fill.length > 0, `${key} needs stroke or fill path`);
    for (const [field, path] of [["stroke", stroke], ["fill", fill]]) {
      if (!path) continue;
      assert.match(path, /^M/, `${key}.${field} must start with absolute M`);
      assert.equal(path.includes("m"), false, `${key}.${field} must not contain relative m (breaks concatenated subpaths)`);
    }
  }
});

test("forKind resolves known window kinds and falls back to generic", () => {
  assert.equal(Icons.forKind("terminal"), Icons.terminal);
  assert.equal(Icons.forKind("browser"), Icons.browser);
  assert.equal(Icons.forKind("code"), Icons.code);
  assert.equal(Icons.forKind("note"), Icons.note);
  assert.equal(Icons.forKind("empty"), Icons.empty);
  assert.equal(Icons.forKind("unknown-app"), Icons.generic);
  assert.equal(Icons.forKind(""), Icons.generic);
});

test("media play and pause expose filled paths for primary transport emphasis", () => {
  assert.ok(Icons.play.fill && Icons.play.stroke);
  assert.ok(Icons.pause.fill);
  assert.equal(Icons.pause.stroke, "");
});

test("provenance records pinned Lucide release and commit SHA", () => {
  assert.equal(Icons.provenance.family, "Lucide");
  assert.equal(Icons.provenance.version, "1.79.0");
  assert.match(Icons.provenance.commit, /^[0-9a-f]{40}$/);
});
