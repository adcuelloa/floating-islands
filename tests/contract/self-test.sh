#!/usr/bin/env bash
# Proves the contract check is neither blind nor brittle: against a copy of
# the installed Omarchy tree it must fail when a symbol this bar uses
# disappears, and pass when upstream changes something it does not use.
# A removal case names the row it expects: that row, and only that row, must
# fail, so one symbol cannot hide behind another on a shared line.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OMARCHY=${OMARCHY_PATH:-/usr/share/omarchy}
work=$(mktemp -d /tmp/islands-contract.XXXXXX)
trap 'rm -rf "$work"' EXIT

QS=${QUICKSHELL_QML_DIR:-/usr/lib/qt6/qml/Quickshell}

fresh_copy() {
  rm -rf "$work/omarchy" "$work/qs"
  mkdir -p "$work/omarchy/default"
  cp -R "$OMARCHY/shell" "$OMARCHY/bin" "$work/omarchy/"
  cp -R "$OMARCHY/default/hypr" "$work/omarchy/default/"
  cp -R "$QS" "$work/qs"
}

# check_copy [flags...]
check_copy() {
  OMARCHY_PATH="$work/omarchy" QUICKSHELL_QML_DIR="$work/qs" "$here/check-contract.sh" --quiet "$@" >"$work/out" 2>&1
}

failed=0
report() { echo "FAIL $1"; sed 's/^/     /' "$work/out" | head -6; failed=$((failed + 1)); }

# expect pass <name>
# expect fail <name> [<text of the one FAIL line expected>]
expect() {
  local outcome=$1 name=$2 row=${3:-}
  if [[ $outcome == pass ]]; then
    check_copy && echo "ok   $name" || report "$name"
  elif check_copy || ! grep -q '^FAIL' "$work/out"; then
    report "$name"
  elif [[ -n $row ]] && { [[ $(grep -c '^FAIL' "$work/out") != 1 ]] || ! grep '^FAIL' "$work/out" | grep -qF -- "$row"; }; then
    report "$name (expected exactly: $row)"
  else
    echo "ok   $name ($(grep -c '^FAIL' "$work/out") reported)"
  fi
}

# drop <file under the copy> <fixed text>: deletes every line containing it
drop() { grep -vF -- "$2" "$work/$1" >"$work/drop.tmp"; cp "$work/drop.tmp" "$work/$1"; }

fresh_copy
expect pass "an unchanged copy passes"

echo "// an unrelated upstream edit" >>"$work/omarchy/shell/shell.qml"
sed -i 's/Status bar with widgets/A different description/' "$work/omarchy/shell/plugins/bar/manifest.json"
echo "unrelated" >>"$work/omarchy/shell/README.md"
expect pass "unrelated upstream changes still pass"

fresh_copy
sed -i 's/bar.barSizeFor(screenName)/bar.size(screenName)/' "$work/omarchy/shell/plugins/notifications/Delivery.js"
expect fail "toasts no longer asking barSizeFor is caught"

fresh_copy
sed -i 's/function duration(ms) {/function animationTime(ms) {/' "$work/omarchy/shell/Commons/Style.qml"
expect fail "a renamed Style.duration is caught"

fresh_copy
sed -i 's/commit "$NORMALIZE | del(.bar.id)"/commit "$NORMALIZE | .bar.id = \\"omarchy.bar\\""/' "$work/omarchy/bin/omarchy-bar"
expect fail "a changed 'omarchy bar reset' is caught"

fresh_copy
sed -i 's/if ("barConfig" in target) target.barConfig = shell.barConfigFor(manifest)//' "$work/omarchy/shell/shell.qml"
expect fail "a bar no longer receiving barConfig is caught"

fresh_copy
sed -i 's/^PluginBarApi 1.0 PluginBarApi.qml$//' "$work/omarchy/shell/Ui/qmldir"
expect fail "PluginBarApi leaving qs.Ui is caught"

