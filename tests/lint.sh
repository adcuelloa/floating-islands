#!/usr/bin/env bash
# qmllint over every QML file of the plugin, resolving Omarchy's `qs.*`
# modules the way Quickshell does (qs -> the shell directory). Fails on any
# finding not explained in tests/lint-allowlist.txt.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin="$here/../plugin"
OMARCHY=${OMARCHY_PATH:-/usr/share/omarchy}
QMLLINT=${QMLLINT:-$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)}

root=$(mktemp -d /tmp/islands-lint.XXXXXX)
trap 'rm -rf "$root"' EXIT
ln -s "$OMARCHY/shell" "$root/qs"

cd "$plugin" || exit 1
mapfile -t files < <(find . -name '*.qml' | sed 's|^\./||' | sort)
findings=$("$QMLLINT" -I "$root" "${files[@]}" 2>&1 | grep -E '^Warning: ' | sed -E 's/^Warning: //; s/^([^:]+):[0-9]+:[0-9]+:/\1:/')

patterns=$(grep -vE '^\s*(#|$)' "$here/lint-allowlist.txt")
unexpected=$(grep -vEf <(printf '%s\n' "$patterns") <<<"$findings" | grep -v '^$' || true)
allowed=$(grep -cEf <(printf '%s\n' "$patterns") <<<"$findings" || true)

if [[ -n $unexpected ]]; then
  echo "qmllint: unexpected findings:"
  printf '  %s\n' "$unexpected"
  exit 1
fi
echo "qmllint: ${#files[@]} files, no unexpected findings ($allowed allowlisted)"
