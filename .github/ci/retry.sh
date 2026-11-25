# Bounded retry helpers for CI downloads from immutable pinned sources.
#
# Preserves exact package versions, archive dates, SHA-256 digests, and pacman
# signature verification. Retries ONLY transient transport failures with
# exponential backoff inside an overall deadline; integrity failures, signature
# errors, HTTP 404 / missing pinned packages, dependency conflicts, and foreign
# or active database locks fail immediately without retrying.

ci_pacman_is_fatal() {
  local log=$1
  grep -qiE \
    'invalid or corrupted (package|database)|pgp signature|signature from .* is|could not be verified|checksum|missing signature|conflicting files|target not found|returned error: 404|404 not found|could not satisfy dependencies|are in conflict|breaks dependency' \
    "$log"
}

ci_pacman_is_transient() {
  local rc=$1 log=$2 timed_out=${3:-0}
  (( timed_out == 1 || rc == 124 )) && return 0
  grep -qiE \
    'connection timed out|operation timed out|operation too slow|resolving timed out|could not resolve host|failed to connect|connection reset by peer|ssl connection timeout|tls connect error|empty reply from server|returned error: (408|429|500|502|503|504)|recv failure|send failure|transferred a partial file|failed retrieving file' \
    "$log"
}

ci_pacman_is_active() {
  if [[ -n ${CI_PACMAN_ACTIVE_CHECK:-} ]]; then
    "$CI_PACMAN_ACTIVE_CHECK"
    return $?
  fi
  local proc_comm pid comm stat state
  for proc_comm in /proc/[0-9]*/comm; do
    [[ -r $proc_comm ]] || continue
    IFS= read -r comm <"$proc_comm" 2>/dev/null || continue
    if [[ $comm == "pacman" ]]; then
      pid=${proc_comm#/proc/}
      pid=${pid%/comm}
      stat=$(cat "/proc/$pid/stat" 2>/dev/null) || continue
      state=${stat##*) }
      state=${state%% *}
      [[ $state != Z ]] && return 0
    fi
  done
  return 1
}

ci_pacman_wait_inactive() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    ci_pacman_is_active || return 0
    sleep 0.2
  done
  return 1
}

# Safely recover a pacman database lock ONLY when:
#   1. The CI-owned pacman attempt timed out (SIGTERM or SIGKILL escalation),
#   2. No lock file existed before this attempt started,
#   3. The lock path is a regular non-symlink file, and
#   4. No pacman process is still active after process-group termination.
ci_pacman_recover_stale_lock() {
  local lock_file=$1 had_preexisting_lock=$2 rc=$3
  if [[ ! -e $lock_file && ! -L $lock_file ]]; then
    return 0
  fi
  if (( had_preexisting_lock )); then
    echo "::error::pacman lock $lock_file existed prior to timed-out attempt (rc=$rc); refusing to remove" >&2
    return 1
  fi
  if [[ -L $lock_file || ! -f $lock_file ]]; then
    echo "::error::pacman lock $lock_file is not a regular file (rc=$rc); refusing to remove" >&2
    return 1
  fi
  if ! ci_pacman_wait_inactive; then
    echo "::error::pacman transaction still active after timeout (rc=$rc); refusing to remove $lock_file" >&2
    return 1
  fi
  rm -f -- "$lock_file"
  echo "::warning::removed stale pacman lock $lock_file left by timed-out CI attempt (rc=$rc)" >&2
  return 0
}

# Usage: ci_pacman_retry <deadline_epoch> <attempt_timeout_sec> -- <pacman args...>
ci_pacman_retry() {
  local deadline=$1 attempt_timeout=$2
  shift 2
  [[ ${1:-} == -- ]] && shift

  local lock_file=${CI_PACMAN_LOCK_FILE:-/var/lib/pacman/db.lck}
  local pacman_bin=${CI_PACMAN_BIN:-pacman}
  local kill_after=${CI_PACMAN_KILL_AFTER:-10}
  local min_remaining=${CI_PACMAN_MIN_REMAINING:-20}
  local -a backoffs=(10 20 40)
  if [[ -n ${CI_PACMAN_BACKOFFS:-} ]]; then
    read -r -a backoffs <<<"$CI_PACMAN_BACKOFFS"
  fi
  local max_attempts=$(( ${#backoffs[@]} + 1 ))
  local attempt=1 rc=0 now remaining wait_s log start_s elapsed timed_out had_preexisting_lock

  log=$(mktemp)
  while (( attempt <= max_attempts )); do
    now=$(date +%s)
    remaining=$(( deadline - now ))
    if (( remaining < min_remaining )); then
      echo "::error::pacman overall deadline reached (${remaining}s remaining) before attempt ${attempt}/${max_attempts}" >&2
      rm -f "$log"
      return 1
    fi
    local cap=$attempt_timeout
    (( remaining < cap )) && cap=$remaining

    had_preexisting_lock=0
    [[ -e $lock_file || -L $lock_file ]] && had_preexisting_lock=1

    : >"$log"
    rc=0
    start_s=$(date +%s)
    # GNU timeout (without --foreground) runs pacman in its own process group,
    # sends SIGTERM to the group at $cap, and escalates to SIGKILL after
    # $kill_after seconds so hung libalpm/child processes cannot linger.
    timeout -k "$kill_after" "$cap" "$pacman_bin" --disable-download-timeout "$@" 2>&1 | tee "$log" || rc=${PIPESTATUS[0]}
    elapsed=$(( $(date +%s) - start_s ))

    if (( rc == 0 )); then
      rm -f "$log"
      return 0
    fi

    timed_out=0
    if (( rc == 124 )) || (( rc == 137 && elapsed >= cap )); then
      timed_out=1
    fi

    if (( timed_out )); then
      if ! ci_pacman_recover_stale_lock "$lock_file" "$had_preexisting_lock" "$rc"; then
        rm -f "$log"
        return "$rc"
      fi
    fi

    if ci_pacman_is_fatal "$log"; then
      echo "::error::pacman failed with non-retryable integrity/package error (rc=$rc); not retrying" >&2
      rm -f "$log"
      return "$rc"
    fi

    if ! ci_pacman_is_transient "$rc" "$log" "$timed_out"; then
      echo "::error::pacman failed with non-transport error (rc=$rc); not retrying" >&2
      rm -f "$log"
      return "$rc"
    fi

    if (( attempt == max_attempts )); then
      echo "::error::pacman transient transport failure persisted after ${max_attempts} attempts (rc=$rc)" >&2
      rm -f "$log"
      return "$rc"
    fi

    wait_s=${backoffs[$((attempt - 1))]}
    now=$(date +%s)
    remaining=$(( deadline - now ))
    if (( remaining <= wait_s + min_remaining )); then
      echo "::error::pacman transient transport failure (rc=$rc) and overall deadline reached (${remaining}s remaining)" >&2
      rm -f "$log"
      return "$rc"
    fi

    echo "::warning::pacman transient transport failure (attempt ${attempt}/${max_attempts}, rc=$rc); retrying in ${wait_s}s" >&2
    (( wait_s > 0 )) && sleep "$wait_s"
    attempt=$(( attempt + 1 ))
  done

  rm -f "$log"
  return 1
}

# Usage: ci_fetch_verified <deadline_epoch> <url> <sha256> <dest_file>
ci_fetch_verified() {
  local deadline=$1 url=$2 sum=$3 dest=$4
  local -a backoffs=(10 20 40)
  if [[ -n ${CI_FETCH_BACKOFFS:-} ]]; then
    read -r -a backoffs <<<"$CI_FETCH_BACKOFFS"
  fi
  local max_attempts=$(( ${#backoffs[@]} + 1 ))
  local attempt=1 rc=0 http_code="" now remaining cap wait_s err

  err=$(mktemp)
  while (( attempt <= max_attempts )); do
    now=$(date +%s)
    remaining=$(( deadline - now ))
    if (( remaining < 15 )); then
      echo "::error::fetch overall deadline reached (${remaining}s remaining) for $url" >&2
      rm -f "$err" "$dest"
      return 1
    fi
    cap=180
    (( remaining < cap )) && cap=$remaining

    : >"$err"
    rm -f "$dest"
    rc=0
    http_code=$(curl -sSL \
      --connect-timeout 30 \
      --speed-time 30 --speed-limit 1024 \
      --max-time "$cap" \
      -o "$dest" -w '%{http_code}' \
      "$url" 2>"$err") || rc=$?

    if (( rc == 0 )) && [[ $http_code == 200 ]]; then
      if echo "$sum  $dest" | sha256sum -c --quiet - >&2; then
        rm -f "$err"
        return 0
      fi
      echo "::error::sha256 mismatch for $url (integrity failure — not retrying)" >&2
      rm -f "$err" "$dest"
      return 1
    fi

    [[ -s $err ]] && cat "$err" >&2
    rm -f "$dest"

    case "$http_code" in
      400|401|403|404|410)
        echo "::error::pinned artifact unavailable ($url, HTTP $http_code — not retrying)" >&2
        rm -f "$err"
        return 1
        ;;
    esac

    local transient=0
    case "$rc" in
      6|7|18|28|35|52|55|56|92) transient=1 ;;
    esac
    case "$http_code" in
      000|408|429|500|502|503|504) transient=1 ;;
    esac

    if (( ! transient )); then
      echo "::error::fetch failed with non-retryable error for $url (curl rc=$rc, HTTP ${http_code:-none})" >&2
      rm -f "$err"
      return 1
    fi

    if (( attempt == max_attempts )); then
      echo "::error::fetch transient transport failure persisted after ${max_attempts} attempts for $url (curl rc=$rc, HTTP ${http_code:-none})" >&2
      rm -f "$err"
      return 1
    fi

    wait_s=${backoffs[$((attempt - 1))]}
    now=$(date +%s)
    remaining=$(( deadline - now ))
    if (( remaining <= wait_s + 15 )); then
      echo "::error::fetch transient failure for $url and overall deadline reached (${remaining}s remaining)" >&2
      rm -f "$err"
      return 1
    fi

    echo "::warning::fetch transient transport failure for $url (attempt ${attempt}/${max_attempts}, curl rc=$rc, HTTP ${http_code:-none}); retrying in ${wait_s}s" >&2
    (( wait_s > 0 )) && sleep "$wait_s"
    attempt=$(( attempt + 1 ))
  done

  rm -f "$err" "$dest"
  return 1
}
