#!/usr/bin/env bash
# Focused negative and positive tests for .github/ci/counts.sh failure propagation.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
counts="$script_dir/counts.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

expect_pass() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then
    echo "ok - $name"
    pass=$((pass + 1))
  else
    echo "NOT ok - $name (expected exit 0)" >&2
    fail=$((fail + 1))
  fi
}

expect_fail() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then
    echo "NOT ok - $name (expected non-zero exit)" >&2
    fail=$((fail + 1))
  else
    echo "ok - $name"
    pass=$((pass + 1))
  fi
}

# Valid fixture logs
cat >"$tmp/node.log" <<'EOF'
# tests 106
# pass 106
EOF
cat >"$tmp/qml.log" <<'EOF'
Totals: 263 passed, 0 failed, 0 skipped
EOF
cat >"$tmp/contract.log" <<'EOF'
contract: 212 passed
EOF
cat >"$tmp/sandbox.log" <<'EOF'
sandbox: 92 passed
EOF

expect_pass "valid all stages pass" "$counts" "$tmp" node=106 qml=263 contract=212 sandbox=92
expect_fail "mismatched count fails" "$counts" "$tmp" node=105
expect_fail "mixed valid and mismatched propagates failure" "$counts" "$tmp" node=106 qml=262 contract=212
expect_fail "unknown stage name fails" "$counts" "$tmp" bogus=1

# Zero-count fixture
mkdir -p "$tmp/zero"
echo "# pass 0" >"$tmp/zero/node.log"
expect_fail "zero count fails even if expected=0" "$counts" "$tmp/zero" node=0

# Missing summary line fixture
mkdir -p "$tmp/empty"
echo "unrelated output" >"$tmp/empty/qml.log"
expect_fail "missing summary line fails" "$counts" "$tmp/empty" qml=263

# Missing log file fixture
expect_fail "missing log file fails" "$counts" "$tmp/empty" sandbox=92

echo "counts-self-test: $pass passed, $fail failed"
(( fail == 0 ))
