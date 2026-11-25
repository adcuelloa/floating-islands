#!/usr/bin/env bash
# Automated regression tests for .github/ci/retry.sh using isolated fixtures
# and stubbed package-manager / curl binaries under /tmp. Never touches any
# real system package database or lock file.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=.github/ci/retry.sh
source "$script_dir/retry.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0

ok() {
  echo "ok - $1"
  pass=$((pass + 1))
}

not_ok() {
  echo "NOT ok - $1" >&2
  fail=$((fail + 1))
}

assert_eq() {
  local name=$1 actual=$2 expected=$3
  if [[ $actual == "$expected" ]]; then
    ok "$name"
  else
    not_ok "$name (got '$actual', expected '$expected')"
  fi
}

# Stub binaries in an isolated directory.
bin="$tmp/bin"
mkdir -p "$bin"

cat >"$bin/fake-pacman" <<'EOF'
#!/usr/bin/env bash
count_file=${TEST_COUNT_FILE:?}
mode=${TEST_MODE:?}
lock_file=${CI_PACMAN_LOCK_FILE:?}

n=$(cat "$count_file" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$count_file"

case "$mode" in
  timeout_stale_lock_then_ok)
    if (( n == 1 )); then
      : >"$lock_file"
      sleep 10
    fi
    if [[ -e $lock_file ]]; then
      echo "error: failed to synchronize all databases (unable to lock database)" >&2
      exit 1
    fi
    echo "pacman succeeded on attempt $n"
    exit 0
    ;;
  sigkill_stale_lock_then_ok)
    if (( n == 1 )); then
      trap '' TERM
      : >"$lock_file"
      sleep 10
    fi
    if [[ -e $lock_file ]]; then
      echo "error: failed to synchronize all databases (unable to lock database)" >&2
      exit 1
    fi
    echo "pacman succeeded after sigkill lock recovery on attempt $n"
    exit 0
    ;;
  timeout_no_lock_then_ok)
    if (( n == 1 )); then
      sleep 10
    fi
    echo "pacman succeeded on attempt $n"
    exit 0
    ;;
  timeout_with_active_tx)
    : >"$lock_file"
    sleep 10
    ;;
  preexisting_lock_immediate_fail)
    if [[ -e $lock_file ]]; then
      echo "error: failed to synchronize all databases (unable to lock database)" >&2
      exit 1
    fi
    exit 0
    ;;
  preexisting_lock_timeout)
    sleep 10
    ;;
  always_timeout)
    : >"$lock_file"
    sleep 10
    ;;
  pgp_fatal_rc42)
    echo 'error: foo: signature from "Arch" is invalid' >&2
    echo 'error: failed to commit transaction (invalid or corrupted package (PGP signature))' >&2
    exit 42
    ;;
  not_found_rc7)
    echo 'error: target not found: missing-pkg' >&2
    exit 7
    ;;
  download_commit_error_then_ok)
    if (( n == 1 )); then
      echo 'error: failed retrieving file mesa.pkg.tar.zst from archive.archlinux.org : Operation too slow. Less than 1 bytes/sec transferred the last 10 seconds' >&2
      echo 'warning: failed to retrieve some files' >&2
      echo 'error: failed to commit transaction (failed to retrieve some files)' >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    echo "unknown test mode: $mode" >&2
    exit 99
    ;;
esac
EOF

cat >"$bin/active-yes" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$bin/active-no" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

cat >"$bin/curl" <<'EOF'
#!/usr/bin/env bash
count_file=${TEST_CURL_COUNT_FILE:?}
mode=${TEST_CURL_MODE:?}
n=$(cat "$count_file" 2>/dev/null || echo 0)
n=$((n + 1))
echo "$n" >"$count_file"
out=""
while (( $# )); do
  if [[ $1 == -o ]]; then out=$2; shift 2; else shift; fi
done
case "$mode" in
  503_then_ok)
    if (( n == 1 )); then printf '503'; exit 0; fi
    printf 'good-payload' >"$out"
    printf '200'
    exit 0
    ;;
  bad_sha)
    printf 'tampered-payload' >"$out"
    printf '200'
    exit 0
    ;;
  http_404)
    printf '404'
    exit 0
    ;;
esac
EOF

