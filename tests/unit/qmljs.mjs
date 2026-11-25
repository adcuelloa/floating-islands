// Loads a QML JavaScript library (`.pragma library`) into node for testing.
// The pragma and `.import` lines are QML-only, so they are dropped; `Qt` is
// stubbed with the one function the libraries call.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const pluginDir = fileURLToPath(new URL("../../plugin/", import.meta.url));

export const Qt = {
  rgba: (r, g, b, a) => ({ r, g, b, a }),
};

export function load(relativePath) {
  const source = readFileSync(pluginDir + relativePath, "utf8")
    .split("\n")
    .filter((line) => !/^\s*\.(pragma|import)\b/.test(line))
    .join("\n");
  const context = vm.createContext({ Qt, Math, JSON, Object, String, Number, Array, isFinite, parseInt });
  vm.runInContext(source, context, { filename: relativePath });
  return context;
}