# --- one symbol per row: each removal fails its own row only
fresh_copy
drop omarchy/shell/Ui/PluginBarApi.qml "property var _setCenterHoverRevealSuppressed: null"
expect fail "facade callback _setCenterHoverRevealSuppressed removed alone" "facade callback _setCenterHoverRevealSuppressed"

fresh_copy
drop omarchy/shell/Ui/PluginBarApi.qml "property var _showTooltip: null"
expect fail "facade callback _showTooltip removed alone" "facade callback _showTooltip"

fresh_copy
sed -i 's/action === "playPause"/action === "toggle"/' "$work/omarchy/shell/plugins/services/media/Service.qml"
expect fail "media action playPause renamed alone" "media action playPause"

fresh_copy
drop omarchy/shell/Ui/KeyboardPanel.qml "property Item focusTarget"
expect fail "KeyboardPanel.focusTarget removed alone" "KeyboardPanel.focusTarget"

fresh_copy
sed -i 's/function fittedContentHeight(/function fitHeight(/' "$work/omarchy/shell/Ui/KeyboardPanel.qml"
expect fail "KeyboardPanel.fittedContentHeight renamed alone" "KeyboardPanel.fittedContentHeight"

fresh_copy
sed -i -E 's/^([[:blank:]]{0,2})property color muted:/\1property color subdued:/' "$work/omarchy/shell/Commons/Color.qml"
expect fail "root Color.muted renamed (nested groups keep theirs)" "Color.muted palette role"

fresh_copy
sed -i 's/property color border: root.pick("tooltip.border"/property color outline: root.pick("tooltip.border"/; s/property color border: root.composed("tooltip.border"/property color outline: root.composed("tooltip.border"/' "$work/omarchy/shell/Commons/Color.qml"
expect fail "Color.tooltip.border renamed alone" "Color.tooltip.border"

fresh_copy
drop omarchy/shell/Commons/Color.qml 'property color background: root.composed("popups.background"'
expect fail "Color.popups.background removed alone" "Color.popups.background"

fresh_copy
sed -i 's/name: "keyboardFocus"/name: "focusPolicy"/' "$work/qs/Wayland/_WlrLayerShell/quickshell-wayland-layershell.qmltypes"
expect fail "Quickshell WlrLayershell.keyboardFocus renamed alone" "WlrLayershell.keyboardFocus"

# --- first-party tagging: the semantic rule, not the spelling
fresh_copy
sed -i 's/manifest.__isFirstParty = (currentKind === "firstparty")/manifest.__isFirstParty = (kind === "firstparty")/' "$work/omarchy/shell/services/PluginRegistry.qml"
expect pass "first-party flag from the scan under a renamed local still passes"

fresh_copy
sed -i 's/manifest.__isFirstParty = (currentKind === "firstparty")/manifest.__isFirstParty = (manifest.firstParty === true)/' "$work/omarchy/shell/services/PluginRegistry.qml"
expect fail "first-party flag taken from the plugin's own manifest is caught" "firstParty comes from the scan"

# --- conditional rows: strict by default, WARN only with --advisory
fresh_copy
drop omarchy/shell/services/PluginFirstPartyServiceApi.qml "property bool stayAwake: false"
expect fail "an opt-in Control Center symbol fails the default (strict) check" "Stay awake state"
if check_copy --advisory && grep -q '^WARN .*(conditional) Stay awake state' "$work/out" && grep -q ', 1 conditional warnings$' "$work/out"; then
  echo "ok   --advisory reports it as a conditional WARN and exits 0"
else report "--advisory reports it as a conditional WARN and exits 0"; fi

fresh_copy
drop omarchy/shell/Ui/PluginBarApi.qml "property var _setCenterHoverRevealSuppressed: null"
if ! check_copy --advisory && grep -q '^FAIL .*_setCenterHoverRevealSuppressed' "$work/out"; then
  echo "ok   --advisory still fails a required row"
else report "--advisory still fails a required row"; fi

(( failed == 0 )) && echo "contract self-test: passed" || { echo "contract self-test: $failed failed"; exit 1; }