chmod +x "$bin"/*

export CI_PACMAN_BIN="$bin/fake-pacman"
export CI_PACMAN_BACKOFFS="0 0 0"
export CI_PACMAN_KILL_AFTER=1
export CI_PACMAN_MIN_REMAINING=1
export CI_FETCH_BACKOFFS="0 0 0"

run_pacman_case() {
  local mode=$1 active_check=$2 timeout_s=$3 deadline_offset=$4
  local lock="$tmp/$mode.lck"
  local count="$tmp/$mode.count"
  rm -f "$lock" "$count"
  if [[ ${PRECREATE_LOCK:-0} == 1 ]]; then
    printf 'preexisting\n' >"$lock"
  fi
  local rc=0
  CI_PACMAN_LOCK_FILE="$lock" \
  CI_PACMAN_ACTIVE_CHECK="$active_check" \
  TEST_MODE="$mode" \
  TEST_COUNT_FILE="$count" \
    ci_pacman_retry "$(( $(date +%s) + deadline_offset ))" "$timeout_s" -- -Syu --noconfirm git >/dev/null 2>&1 || rc=$?
  LAST_RC=$rc
  LAST_COUNT=$(cat "$count" 2>/dev/null || echo 0)
  LAST_LOCK=$lock
}

# 1. Timeout (SIGTERM, rc=124) leaving a stale lock -> safe recovery + successful retry
PRECREATE_LOCK=0 run_pacman_case timeout_stale_lock_then_ok "$bin/active-no" 1 30
assert_eq "timeout leaving stale lock recovers and retries to success (rc=0)" "$LAST_RC" "0"
assert_eq "timeout leaving stale lock runs 2 attempts" "$LAST_COUNT" "2"
assert_eq "timeout leaving stale lock leaves no residual lock" "$(test -e "$LAST_LOCK" && echo yes || echo no)" "no"

# 2. Timeout escalation (SIGKILL, rc=137) leaving a stale lock -> safe recovery + successful retry
PRECREATE_LOCK=0 run_pacman_case sigkill_stale_lock_then_ok "$bin/active-no" 1 30
assert_eq "SIGKILL timeout escalation recovers stale lock and succeeds (rc=0)" "$LAST_RC" "0"
assert_eq "SIGKILL timeout escalation runs 2 attempts" "$LAST_COUNT" "2"
assert_eq "SIGKILL timeout escalation leaves no residual lock" "$(test -e "$LAST_LOCK" && echo yes || echo no)" "no"

# 3. Timeout without a residual lock -> retries cleanly
PRECREATE_LOCK=0 run_pacman_case timeout_no_lock_then_ok "$bin/active-no" 1 30
assert_eq "timeout without residual lock retries to success (rc=0)" "$LAST_RC" "0"
assert_eq "timeout without residual lock runs 2 attempts" "$LAST_COUNT" "2"

# 4. Active package transaction prevents lock removal and aborts with timeout rc
PRECREATE_LOCK=0 run_pacman_case timeout_with_active_tx "$bin/active-yes" 1 30
assert_eq "active transaction prevents lock removal and propagates rc=124" "$LAST_RC" "124"
assert_eq "active transaction stops after 1 attempt" "$LAST_COUNT" "1"
assert_eq "active transaction preserves lock file" "$(test -e "$LAST_LOCK" && echo yes || echo no)" "yes"

# 5a. Pre-existing lock causing immediate unable-to-lock error is NOT retried and NOT removed
PRECREATE_LOCK=1 run_pacman_case preexisting_lock_immediate_fail "$bin/active-no" 5 30
assert_eq "pre-existing lock immediate error fails with rc=1" "$LAST_RC" "1"
assert_eq "pre-existing lock immediate error is not retried (1 attempt)" "$LAST_COUNT" "1"
assert_eq "pre-existing lock immediate error preserves lock file" "$(cat "$LAST_LOCK" 2>/dev/null || true)" "preexisting"

# 5b. Pre-existing lock when attempt times out is NOT removed and aborts
PRECREATE_LOCK=1 run_pacman_case preexisting_lock_timeout "$bin/active-no" 1 30
assert_eq "pre-existing lock on timeout aborts with rc=124" "$LAST_RC" "124"
assert_eq "pre-existing lock on timeout stops after 1 attempt" "$LAST_COUNT" "1"
assert_eq "pre-existing lock on timeout preserves lock file" "$(cat "$LAST_LOCK" 2>/dev/null || true)" "preexisting"

# 6. Repeated timeouts reaching overall deadline stop cleanly, propagate rc=124, leave no stale lock
PRECREATE_LOCK=0 run_pacman_case always_timeout "$bin/active-no" 1 2
assert_eq "repeated timeouts hitting deadline propagate rc=124" "$LAST_RC" "124"
assert_eq "repeated timeouts hitting deadline leave no stale lock" "$(test -e "$LAST_LOCK" && echo yes || echo no)" "no"
if (( LAST_COUNT >= 1 && LAST_COUNT < 4 )); then
  ok "repeated timeouts stopped before max_attempts by deadline (attempts=$LAST_COUNT)"
else
  not_ok "repeated timeouts should stop before max_attempts by deadline (attempts=$LAST_COUNT)"
fi

# 7. Fatal integrity / unavailable package errors remain non-retryable and propagate exact exit codes
PRECREATE_LOCK=0 run_pacman_case pgp_fatal_rc42 "$bin/active-no" 5 30
assert_eq "PGP fatal error propagates exact exit code (rc=42)" "$LAST_RC" "42"
assert_eq "PGP fatal error is never retried (1 attempt)" "$LAST_COUNT" "1"

PRECREATE_LOCK=0 run_pacman_case not_found_rc7 "$bin/active-no" 5 30
assert_eq "target-not-found propagates exact exit code (rc=7)" "$LAST_RC" "7"
assert_eq "target-not-found is never retried (1 attempt)" "$LAST_COUNT" "1"

# 8. Transient download commit failure retries cleanly
PRECREATE_LOCK=0 run_pacman_case download_commit_error_then_ok "$bin/active-no" 5 30
assert_eq "transient download commit error retries to success (rc=0)" "$LAST_RC" "0"
assert_eq "transient download commit error runs 2 attempts" "$LAST_COUNT" "2"

# 9. ci_fetch_verified: 503 retries, SHA-256 mismatch and HTTP 404 fail immediately
good_sha=$(printf 'good-payload' | sha256sum | cut -d' ' -f1)

rc=0
rm -f "$tmp/curl.count" "$tmp/pkg"
PATH="$bin:$PATH" TEST_CURL_MODE=503_then_ok TEST_CURL_COUNT_FILE="$tmp/curl.count" \
  ci_fetch_verified "$(( $(date +%s) + 60 ))" "https://example.invalid/pkg" "$good_sha" "$tmp/pkg" >/dev/null 2>&1 || rc=$?
assert_eq "fetch 503 retries and verifies sha256 (rc=0)" "$rc" "0"
assert_eq "fetch 503 runs 2 attempts" "$(cat "$tmp/curl.count")" "2"

rc=0
rm -f "$tmp/curl.count" "$tmp/pkg"
PATH="$bin:$PATH" TEST_CURL_MODE=bad_sha TEST_CURL_COUNT_FILE="$tmp/curl.count" \
  ci_fetch_verified "$(( $(date +%s) + 60 ))" "https://example.invalid/pkg" "$good_sha" "$tmp/pkg" >/dev/null 2>&1 || rc=$?
assert_eq "fetch sha256 mismatch fails with rc=1" "$rc" "1"
assert_eq "fetch sha256 mismatch is never retried (1 attempt)" "$(cat "$tmp/curl.count")" "1"
assert_eq "fetch sha256 mismatch deletes corrupt file" "$(test -e "$tmp/pkg" && echo yes || echo no)" "no"

rc=0
rm -f "$tmp/curl.count" "$tmp/pkg"
PATH="$bin:$PATH" TEST_CURL_MODE=http_404 TEST_CURL_COUNT_FILE="$tmp/curl.count" \
  ci_fetch_verified "$(( $(date +%s) + 60 ))" "https://example.invalid/pkg" "$good_sha" "$tmp/pkg" >/dev/null 2>&1 || rc=$?
assert_eq "fetch HTTP 404 fails with rc=1" "$rc" "1"
assert_eq "fetch HTTP 404 is never retried (1 attempt)" "$(cat "$tmp/curl.count")" "1"

echo "retry-self-test: $pass passed, $fail failed"
(( fail == 0 ))
