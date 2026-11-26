#!/usr/bin/env bash
# Strict TypeScript checkJs validation for the native .mjs pilot and its Node
# test consumer, plus isolated negative checks proving invalid contracts and
# disallowed Qt-runtime globals/APIs are rejected.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)
TSC=${TSC:-"$repo/node_modules/.bin/tsc"}

if [[ ! -x $TSC ]]; then
  echo "typecheck: $TSC not found (run 'pnpm install --frozen-lockfile --ignore-scripts' for development type checking)" >&2
  exit 1
fi

failures=0
pass() { echo "ok   $1"; }
fail() { echo "FAIL $1" >&2; failures=$((failures + 1)); }

if "$TSC" -p "$repo/tsconfig.qml.json"; then
  pass "tsconfig.qml.json (Qt-executed .mjs modules)"
else
  fail "tsconfig.qml.json"
fi

if "$TSC" -p "$repo/tsconfig.node.json"; then
  pass "tsconfig.node.json (Node test consumer)"
else
  fail "tsconfig.node.json"
fi

# Isolated negative checks in /tmp: each fixture must fail type checking with
# the expected TypeScript diagnostic code.
tmp=$(mktemp -d /tmp/islands-typecheck.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

expect_error() {
  local name=$1 base_config=$2 expected_code=$3 code=$4
  local case_dir="$tmp/$name"
  mkdir -p "$case_dir"
  printf '%s\n' "$code" >"$case_dir/case.mjs"
  local extra_opts=""
  if [[ $base_config == "tsconfig.node.json" ]]; then
    extra_opts="\"compilerOptions\": { \"typeRoots\": [\"$repo/node_modules/@types\"] },"
  fi
  cat >"$case_dir/tsconfig.json" <<EOF
{
  "extends": "$repo/$base_config",
  $extra_opts
  "include": ["case.mjs"]
}
EOF
  local out rc
  out=$("$TSC" -p "$case_dir/tsconfig.json" 2>&1)
  rc=$?
  if (( rc == 0 )); then
    fail "negative[$name]: unexpectedly passed type checking"
    return
  fi
  if ! grep -q "$expected_code" <<<"$out"; then
    fail "negative[$name]: failed, but without expected $expected_code"
    printf '%s\n' "$out" | sed 's/^/  /' >&2
    return
  fi
  pass "negative[$name] rejected ($expected_code)"
}

expect_error "invalid-tier" "tsconfig.qml.json" "TS2345" \
  "import { partsFor } from '$repo/plugin/logic/ClockFormat.mjs';
export const bad = partsFor('wide');"

expect_error "invalid-edge" "tsconfig.qml.json" "TS2345" \
  "import { islandY, metrics } from '$repo/plugin/geometry/Layout.mjs';
export const bad = islandY('left', 864, metrics(1, 'compact'));"

expect_error "incomplete-demand" "tsconfig.qml.json" "TS2741" \
  "import { fit, metrics } from '$repo/plugin/geometry/Layout.mjs';
export const bad = fit(1920, { center: 120, leftFixed: 280 }, metrics(1, 'compact'));"

expect_error "no-node-globals-in-qml" "tsconfig.qml.json" "TS2591" \
  "export const env = process.env;"

expect_error "no-dom-globals-in-qml" "tsconfig.qml.json" "TS2304" \
  "export const width = window.innerWidth;"

expect_error "no-es2022-stdlib-in-qml" "tsconfig.qml.json" "TS2550" \
  "export const last = [1, 2, 3].at(-1);"

expect_error "invalid-node-consumer-arg" "tsconfig.node.json" "TS2345" \
  "import * as Layout from '$repo/plugin/geometry/Layout.mjs';
export const bad = Layout.chooseTier('1920', {}, Layout.metrics(1, 'compact'), 'full');"

# Isolated automatic-inclusion probe: adding a new .mjs file under plugin/ must
# enter tsconfig.qml.json's "plugin/**/*.mjs" scope automatically without
# editing tsconfig.qml.json.
auto_dir="$tmp/auto-include"
mkdir -p "$auto_dir/plugin/logic"
cp "$repo/tsconfig.base.json" "$repo/tsconfig.qml.json" "$auto_dir/"
cp -R "$repo/plugin/geometry" "$auto_dir/plugin/geometry"
cat >"$auto_dir/plugin/logic/NewModule.mjs" <<'EOF'
import { partsFor } from "./MissingOrUnused.mjs";
/** @param {number} n */
export function bad(n) { return n; }
export const fail = bad("not-a-number");
EOF
auto_out=$("$TSC" -p "$auto_dir/tsconfig.qml.json" 2>&1)
auto_rc=$?
if (( auto_rc == 0 )) || ! grep -q "TS2345" <<<"$auto_out"; then
  fail "negative[auto-include-new-mjs]: expected TS2345 for newly added plugin/**/*.mjs"
  printf '%s\n' "$auto_out" | sed 's/^/  /' >&2
else
  pass "negative[auto-include-new-mjs] rejected automatically (TS2345)"
fi

if (( failures )); then
  echo "typecheck: $failures check(s) failed" >&2
  exit 1
fi
echo "typecheck: all positive and negative checks passed"
