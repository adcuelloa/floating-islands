import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./qmljs.mjs";

const CC = load("logic/ControlCenter.js");
const Layout = load("geometry/Layout.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

// Stands in for the shell's first-party proxy (PluginFirstPartyServiceApi):
// state properties and setters, recording what was asked.
function proxy(state = {}) {
  const calls = [];
  return Object.assign({
    calls,
    enabled: false, stayAwake: false, doNotDisturb: false,
    setNightlight(v) { calls.push(["setNightlight", v]); },
    setIdleEnabled(v) { calls.push(["setIdleEnabled", v]); },
    setDoNotDisturb(v) { calls.push(["setDoNotDisturb", v]); },
  }, state);
}

test("each tile reads its own service's state", () => {
  assert.deepEqual(plain(CC.TILES).map((t) => [t.key, t.service]), [
    ["nightlight", "omarchy.nightlight"], ["stayAwake", "omarchy.idle"], ["doNotDisturb", "omarchy.notifications"],
  ]);
  assert.equal(CC.isOn("nightlight", proxy({ enabled: true })), true);
  assert.equal(CC.isOn("stayAwake", proxy({ stayAwake: true })), true);
  assert.equal(CC.isOn("doNotDisturb", proxy({ doNotDisturb: true })), true);
  assert.equal(CC.isOn("nightlight", proxy({ stayAwake: true })), false, "another service's field does not count");
  assert.equal(CC.isOn("nightlight", null), false);
});

test("requests go through the service's own setter", () => {
  const p = proxy();
  assert.equal(CC.request("nightlight", p, true), true);
  assert.equal(CC.request("doNotDisturb", p, false), true);
  // The idle service is inverted: staying awake is idle disabled.
  assert.equal(CC.request("stayAwake", p, true), true);
  assert.equal(CC.request("stayAwake", p, false), true);
  assert.deepEqual(p.calls, [["setNightlight", true], ["setDoNotDisturb", false], ["setIdleEnabled", false], ["setIdleEnabled", true]]);
});

test("nothing is asked of a missing service or setter", () => {
  assert.equal(CC.request("nightlight", null, true), false);
  assert.equal(CC.request("nightlight", { enabled: false }, true), false, "a proxy without the setter");
  assert.equal(CC.request("unknown", proxy(), true), false);
});

test("a tile's status never claims more than the service reports", () => {
  assert.equal(CC.status(false, true, true, true), "unavailable");
  assert.equal(CC.status(true, false, true, false), "pending");
  assert.equal(CC.status(true, false, false, true), "failed");
  assert.equal(CC.status(true, true, false, false), "on");
  assert.equal(CC.status(true, false, false, false), "off");
});

test("the IPC toggle answers disabled, no surface, or the surface's output", () => {
  let toggles = 0;
  const surface = { toggleControlCenter() { toggles++; return "eDP-1"; } };
  assert.equal(CC.ipcToggle(false, surface), "disabled");
  assert.equal(toggles, 0, "a disabled Control Center is not opened");
  assert.equal(CC.ipcToggle(true, null), "no-surface");
  assert.equal(CC.ipcToggle(true, surface), "eDP-1");
  assert.equal(toggles, 1);
});

test("panel links use the registry's display name, else the id", () => {
  const registry = { widgets: { "omarchy.bluetooth": { metadata: { displayName: "Bluetooth" } }, "user.audio": { metadata: {} } } };
  assert.deepEqual(plain(CC.links(["omarchy.bluetooth", "user.audio"], registry)), [
    { id: "omarchy.bluetooth", name: "Bluetooth" }, { id: "user.audio", name: "user.audio" },
  ]);
  assert.deepEqual(plain(CC.links([], null)), []);
});

// The live display: 1536 logical px (1920 at scale 1.25), measured 2026-10-31.
// The entry adds a status slot and an item gap to the status island.
test("geometry at 1536 px: the entry fits beside the full-tier clock unless the tray shows too", () => {
  const m = Layout.metrics(1, "compact");
  const clock = 209;                 // full tier, seconds' width reserved
  const media = 224 + 132 + 2 * 4 + 2; // MediaIsland.demandFor("full")
  const entry = m.statusSlot + m.itemGap;
  const demands = (status) => ({
    full: { center: clock, leftFixed: 207 + m.groupGap, titleMin: m.titleMin, rightFixed: status + m.groupGap + media },
    compact: { center: 150, leftFixed: 207 + m.groupGap, titleMin: m.titleMin, rightFixed: status + m.groupGap + 48 + 132 + 10 },
    minimal: { center: 80, leftFixed: 207, titleMin: 0, rightFixed: status },
  });
  assert.equal(Layout.chooseTier(1536, demands(200), m, "full"), "full", "today, no tray icon");
  assert.equal(Layout.chooseTier(1536, demands(232), m, "full"), "full", "today, a tray icon");
  assert.equal(Layout.chooseTier(1536, demands(200 + entry), m, "full"), "full", "with the entry, no tray icon");
  // Known limit: entry plus a tray icon leaves the right side 2.5 px short, so
  // the clock drops its weekday. Only while bar.islands.controlCenter is on.
  assert.equal(Layout.chooseTier(1536, demands(232 + entry), m, "full"), "compact");
});

test("audio output: available only with a ready node that has audio", () => {
  assert.equal(CC.outputAvailable(null), false);
  assert.equal(CC.outputAvailable({ ready: true }), false, "no audio object");
  assert.equal(CC.outputAvailable({ ready: false, audio: {} }), false, "not yet bound");
  assert.equal(CC.outputAvailable({ ready: true, audio: {} }), true);
  assert.equal(CC.outputAvailable({ audio: {} }), true, "no ready flag reads as ready");
});

test("audio volume bounds and percent", () => {
  assert.equal(CC.clampVolume(-0.2), 0);
  assert.equal(CC.clampVolume(0.42), 0.42);
  assert.equal(CC.clampVolume(1.3), 1, "the slider stops at 100 %");
  assert.equal(CC.clampVolume(NaN), 0);
  assert.equal(CC.clampVolume("0.5"), 0.5);
  assert.equal(CC.percent(0.426), 43);
  assert.equal(CC.percent(1.2), 120, "a louder level set elsewhere is shown as it is");
  assert.equal(CC.percent(-1), 0);
  assert.equal(CC.VOLUME_STEP, 0.05);
});

test("audio output name: description, then nickname, then node name", () => {
  assert.equal(CC.outputName({ description: "Speakers", nickname: "spk", name: "alsa_output.x" }), "Speakers");
  assert.equal(CC.outputName({ description: "", nickname: "spk", name: "alsa_output.x" }), "spk");
  assert.equal(CC.outputName({ name: "alsa_output.x" }), "alsa_output.x");
  assert.equal(CC.outputName(null), "");
});

test("the full audio panel is the first hosted widget in the Audio category", () => {
  const registry = { widgets: {
    "omarchy.bluetooth": { metadata: { category: "Connectivity" } },
    "user.audio": { metadata: { category: "Audio" } },
    "omarchy.audio": { metadata: { category: "Audio" } },
  } };
  assert.equal(CC.audioPanelId(["omarchy.bluetooth", "user.audio", "omarchy.audio"], registry), "user.audio", "a user's clone, as hosted");
  assert.equal(CC.audioPanelId(["omarchy.bluetooth"], registry), "", "none hosted: no link");
  assert.equal(CC.audioPanelId(["user.audio"], null), "");
});

// ------------------------------------------------------------ connectivity

test("wifi: no NetworkManager or no Wi-Fi device is unavailable", () => {
  assert.equal(CC.wifi(false, [{ connected: true }], true, true).available, false);
  assert.equal(CC.wifi(true, [], true, true).available, false);
  assert.equal(CC.wifi(true, null, true, true).available, false);
  assert.equal(CC.radioStatus(CC.wifi(true, [], true, true), false, false), "unavailable");
});

test("wifi: enabled, disabled, hardware switch", () => {
  const dev = [{ connected: false, network: "" }];
  assert.equal(CC.radioStatus(CC.wifi(true, dev, true, true), false, false), "on");
  assert.equal(CC.radioStatus(CC.wifi(true, dev, false, true), false, false), "off");
  const blocked = CC.wifi(true, dev, true, false);
  assert.equal(blocked.blocked, true);
  assert.equal(blocked.on, false, "a hard block is never on");
  assert.equal(CC.radioStatus(blocked, true, true), "blocked", "the switch wins over pending and failed");
});

test("wifi: connected only from a Wi-Fi device, with its network", () => {
  const on = CC.wifi(true, [{ connected: false, network: "" }, { connected: true, network: "Home" }], true, true);
  assert.equal(on.connected, true);
  assert.equal(on.detail, "Home");
  assert.equal(CC.radioStatus(on, false, false), "connected");
  const nameless = CC.wifi(true, [{ connected: true, network: "" }], true, true);
  assert.equal(nameless.connected, true, "the device decides, not the network list");
  assert.equal(nameless.detail, "");
  const off = CC.wifi(true, [{ connected: true, network: "Home" }], false, true);
  assert.equal(off.connected, false, "a stale connected flag does not outlive the radio");
  // The adapter passes Wi-Fi devices only; an Ethernet link is not one of them.
  assert.equal(CC.wifi(true, [{ connected: false, network: "" }], true, true).connected, false);
});

test("connectedNetwork names the connected network", () => {
  assert.equal(CC.connectedNetwork([{ name: "A", connected: false }, { name: "B", connected: true }]), "B");
  assert.equal(CC.connectedNetwork([{ name: "A", connected: false }]), "");
  assert.equal(CC.connectedNetwork(null), "");
});

test("bluetooth: absent, off, on, several adapters", () => {
  assert.equal(CC.radioStatus(CC.bluetooth([]), false, false), "unavailable");
  assert.equal(CC.radioStatus(CC.bluetooth(null), false, false), "unavailable");
  assert.equal(CC.radioStatus(CC.bluetooth([{ enabled: false }]), false, false), "off");
  assert.equal(CC.radioStatus(CC.bluetooth([{ enabled: true }]), false, false), "on");
  const two = CC.bluetooth([{ enabled: false }, { enabled: true }]);
  assert.equal(two.on, true, "any powered adapter counts");
  assert.equal(two.count, 2);
  assert.equal(CC.radioStatus(two, true, false), "pending");
  assert.equal(CC.radioStatus(CC.bluetooth([{ enabled: false }]), false, true), "failed");
});

test("radio commands ask for a direction, never a toggle", () => {
  assert.deepEqual(plain(CC.radioCommand("wifi", true)), ["nmcli", "radio", "wifi", "on"]);
  assert.deepEqual(plain(CC.radioCommand("wifi", false)), ["nmcli", "radio", "wifi", "off"]);
  assert.deepEqual(plain(CC.radioCommand("bluetooth", true)), ["omarchy-bluetooth-power", "on"]);
  assert.deepEqual(plain(CC.radioCommand("bluetooth", false)), ["omarchy-bluetooth-power", "off"]);
  assert.deepEqual(plain(CC.radioCommand("other", true)), []);
});

test("panelId links to Omarchy's own panel only when hosted", () => {
  assert.equal(CC.panelId("wifi", ["omarchy.clock", "omarchy.network"]), "omarchy.network");
  assert.equal(CC.panelId("bluetooth", ["omarchy.network"]), "");
  assert.equal(CC.panelId("bluetooth", ["omarchy.bluetooth"]), "omarchy.bluetooth");
  assert.equal(CC.panelId("wifi", null), "");
});

// ------------------------------------------- radio off can remove the device

const RFKILL = (devices) => JSON.stringify({ rfkilldevices: devices });

test("rfkillState reads rfkill --json per type", () => {
  const text = RFKILL([
    { type: "bluetooth", soft: "blocked", hard: "unblocked" },
    { type: "bluetooth", soft: "unblocked", hard: "unblocked" },
    { type: "wlan", soft: "unblocked", hard: "blocked" },
  ]);
  assert.deepEqual(plain(CC.rfkillState(text, "bluetooth")), { present: true, soft: true, hard: false }, "any switch blocked counts");
  assert.deepEqual(plain(CC.rfkillState(text, "wlan")), { present: true, soft: false, hard: true });
  assert.deepEqual(plain(CC.rfkillState(RFKILL([]), "wlan")), { present: false, soft: false, hard: false });
  assert.equal(CC.rfkillState("", "wlan"), null, "no output is unknown, not absent");
  assert.equal(CC.rfkillState("not json", "wlan"), null);
  assert.equal(CC.rfkillState("{}", "wlan"), null);
  assert.deepEqual(plain(CC.RFKILL_READ), ["rfkill", "--json", "--output", "TYPE,SOFT,HARD"], "read-only, no op");
});

test("bluetooth: the six cases are told apart", () => {
  const none = { present: false, soft: false, hard: false };
  const soft = { present: true, soft: true, hard: false };
  const hard = { present: true, soft: false, hard: true };
  const clear = { present: true, soft: false, hard: false };
  // 1. Physically absent: no adapter and no rfkill switch.
  assert.equal(CC.radioStatus(CC.bluetooth([], none), false, false), "unavailable");
  // 2. Present and powered off.
  assert.equal(CC.radioStatus(CC.bluetooth([{ enabled: false }], clear), false, false), "off");
  // 3. Soft-blocked: the adapter may stay listed, or be gone with its module.
  assert.equal(CC.radioStatus(CC.bluetooth([{ enabled: false }], soft), false, false), "off");
  const gone = CC.bluetooth([], soft);
  assert.equal(gone.available, true, "still switchable on");
  assert.equal(CC.radioStatus(gone, false, false), "off");
  // 4. Hardware-blocked: listed or not, nothing here can switch it on.
  assert.equal(CC.radioStatus(CC.bluetooth([], hard), false, false), "blocked");
  assert.equal(CC.radioStatus(CC.bluetooth([{ enabled: false }], hard), false, false), "blocked");
  // 5. Briefly unlisted with its switch unblocked (re-enumeration, bluetoothd
  // restarting): nothing claimed.
  assert.equal(CC.radioStatus(CC.bluetooth([], clear), false, false), "unavailable");
  // 6. Listed again after the block is lifted.
  assert.equal(CC.radioStatus(CC.bluetooth([{ enabled: true }], clear), false, false), "on");
  // rfkill not read (yet, or it failed): an empty list stays unavailable.
  assert.equal(CC.radioStatus(CC.bluetooth([], null), false, false), "unavailable");
  // Several adapters: one powered is on, even with another switch blocked.
  assert.equal(CC.radioStatus(CC.bluetooth([{ enabled: false }, { enabled: true }], hard), false, false), "on");
});

test("wifi: a device removed by radio off stays switchable", () => {
  const soft = { present: true, soft: true, hard: false };
  const off = CC.wifi(true, [], false, true, soft);
  assert.equal(off.available, true);
  assert.equal(CC.radioStatus(off, false, false), "off");
  assert.equal(CC.radioStatus(CC.wifi(true, [], false, true, { present: true, soft: false, hard: true }), false, false), "blocked");
  assert.equal(CC.radioStatus(CC.wifi(true, [], true, false, { present: true, soft: false, hard: false }), false, false), "blocked",
    "NetworkManager's hardware flag, with a switch present");
  assert.equal(CC.radioStatus(CC.wifi(true, [], true, true, { present: true, soft: false, hard: false }), false, false), "unavailable");
  assert.equal(CC.radioStatus(CC.wifi(true, [], false, true, { present: false, soft: false, hard: false }), false, false), "unavailable",
    "no Wi-Fi hardware at all");
  assert.equal(CC.radioStatus(CC.wifi(false, [], false, true, soft), false, false), "unavailable", "no NetworkManager to ask");
  assert.equal(CC.radioStatus(CC.wifi(true, [{ connected: false }], true, true, { present: true, soft: false, hard: true }), false, false), "blocked");
});

// -------------------------------------------------------------- dashboard

test("card width: a quarter of the output, 340-420 px, scaled", () => {
  assert.equal(CC.cardWidth(1536, 1), 384);
  assert.equal(CC.cardWidth(1280, 1), 340, "320 is below the floor");
  assert.equal(CC.cardWidth(2560, 1), 420);
  assert.equal(CC.cardWidth(1536, 1.25), 425);
  assert.equal(CC.cardWidth(0, 1), 340, "before the output is known");
});

test("columns fit the width", () => {
  assert.equal(CC.columns(352, 96, 8, 3), 3);
  assert.equal(CC.columns(200, 96, 8, 3), 2);
  assert.equal(CC.columns(90, 96, 8, 3), 1, "never zero");
  assert.equal(CC.columns(1000, 96, 8, 3), 3, "never more than asked");
});

test("rows keep visual rows and drop unfocusable items", () => {
  const items = ["a", "b", "c", "d", "e"];
  assert.deepEqual(plain(CC.rows(items, 2, () => true)), [["a", "b"], ["c", "d"], ["e"]]);
  assert.deepEqual(plain(CC.rows(items, 2, (x) => x !== "b" && x !== "e")), [["a"], ["c", "d"]]);
  assert.deepEqual(plain(CC.rows(items, 3, (x) => x === "z")), []);
});

test("navigate: arrows inside a group, Up/Down across groups, Tab between groups", () => {
  // Connectivity [4], System [3], Sound [[2],[1]], More [1].
  const shape = [[4], [3], [2, 1], [1]];
  const at = (group, row, col) => ({ group, row, col });
  const go = (from, move, memory) => plain(CC.navigate(shape, from, move, memory));
  assert.deepEqual(go(at(0, 0, 1), "right"), at(0, 0, 2));
  assert.deepEqual(go(at(0, 0, 3), "right"), at(0, 0, 3), "Left/Right stop at the group's edge");
  assert.deepEqual(go(at(2, 0, 1), "right"), at(2, 1, 0), "across rows within a group");
  assert.deepEqual(go(at(0, 0, 3), "down"), at(1, 0, 2), "into the next group at the nearest column");
  assert.deepEqual(go(at(2, 0, 1), "down"), at(2, 1, 0));
  assert.deepEqual(go(at(2, 1, 0), "down"), at(3, 0, 0));
  assert.deepEqual(go(at(3, 0, 0), "down"), at(3, 0, 0), "nothing below the last group");
  assert.deepEqual(go(at(1, 0, 0), "up"), at(0, 0, 0));
  assert.deepEqual(go(at(0, 0, 2), "up"), at(0, 0, 2), "nothing above the first group");
  assert.deepEqual(go(at(3, 0, 0), "up"), at(2, 1, 0), "the last row of the group above");
  assert.deepEqual(go(at(0, 0, 2), "tab"), at(1, 0, 0));
  assert.deepEqual(go(at(3, 0, 0), "tab"), at(0, 0, 0), "Tab wraps inside the panel");
  assert.deepEqual(go(at(0, 0, 0), "backtab"), at(3, 0, 0));
  assert.deepEqual(go(at(0, 0, 0), "tab", { 1: at(1, 0, 2) }), at(1, 0, 2), "back where the group was left");
  assert.deepEqual(go(at(0, 0, 0), "tab", { 1: at(1, 4, 0) }), at(1, 0, 0), "a stale memory falls back");
});

test("navigate: empty groups are skipped, an unknown start goes to the first control", () => {
  const shape = [[], [2], [], [1]];
  assert.deepEqual(plain(CC.navigate(shape, null, "down")), { group: 1, row: 0, col: 0 });
  assert.deepEqual(plain(CC.navigate(shape, { group: 1, row: 0, col: 1 }, "down")), { group: 3, row: 0, col: 0 });
  assert.deepEqual(plain(CC.navigate(shape, { group: 3, row: 0, col: 0 }, "tab")), { group: 1, row: 0, col: 0 });
  assert.equal(CC.navigate([[], []], null, "down"), null);
});

// ---------------------------------------------------------- power profile

const busctlAll = (profiles, active, degraded = "") => JSON.stringify({ type: "a{sv}", data: [{
  ActiveProfile: { type: "s", data: active },
  PerformanceDegraded: { type: "s", data: degraded },
  Profiles: { type: "aa{sv}", data: profiles.map((p) => ({ Profile: { type: "s", data: p }, Driver: { type: "s", data: "x" } })) },
}] });

test("profile names follow Quickshell's enum", () => {
  assert.deepEqual([0, 1, 2].map((v) => CC.profileName(v)), ["power-saver", "balanced", "performance"]);
  assert.equal(CC.profileName(7), "");
  for (const v of ["length", "__proto__", -1, 1.5, null, undefined, "x"]) assert.equal(CC.profileName(v), "", String(v));
});

test("parseProfiles: what the daemon lists, in display order", () => {
  assert.deepEqual(plain(CC.parseProfiles(busctlAll(["performance", "power-saver", "balanced"], "performance"))),
    { available: true, profiles: ["power-saver", "balanced", "performance"], active: "performance", degraded: "" });
  assert.deepEqual(plain(CC.parseProfiles(busctlAll(["power-saver", "balanced"], "balanced"))).profiles,
    ["power-saver", "balanced"], "no performance on this machine");
  assert.deepEqual(plain(CC.parseProfiles(busctlAll(["balanced"], "balanced"))).profiles, ["balanced"]);
  assert.equal(CC.parseProfiles(busctlAll(["balanced", "turbo"], "turbo")).active, "", "an unknown active profile is not shown as one");
  assert.equal(CC.parseProfiles(busctlAll(["balanced", "performance"], "performance", "lap-detected")).degraded, "lap-detected");
});

test("parseProfiles: unavailable daemon", () => {
  for (const text of ["", "Call failed: Destination does not exist", "{}", '{"data":[]}', busctlAll([], "")]) {
    assert.equal(CC.parseProfiles(text).available, false, JSON.stringify(text));
  }
  assert.ok(CC.PROFILE_READ.includes("--auto-start=no"), "the read never starts the daemon");
  assert.equal(CC.PROFILE_READ[0], "busctl");
});

test("profileCommand: Omarchy's helper, fixed arguments, validated", () => {
  const all = ["power-saver", "balanced", "performance"];
  assert.deepEqual(plain(CC.profileCommand("ac", "performance", all)), ["omarchy-powerprofiles-set", "ac", "performance"]);
  assert.deepEqual(plain(CC.profileCommand("battery", "power-saver", all)), ["omarchy-powerprofiles-set", "battery", "power-saver"]);
  assert.deepEqual(plain(CC.profileCommand("battery", "performance", ["power-saver", "balanced"])), [], "not offered here");
  assert.deepEqual(plain(CC.profileCommand("autodetect", "balanced", all)), [], "only ac or battery");
  assert.deepEqual(plain(CC.profileCommand("ac", "balanced; rm -rf ~", all)), []);
  assert.deepEqual(plain(CC.profileCommand("ac", "balanced", null)), []);
});

test("profileOutcome: exit status and observed state are separate evidence", () => {
  const req = (exited, code) => ({ target: "balanced", source: "ac", exited, code });
  assert.equal(CC.profileOutcome(req(false), "performance", "ac", false, false), "pending");
  assert.equal(CC.profileOutcome(req(false), "balanced", "ac", false, false), "pending", "observed before exit: wait for the exit");
  assert.equal(CC.profileOutcome(req(true, 0), "balanced", "ac", false, false), "done");
  assert.equal(CC.profileOutcome(req(true, 139), "balanced", "ac", false, false), "unsaved", "active, persistence unknown");
  assert.equal(CC.profileOutcome(req(true, 0), "performance", "ac", false, false), "pending", "exit 0 alone proves nothing");
  assert.equal(CC.profileOutcome(req(true, 0), "performance", "ac", true, false), "failed", "no change after the grace");
  assert.equal(CC.profileOutcome(req(true, 1), "performance", "ac", false, false), "pending", "a late signal may still come");
  assert.equal(CC.profileOutcome(req(true, 1), "performance", "ac", true, false), "failed");
  assert.equal(CC.profileOutcome(req(false), "performance", "ac", false, true), "failed", "hung past the limit");
  assert.equal(CC.profileOutcome(req(false), "balanced", "battery", false, false), "superseded", "the source changed mid-request");
  assert.equal(CC.profileOutcome(req(true, 0), "balanced", "battery", false, false), "superseded", "even if it matched: the source decides");
  assert.equal(CC.profileOutcome(null, "balanced", "ac", false, false), "pending");
});

// ------------------------------------------------------------- brightness

test("backlightOutput: Omarchy's internal prefixes, plain names only", () => {
  for (const ok of ["eDP-1", "eDP-2", "LVDS-1", "DSI-1", "eDP-1-1"]) assert.equal(CC.backlightOutput(ok), true, ok);
  for (const bad of ["HDMI-A-1", "DP-1", "", "eDP", "eDP-", "eDP-1 off", "eDP-1;rm", "--monitor", "-eDP-1", "eDP-1/..", null, undefined, 1, "edp-1"])
    assert.equal(CC.backlightOutput(bad), false, String(bad));
});

test("backlightDevice: a plain sysfs name from omarchy-hw-display", () => {
  assert.equal(CC.backlightDevice("intel_backlight\n"), "intel_backlight");
  assert.equal(CC.backlightDevice("amdgpu_bl1"), "amdgpu_bl1");
  assert.equal(CC.backlightDevice("acpi_video0"), "acpi_video0");
  for (const bad of ["", "\n", "..", ".", "../../etc", "a/b", "intel backlight", null, "x".repeat(65)])
    assert.equal(CC.backlightDevice(bad), "", String(bad));
});

test("backlightValue: non-negative integers only", () => {
  assert.equal(CC.backlightValue("57600\n"), 57600);
  assert.equal(CC.backlightValue("0"), 0);
  for (const bad of ["", "-1", "12.5", "1e3", "abc", null, "99999999999"]) assert.equal(CC.backlightValue(bad), -1, String(bad));
});

test("brightnessPercent: Omarchy's rounding, unusable values are -1", () => {
  assert.equal(CC.brightnessPercent(57600, 96000), 60);
  assert.equal(CC.brightnessPercent(52800, 96000), 55);
  assert.equal(CC.brightnessPercent(0, 96000), 0);
  assert.equal(CC.brightnessPercent(96000, 96000), 100);
  assert.equal(CC.brightnessPercent(479, 96000), 0, "rounds down below half a percent");
  assert.equal(CC.brightnessPercent(480, 96000), 1, "rounds half up");
  assert.equal(CC.brightnessPercent(7, 15), 47, "coarse hardware: 15 steps");
  assert.equal(CC.brightnessPercent(200, 100), 100, "clamped");
  assert.equal(CC.brightnessPercent(-1, 96000), -1);
  assert.equal(CC.brightnessPercent(10, 0), -1);
  assert.equal(CC.brightnessPercent(10, -5), -1);
  assert.equal(CC.brightnessPercent(NaN, 100), -1);
});

test("clampBrightness: finite numbers to 1..100, never 0", () => {
  assert.equal(CC.clampBrightness(60), 60);
  assert.equal(CC.clampBrightness(0), 1, "never blank the panel");
  assert.equal(CC.clampBrightness(-20), 1);
  assert.equal(CC.clampBrightness(150), 100);
  assert.equal(CC.clampBrightness(54.6), 55);
  assert.equal(CC.clampBrightness("70"), 70);
  for (const bad of [NaN, Infinity, -Infinity, "", "x", null, undefined, true, false, {}])
    assert.equal(CC.clampBrightness(bad), -1, String(bad));
});

test("brightnessCommand: fixed arguments, validated output and percent", () => {
  assert.deepEqual(plain(CC.brightnessCommand("eDP-1", 60)), ["omarchy-brightness-display", "--no-osd", "--monitor", "eDP-1", "60%"]);
  assert.deepEqual(plain(CC.brightnessCommand("eDP-1", 1)), ["omarchy-brightness-display", "--no-osd", "--monitor", "eDP-1", "1%"]);
  assert.deepEqual(plain(CC.brightnessCommand("eDP-1", 100)), ["omarchy-brightness-display", "--no-osd", "--monitor", "eDP-1", "100%"]);
  for (const p of [0, 101, -5, 50.5, NaN, "60", null, "off", "on"])
    assert.deepEqual(plain(CC.brightnessCommand("eDP-1", p)), [], String(p));
  for (const o of ["HDMI-A-1", "", "eDP-1 off", "off", "on", null])
    assert.deepEqual(plain(CC.brightnessCommand(o, 60)), [], String(o));
  const all = [];
  for (let p = 1; p <= 100; p++) all.push(...CC.brightnessCommand("eDP-1", p));
  assert.ok(!all.includes("off") && !all.includes("on") && !all.includes("0%"), "never off, on or 0");
});

test("brightnessOutcome: only the observed level proves a change", () => {
  const req = (exited, code = 0, target = 60) => ({ target, exited, code });
  assert.equal(CC.brightnessOutcome(null, 60, true), "pending");
  assert.equal(CC.brightnessOutcome(req(false), 60, false), "pending", "observed before exit: wait for the exit");
  assert.equal(CC.brightnessOutcome(req(true), 60, false), "done");
  assert.equal(CC.brightnessOutcome(req(true), 59, false), "done", "within the rounding tolerance");
  assert.equal(CC.brightnessOutcome(req(true), 61, false), "done");
  assert.equal(CC.brightnessOutcome(req(true), 58, false), "pending", "not yet: wait the grace");
  assert.equal(CC.brightnessOutcome(req(true), 58, true), "unconfirmed", "exit 0 is not proof");
  assert.equal(CC.brightnessOutcome(req(true, 1), 58, true), "failed");
  assert.equal(CC.brightnessOutcome(req(true, -1), 58, true), "failed", "could not start or was stopped");
  assert.equal(CC.brightnessOutcome(req(true, 1), 60, false), "done", "observed despite a failed exit");
  assert.equal(CC.brightnessOutcome(req(true), -1, true), "unconfirmed", "unreadable after the write");
});
