#!/usr/bin/env bash
# Every automated check, in the order a failure is cheapest to read. Nothing
# here touches the live desktop: temporary files go to /tmp and are removed.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo="$here/.."
status=0
step() {
  echo
  echo "== $1"
  shift
  "$@" || status=1
}

validate() {
  local stage
  stage=$(mktemp -d /tmp/islands-validate.XXXXXX)
  local id
  id=$(jq -r .id "$repo/plugin/manifest.json")
  cp -R "$repo/plugin" "$stage/$id"
  "${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-plugin-validate" "$stage/$id" && echo "omarchy plugin validate: ok"
  local rc=$?
  rm -rf "$stage"
  return $rc
}

qml_tests() {
  "$here/qml/run.sh" 2>&1 | grep -E '^(FAIL|Totals)|Loc:|Actual|Expected'
  return "${PIPESTATUS[0]}"
}

step "omarchy plugin validate" validate
step "imports" "$here/imports.sh"
step "qmllint" "$here/lint.sh"
step "compatibility contract" "$here/contract/check-contract.sh" --quiet
step "contract self-test" "$here/contract/self-test.sh"
step "unit tests (node)" node --test "$here"/unit/*.test.mjs
step "component tests (qmltestrunner, offscreen)" qml_tests
step "install / settings / rollback (sandbox, isolated)" "$here/scripts/isolated.sh" "$here/scripts/sandbox.test.sh"
step "privacy" "$here/privacy.sh"

echo
(( status == 0 )) && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $status
