#!/usr/bin/env bash
# Reads each stage's counted result out of its log and fails if the summary is
# missing, counts nothing, or differs from the expected number, so a stage that
# silently ran fewer tests cannot pass.
#
# Counted: node (TAP "# pass"), QML ("Totals: N passed", which includes each
# TestCase's initTestCase/cleanupTestCase), contract rows and sandbox checks.
# The contract self-test's cases are not counted, matching the local 673
# (node 106 + qml 263 + contract 212 + sandbox 92 at tree f792aba).
#
# Usage: counts.sh <log-dir> <stage>=<expected>...   (stage: node qml contract sandbox)
set -uo pipefail
logs=${1:?usage: counts.sh <log-dir> <stage>=<expected>...}
shift

declare -A regex=(
  [node]='^# pass [0-9]+'
  [qml]='^Totals: [0-9]+ passed'
  [contract]='^contract: [0-9]+ passed'
  [sandbox]='^sandbox: [0-9]+ passed'
)

status=0
for arg in "$@"; do
  stage=${arg%%=*} expected=${arg#*=}
  [[ -n ${regex[$stage]:-} ]] || { echo "counts: unknown stage $stage"; status=1; continue; }
  n=$(grep -oE "${regex[$stage]}" "$logs/$stage.log" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
  if [[ -z $n || $n == 0 ]]; then
    echo "counts: $stage has no counted result in $logs/$stage.log"; status=1
  elif [[ $n != "$expected" ]]; then
    echo "counts: $stage counted $n, expected $expected"; status=1
  else
    echo "counts: $stage $n"
  fi
done
exit $status
