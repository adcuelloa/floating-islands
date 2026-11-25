#!/usr/bin/env bash
# Checks the installed Omarchy shell and Quickshell against contract.tsv: every
# upstream symbol this bar depends on must still be there. Fails on the first
# report of any missing symbol, and names what would break.
#
# Rows marked F?/E? are conditional (an opt-in feature uses them): they fail
# like any other row unless --advisory, which reports them as WARN, for
# checking newer upstream revisions where an opt-in break is a finding, not a
# blocker. The supported baseline is always checked without --advisory.
#
# Usage: tests/contract/check-contract.sh [--quiet] [--advisory] [--porcelain]
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OMARCHY=${OMARCHY_PATH:-/usr/share/omarchy}
QS=${QUICKSHELL_QML_DIR:-/usr/lib/qt6/qml/Quickshell}
quiet=0
advisory=0
porcelain=0
for arg in "$@"; do
  case $arg in
    --quiet) quiet=1 ;;
    --advisory) advisory=1 ;;
    --porcelain) porcelain=1 ;;
    *) echo "usage: check-contract.sh [--quiet] [--advisory] [--porcelain]" >&2; exit 2 ;;
  esac
done

# Versions the contract was last verified against. A difference is reported,
# not failed: the symbol checks below decide compatibility.
PINNED_OMARCHY="4.5.0-3"
PINNED_QUICKSHELL="0.3.2.r7.g2b4501a-1"

pass=0
fail=0
warn=0

installed_version() {
  pacman -Q "$1" 2>/dev/null | awk '{print $2}'
}

note_version() {
  local name=$1 pinned=$2 actual
  actual=$(installed_version "$name")
  if [[ -z $actual ]]; then
    echo "note: $name not installed as a package (pinned $pinned)"
  elif [[ $actual != "$pinned" ]]; then
    echo "note: $name $actual differs from the verified $pinned; relying on the symbol checks"
  elif (( ! quiet )); then
    echo "version: $name $actual (verified)"
  fi
}

note_version omarchy "$PINNED_OMARCHY"
note_version quickshell "$PINNED_QUICKSHELL"

lineno=0
while IFS=$'\t' read -r area file mode pattern reason; do
  lineno=$((lineno + 1))
  [[ -z ${area// } || $area == \#* ]] && continue
  conditional=0
  [[ $mode == *\? ]] && conditional=1 && mode=${mode%\?}
  if [[ $mode != F && $mode != E ]]; then
    fail=$((fail + 1))
    if (( porcelain )); then
      printf 'row\t%d\tFAIL\t%d\t%s\t%s\n' "$lineno" "$conditional" "$area" "$reason"
    else
      echo "FAIL [$area] bad mode '$mode' — $reason"
    fi
    continue
  fi
  path=${file//\$OMARCHY/$OMARCHY}
  path=${path//\$QS/$QS}
  if [[ ! -f $path ]]; then
    found=1 detail="missing file $path"
  elif [[ $mode == F ]]; then
    grep -qF -- "$pattern" "$path"; found=$? detail="not found in ${path}: $pattern"
  else
    grep -qE -- "$pattern" "$path"; found=$? detail="not found in ${path}: $pattern"
  fi
  if (( found == 0 )); then
    pass=$((pass + 1))
    if (( porcelain )); then
      printf 'row\t%d\tok\t%d\t%s\t%s\n' "$lineno" "$conditional" "$area" "$reason"
    elif (( ! quiet )); then
      echo "ok   [$area] $reason"
    fi
  elif (( conditional && advisory )); then
    warn=$((warn + 1))
    if (( porcelain )); then
      printf 'row\t%d\tWARN\t%d\t%s\t%s\n' "$lineno" "$conditional" "$area" "$reason"
    else
      echo "WARN [$area] (conditional) $reason"
      echo "     $detail"
    fi
  else
    fail=$((fail + 1))
    if (( porcelain )); then
      printf 'row\t%d\tFAIL\t%d\t%s\t%s\n' "$lineno" "$conditional" "$area" "$reason"
    else
      echo "FAIL [$area] $reason"
      echo "     $detail"
    fi
  fi
done <"$here/contract.tsv"

if (( advisory )); then
  echo "contract: $pass passed, $fail failed, $warn conditional warnings"
else
  echo "contract: $pass passed, $fail failed"
fi
(( fail == 0 ))
