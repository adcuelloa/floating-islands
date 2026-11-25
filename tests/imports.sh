#!/usr/bin/env bash
# Every import in the plugin must resolve against what is installed, and come
# from the supported set below. qmllint does not flag an unknown module that
# provides no used types, so this check is the gate for a broken import.
#
# Usage: tests/imports.sh [plugin-dir]
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin=$(cd "${1:-$here/../plugin}" && pwd)
OMARCHY=${OMARCHY_PATH:-/usr/share/omarchy}
QT_QML=${QT_QML_DIR:-/usr/lib/qt6/qml}

# The supported import surface. Adding a module here is a deliberate change:
# it widens what an Omarchy or Qt update can break.
SUPPORTED=(
  QtQuick
  QtQuick.Shapes
  QtQuick.Effects
  QtTest
  Quickshell
  Quickshell.Wayland
  Quickshell.Hyprland
  Quickshell.Io
  Quickshell.Services.Pipewire
  Quickshell.Networking
  Quickshell.Bluetooth
  Quickshell.Services.UPower
  qs.Commons
  qs.Ui
)

failures=0
count=0
report() { echo "FAIL $*"; failures=$((failures + 1)); }

module_dir() {
  local uri=$1
  if [[ $uri == qs.* ]]; then
    printf '%s/shell/%s\n' "$OMARCHY" "${uri#qs.}" | tr . /
  else
    printf '%s/%s\n' "$QT_QML" "$uri" | tr . /
  fi
}

while IFS= read -r file; do
  dir=$(dirname "$file")
  while IFS= read -r line; do
    count=$((count + 1))
    target=$(sed -E 's/^\s*\.?import\s+//; s/\s+as\s+\S+\s*$//; s/\s+[0-9]+(\.[0-9]+)?\s*$//' <<<"$line")
    if [[ $target == \"*\" ]]; then
      path=${target//\"/}
      [[ -e $dir/$path ]] || report "${file#$plugin/}: $path does not exist"
      continue
    fi
    supported=0
    for module in "${SUPPORTED[@]}"; do [[ $target == "$module" ]] && supported=1; done
    (( supported )) || { report "${file#$plugin/}: $target is not a supported import"; continue; }
    qmldir="$(module_dir "$target")/qmldir"
    if [[ ! -f $qmldir ]]; then
      report "${file#$plugin/}: $target is not installed ($qmldir)"
    elif ! grep -qE "^module $target\$" "$qmldir"; then
      report "${file#$plugin/}: $qmldir does not declare module $target"
    fi
  done < <(grep -E '^\s*\.?import\s' "$file")
done < <(find "$plugin" -type f \( -name '*.qml' -o -name '*.js' \) | sort)

if (( failures )); then
  echo "imports: $failures unresolved or unsupported"
  exit 1
fi
echo "imports: $count imports resolve"
