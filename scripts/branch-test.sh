#!/usr/bin/env bash
# A supervised test of a development build while this bar is the persistent
# daily bar. Arming snapshots the installed plugin and shell.json and sets a
# wall-clock deadline at which they are put back by themselves, so the test
# ends even if the terminal or the session that started it is gone.
#
#   branch-test.sh --arm 45     snapshot, restore by itself in 45 min (1-240)
#   (then scripts/install.sh and `omarchy restart shell` to load the build)
#   branch-test.sh --restore    put the snapshot back now and restart the shell
#   branch-test.sh --accept     keep the current build, stop rollback, preserve snapshot backup
#   branch-test.sh --status     the snapshot and the deadline, if armed
#
# This restores the previous Floating Islands installation. It is not the
# emergency path: scripts/rollback.sh (works from a TTY) returns the stock
# Omarchy bar and needs nothing from here.
#
# State: a private directory (mode 700, checked before every use) under
# ~/.local/state with the plugin, shell.json, their checksums and a copy of
# this script, so a restore depends on neither the repository's branch nor
# the session that armed it. Two triggers, both temporary:
#   - an OnCalendar (wall-clock) transient timer at the deadline. A monotonic
#     OnActiveSec timer pauses during suspend; this one fires on resume.
#   - a user unit started at the next login, for a reboot before the
#     deadline (transient timers do not survive one). It is ordered before
#     the graphical session, so the shell starts from the restored files.
# Both are removed once the restored files verify. A restart refused while
# the screen is locked is retried every 5 min, at most 24 times; the files
# are already back by then.
# Self-contained like rollback.sh: needs bash, jq, coreutils, util-linux
# (flock) and systemd.
set -uo pipefail

OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
config="$HOME/.config/omarchy/shell.json"
plugins_dir="$HOME/.config/omarchy/plugins"
state_root=${XDG_STATE_HOME:-$HOME/.local/state}
state=${ISLANDS_BRANCH_TEST_DIR:-$state_root/islands-branch-test}
backup_root=${ISLANDS_BRANCH_TEST_BACKUP_DIR:-${state}-backups}
unit=islands-branch-restore
boot_unit=islands-branch-restore-boot.service
boot_unit_file="$HOME/.config/systemd/user/$boot_unit"
protocol_version=2
lock_wait_seconds=${ISLANDS_BRANCH_TEST_LOCK_WAIT:-60}
retry_minutes=5
retry_limit=24

say() { printf 'branch-test.sh: %s\n' "$*"; }
die() { printf 'branch-test.sh: %s\n' "$*" >&2; exit 1; }

deadline_in() { date -d "+$1 min" '+%Y-%m-%d %H:%M:%S'; }

new_session_id() {
  local uuid=""
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    read -r uuid </proc/sys/kernel/random/uuid || true
  fi
  if [[ $uuid =~ ^[0-9a-fA-F-]+$ ]]; then
    printf '%s\n' "$uuid"
  else
    printf '%s-%s-%s\n' "$(date +%Y%m%d%H%M%S%N)" "$$" "$RANDOM"
  fi
}

# Close the lock fd (8) before running external commands so systemd, child
# processes or a restarted shell can never inherit and hold $state/lock.
run_systemctl() { systemctl "$@" 8>&-; }
run_systemd_run() { systemd-run "$@" 8>&-; }

# A private directory is trusted only if it is ours, private (700) and real.
dir_safe() {
  [[ -d $1 && ! -L $1 && -O $1 && $(stat -c %a "$1") == 700 ]]
}

state_safe() {
  dir_safe "$state"
}

# Acquire an exclusive lock on $state/lock.
# mode="nowait" (manual invocations) fails fast; mode="wait" (dispatched
# automatic triggers) waits up to $lock_wait_seconds so lock contention with
# --accept never drops a recovery obligation.
# Returns 0 when the lock is held on the live $state/lock inode,
# returns 2 when mode="wait" observes that $state was retired/replaced while waiting.
acquire_lock() {
  local mode=${1:-nowait}
  if [[ ! -e $state && ! -L $state ]]; then
    [[ $mode == wait ]] && return 2
    die "nothing armed ($state)"
  fi
  state_safe || die "$state is not a private directory; refusing to proceed"
  [[ ! -L $state/lock ]] || die "unsafe lock file in $state"
  if ! exec 8>"$state/lock" 2>/dev/null; then
    if [[ $mode == wait && ! -e $state && ! -L $state ]]; then
      return 2
    fi
    die "could not open lock in $state"
  fi
  if [[ $mode == wait ]]; then
    flock -w "$lock_wait_seconds" 8 || { exec 8>&-; die "timed out waiting for lock in $state"; }
  else
    flock -n 8 || { exec 8>&-; die "another restore or accept is running"; }
  fi
  if [[ ! -e $state && ! -L $state ]]; then
    exec 8>&-
    [[ $mode == wait ]] && return 2
    die "$state disappeared while acquiring lock; refusing to proceed"
  fi
  state_safe || { exec 8>&-; die "$state is no longer a private directory; refusing to proceed"; }
  if [[ ! -f $state/lock || -L $state/lock || ! $state/lock -ef /dev/fd/8 ]]; then
    exec 8>&-
    [[ $mode == wait ]] && return 2
    die "$state changed while acquiring lock; refusing to proceed"
  fi
  return 0
}

# Atomically retire $state via same-filesystem rename before deleting it, so
# an interrupted deletion can never leave an accepted snapshot exposed as
# restorable or lose terminal markers before retirement commits.
retire_state_dir() {
  local retired
  retired=$(umask 077 && mktemp -d "${state}.retired.XXXXXX") || return 1
  if ! mv -- "$state" "$retired/state"; then
    rmdir -- "$retired" 2>/dev/null || true
    return 1
  fi
  exec 8>&- 2>/dev/null || true
  if ! rm -rf -- "$retired"; then
    say "retired state left at $retired; remove it manually" >&2
    return 2
  fi
  return 0
}

# Validate that an automatic trigger's --session matches the active session.
# Returns 0 if no session was requested (manual invocation) or it matches;
# returns 1 if the trigger is stale (belongs to an earlier session).
session_matches() {
  local expected=$1
  [[ -z $expected ]] && return 0
  [[ -f $state/session && ! -L $state/session ]] || return 1
  [[ $(<"$state/session") == "$expected" ]]
}

# Every regular file in a plugin tree with its checksum, in a stable order.
tree_sums() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum); }

# Verify an armed snapshot directory's required files, safety and checksums.
verify_snapshot_dir() {
  local dir=$1
  local id
  [[ -f $dir/complete && ! -L $dir/complete ]] || return 1
  [[ -f $dir/id && ! -L $dir/id && -s $dir/id ]] || return 1
  [[ -d $dir/plugin && ! -L $dir/plugin ]] || return 1
  [[ -f $dir/plugin.sha256 && ! -L $dir/plugin.sha256 && -s $dir/plugin.sha256 ]] || return 1
  [[ -f $dir/shell.json && ! -L $dir/shell.json && -s $dir/shell.json ]] || return 1
  [[ -f $dir/shell.json.sha256 && ! -L $dir/shell.json.sha256 && -s $dir/shell.json.sha256 ]] || return 1
  id=$(<"$dir/id")
  [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || return 1
  [[ -z $(find "$dir/plugin" -type l -print -quit) ]] || return 1
  jq -e 'type == "object" and .version == 1' "$dir/shell.json" >/dev/null 2>&1 || return 1
  [[ $(tree_sums "$dir/plugin") == $(<"$dir/plugin.sha256") ]] || return 1
  [[ $(sha256sum "$dir/shell.json" | cut -d' ' -f1) == $(<"$dir/shell.json.sha256") ]] || return 1
}

# Verify that the currently installed plugin and shell.json are valid and select
# the expected plugin id. Never mutates the live installation or configuration.
verify_current_install() {
  local id=$1
  local current_id entry
  [[ -f $config && ! -L $config && -s $config ]] || die "current shell.json is missing or unreadable"
  jq -e 'type == "object" and .version == 1' "$config" >/dev/null 2>&1 \
    || die "current shell.json is not a valid Omarchy shell.json (version 1)"
  current_id=$(jq -r '.bar.id // empty' "$config")
  [[ $current_id == "$id" ]] \
    || die "selected bar is '${current_id:-stock}', expected '$id'; refusing to accept"

  local target="$plugins_dir/$id"
  [[ -d $target && ! -L $target ]] || die "current plugin $id is not installed at $target"
  [[ -z $(find "$target" -type l -print -quit) ]] || die "current plugin $id contains symlinks; refusing to accept"
  [[ -f $target/manifest.json && ! -L $target/manifest.json ]] || die "current plugin $id is missing manifest.json"
  jq -e --arg id "$id" '
      type == "object"
      and .schemaVersion == 1
      and .id == $id
      and (.kinds | type == "array")
      and ((.kinds | index("bar")) != null)
      and (.entryPoints.bar | type == "string")
      and (.entryPoints.bar | length > 0)
    ' "$target/manifest.json" >/dev/null 2>&1 \
    || die "current plugin $id has an invalid manifest.json; refusing to accept"
  entry=$(jq -r '.entryPoints.bar' "$target/manifest.json")
  [[ $entry != /* && $entry != *..* && -f "$target/$entry" && ! -L "$target/$entry" ]] \
    || die "current plugin $id is missing bar entry point '$entry'; refusing to accept"
  if [[ -x $OMARCHY_PATH/bin/omarchy-plugin-validate ]]; then
    "$OMARCHY_PATH/bin/omarchy-plugin-validate" "$target" >/dev/null 2>&1 8>&- \
      || die "omarchy-plugin-validate rejected current plugin $id; refusing to accept"
  fi
}

stop_restore_timer_strict() {
  local err rc=0
  err=$(run_systemctl --user stop "$unit.timer" 2>&1) || rc=$?
  if (( rc != 0 )); then
    # Exit 5 ("Unit ... not loaded") means the transient timer is already gone.
    if (( rc == 5 )) || [[ $err == *"not loaded"* ]]; then
      return 0
    fi
    return "$rc"
  fi
  run_systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
  return 0
}

remove_boot_unit_strict() {
  local wants_link="$HOME/.config/systemd/user/default.target.wants/$boot_unit"
  if [[ -e $boot_unit_file || -L $boot_unit_file || -L $wants_link ]]; then
    run_systemctl --user disable --quiet "$boot_unit" >/dev/null 2>&1 || return 1
    if [[ -e $boot_unit_file || -L $boot_unit_file ]]; then
      rm -f -- "$boot_unit_file" || return 1
    fi
    [[ ! -e $boot_unit_file && ! -L $boot_unit_file && ! -L $wants_link ]] || return 1
  fi
  # Always reload the systemd user manager so a retry after unit/symlink
  # removal still completes daemon-reload before reporting cleanup success.
  run_systemctl --user daemon-reload >/dev/null 2>&1 || return 1
  return 0
}

arm_timer() { # <minutes> <args for the snapshot's copy...>
  local minutes=$1
  shift
  run_systemctl --user stop "$unit.timer" >/dev/null 2>&1 || true
  run_systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
  run_systemd_run --user --quiet --unit="$unit" --on-calendar="$(deadline_in "$minutes")" \
    --timer-property=AccuracySec=5s --setenv=OMARCHY_PATH="$OMARCHY_PATH" \
    --setenv=ISLANDS_BRANCH_TEST_DIR="$state" /bin/bash "$state/branch-test.sh" "$@"
}

write_boot_unit() {
  local sid=$1
  mkdir -p "${boot_unit_file%/*}" || return 1
  cat >"$boot_unit_file.tmp" <<EOF || return 1
# Temporary: written by Floating Islands branch-test.sh --arm, removed by its
# restore. Puts the persistent bar back after a reboot during a supervised test.
[Unit]
Description=Floating Islands: restore the persistent bar after a supervised test
ConditionPathExists=$state/complete
Before=graphical-session-pre.target

[Service]
Type=oneshot
Environment=OMARCHY_PATH=$OMARCHY_PATH
Environment=ISLANDS_BRANCH_TEST_DIR=$state
ExecStart=/bin/bash $state/branch-test.sh --restore --session $sid

[Install]
WantedBy=default.target
EOF
  mv -- "$boot_unit_file.tmp" "$boot_unit_file" && run_systemctl --user enable --quiet "$boot_unit"
}

remove_boot_unit() {
  [[ -e $boot_unit_file ]] || return 0
  run_systemctl --user disable --quiet "$boot_unit" >/dev/null 2>&1 || true
  rm -f -- "$boot_unit_file"
  run_systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# Only a running desktop has a shell to restart; at login (the boot unit),
# the shell has not started yet and will read the restored files.
session_up() { pgrep -x -u "$(id -u)" Hyprland >/dev/null 2>&1 8>&-; }

restart_shell() { "$OMARCHY_PATH/bin/omarchy-restart-shell" >/dev/null 2>&1 8>&-; }

cmd_arm() {
  local minutes=${1:-}
  [[ $minutes =~ ^[1-9][0-9]{0,2}$ ]] && (( minutes <= 240 )) || die "--arm takes 1-240 minutes"
  command -v jq >/dev/null && command -v flock >/dev/null || die "jq and flock are required"
  [[ -s $config ]] && jq -e . "$config" >/dev/null 2>&1 || die "shell.json is missing or unreadable"
  local id
  id=$(jq -r '.bar.id // empty' "$config")
  [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || die "no plugin bar is selected; this is for testing over a persistent one"
  [[ -d $plugins_dir/$id && ! -L $plugins_dir/$id ]] || die "the selected bar $id is not installed in $plugins_dir"
  [[ -z $(find "$plugins_dir/$id" -type l -print -quit) ]] || die "the installed $id contains symlinks; not snapshotting it"

  if [[ -e $state || -L $state ]]; then
    [[ -e $state/accepted ]] && die "previous session in $state was accepted but cleanup is incomplete; run --accept to finish cleanup"
    [[ -e $state/restoring ]] && die "a restore is in progress in $state; run --restore to finish"
    [[ -e $state/complete ]] && die "already armed ($state); run --restore, --accept or --status"
    die "an incomplete snapshot is in $state (an interrupted --arm); check it, remove it, then arm again"
  fi
  mkdir -p "${state%/*}" && mkdir -m 700 -- "$state" || die "could not create $state"
  state_safe || die "$state is not a private directory"

  local sid
  sid=$(new_session_id)
  # complete is written last; a restore refuses a snapshot without it.
  if ! { cp -a "$plugins_dir/$id" "$state/plugin" &&
         tree_sums "$plugins_dir/$id" >"$state/plugin.sha256" &&
         [[ $(tree_sums "$state/plugin") == $(<"$state/plugin.sha256") ]] &&
         cp -p "$config" "$state/shell.json" &&
         cmp -s "$config" "$state/shell.json" &&
         sha256sum "$state/shell.json" | cut -d' ' -f1 >"$state/shell.json.sha256" &&
         printf '%s\n' "$id" >"$state/id" &&
         printf '%s\n' "$protocol_version" >"$state/protocol" &&
         printf '%s\n' "$sid" >"$state/session" &&
         cp "${BASH_SOURCE[0]}" "$state/branch-test.sh" &&
         : >"$state/complete"; }; then
    rm -rf -- "$state"
    die "could not write the snapshot; nothing was armed"
  fi
  if ! write_boot_unit "$sid"; then
    remove_boot_unit
    rm -rf -- "$state"
    die "could not install the login restore; nothing was armed"
  fi
  if ! arm_timer "$minutes" --restore --session "$sid"; then
    remove_boot_unit
    rm -rf -- "$state"
    die "could not arm the restore timer; nothing was armed"
  fi
  say "snapshot of $id and shell.json in $state (session $sid)"
  say "restores by itself at $(deadline_in "$minutes") (wall clock), or at the next login after a reboot"
}

cmd_restore() {
  local expected_session=${1:-}
  local lock_mode=nowait lock_rc=0
  if [[ -n $expected_session ]]; then
    [[ $expected_session =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid session id '$expected_session'"
    lock_mode=wait
  fi
  acquire_lock "$lock_mode" || lock_rc=$?
  if (( lock_rc == 2 )); then
    say "session $expected_session is no longer active; nothing to restore"
    return 0
  fi
  if ! session_matches "$expected_session"; then
    say "ignoring stale restore trigger for session $expected_session"
    exec 8>&-
    return 0
  fi
  if [[ -e $state/accepted ]]; then
    local kept
    kept=$(cat "$state/accepted" 2>/dev/null || true)
    exec 8>&-
    if [[ -n $expected_session ]]; then
      say "session $expected_session was already accepted (backup in ${kept:-unknown}); not restoring"
      return 0
    fi
    die "session in $state was already accepted (backup in ${kept:-unknown}); refusing to restore"
  fi
  [[ -e $state/complete && -s $state/shell.json && -d $state/plugin && -s $state/id ]] \
    || die "the snapshot in $state is incomplete; run scripts/rollback.sh"
  local id active_session=""
  id=$(<"$state/id")
  [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || die "the snapshot names no usable plugin id"
  jq -e . "$state/shell.json" >/dev/null 2>&1 || die "the snapshot's shell.json is unreadable; run scripts/rollback.sh"
  verify_snapshot_dir "$state" || die "the snapshot in $state failed integrity verification; snapshot kept"
  if [[ -f $state/session && ! -L $state/session ]]; then
    active_session=$(<"$state/session")
  fi

  # Mark restoration started before modifying live files so --accept cannot race
  # or run during a locked-screen --restart retry window.
  : >"$state/restoring" || die "could not record restore state in $state"

  # A complete copy swapped in, so the shell's watcher never sees half a plugin.
  # An interrupted run leaves the snapshot intact and can simply run again.
  local target="$plugins_dir/$id" next="$plugins_dir/.$id.next" old="$plugins_dir/.$id.old"
  mkdir -p "$plugins_dir"
  rm -rf -- "$next" "$old"
  cp -a "$state/plugin" "$next" || die "could not copy the plugin back; run scripts/rollback.sh"
  if [[ -e $target || -L $target ]]; then
    mv -- "$target" "$old" || die "could not move the test build aside"
  fi
  mv -- "$next" "$target" || die "could not put the plugin back; run scripts/rollback.sh"
  rm -rf -- "$old"

  # Same directory, then mv: the shell never reads a half-written file.
  local tmp="$config.branch-test.$$"
  { cp -p "$state/shell.json" "$tmp" && mv -- "$tmp" "$config"; } || { rm -f -- "$tmp"; die "could not put shell.json back"; }

  # Nothing is cleaned up until both verify.
  [[ $(tree_sums "$target") == $(<"$state/plugin.sha256") ]] || die "the restored plugin does not match the snapshot; snapshot kept"
  [[ $(sha256sum "$config" | cut -d' ' -f1) == $(<"$state/shell.json.sha256") ]] || die "shell.json does not match the snapshot; snapshot kept"
  say "restored $id and shell.json (checksums match)"
  run_systemctl --user stop "$unit.timer" >/dev/null 2>&1 || true
  remove_boot_unit

  if ! session_up; then
    say "no desktop session; the shell will start from the restored files"
  elif restart_shell; then
    # The bar's own QML is only rebuilt by a restart (a plugin reload does not).
    say "shell restarted"
  else
    say "the shell refused to restart (locked screen?); retrying every $retry_minutes min"
    if [[ -n $active_session ]]; then
      arm_timer "$retry_minutes" --restart 1 --session "$active_session" || say "could not arm the retry; run: omarchy restart shell"
    else
      arm_timer "$retry_minutes" --restart 1 || say "could not arm the retry; run: omarchy restart shell"
    fi
    exec 8>&-
    return 0
  fi
  retire_state_dir || die "restored files, but could not retire $state"
}

cmd_accept() {
  command -v jq >/dev/null && command -v flock >/dev/null && command -v sha256sum >/dev/null \
    || die "jq, flock and sha256sum are required"
  acquire_lock nowait

  if [[ -e $state/restoring ]]; then
    die "restore has already started in $state; refusing to accept (run --restore to finish)"
  fi

  # Reject snapshots armed by legacy script versions that do not support the
  # acceptance protocol or per-arm session identity. Never rewrite them in place.
  if [[ ! -f $state/protocol || -L $state/protocol || $(<"$state/protocol") != "$protocol_version" || ! -f $state/session || -L $state/session || ! $(<"$state/session") =~ ^[A-Za-z0-9._-]+$ ]]; then
    die "snapshot in $state was armed by a legacy script version that does not support --accept; run --restore and re-arm with the current branch-test.sh"
  fi

  local backup_dir="" id=""
  if [[ -e $state/accepted ]]; then
    [[ -f $state/accepted && ! -L $state/accepted ]] || die "unsafe acceptance marker in $state"
    backup_dir=$(<"$state/accepted")
    [[ -n $backup_dir ]] && dir_safe "$backup_dir" && verify_snapshot_dir "$backup_dir" \
      || die "recorded backup '$backup_dir' is missing or invalid; check $state and $backup_root manually"
    id=$(<"$backup_dir/id")
  else
    verify_snapshot_dir "$state" \
      || die "the snapshot in $state is missing, incomplete or corrupted; refusing to accept"
    id=$(<"$state/id")
    verify_current_install "$id"

    if [[ -e $backup_root || -L $backup_root ]]; then
      dir_safe "$backup_root" || die "backup root $backup_root is not a private directory; refusing to accept"
    else
      mkdir -p "${backup_root%/*}" && mkdir -m 700 -- "$backup_root" \
        || die "could not create backup root $backup_root"
      dir_safe "$backup_root" || die "backup root $backup_root is not a private directory; refusing to accept"
    fi

    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    backup_dir=$(umask 077 && mktemp -d "$backup_root/${id}-${stamp}.XXXXXX") \
      || die "could not create backup directory under $backup_root"
    dir_safe "$backup_dir" || { rm -rf -- "$backup_dir"; die "backup directory $backup_dir is not private"; }

    if ! { cp -a "$state/plugin" "$backup_dir/plugin" &&
           cp -p "$state/plugin.sha256" "$backup_dir/plugin.sha256" &&
           cp -p "$state/shell.json" "$backup_dir/shell.json" &&
           cp -p "$state/shell.json.sha256" "$backup_dir/shell.json.sha256" &&
           cp -p "$state/id" "$backup_dir/id" &&
           { [[ ! -f $state/branch-test.sh || -L $state/branch-test.sh ]] || cp -p "$state/branch-test.sh" "$backup_dir/branch-test.sh"; } &&
           cmp -s "$state/shell.json" "$backup_dir/shell.json" &&
           : >"$backup_dir/complete" &&
           verify_snapshot_dir "$backup_dir"; }; then
      rm -rf -- "$backup_dir"
      die "could not preserve verified backup of original snapshot; session remains armed"
    fi

    # Commit terminal acceptance state before stopping timers or boot recovery.
    # Any dispatched --restore seeing this marker refuses to revert the accepted bar.
    if ! { printf '%s\n' "$backup_dir" >"$state/accepted.tmp" && mv -- "$state/accepted.tmp" "$state/accepted"; }; then
      rm -f -- "$state/accepted.tmp"
      die "could not commit acceptance state; backup preserved in $backup_dir and session remains armed"
    fi
  fi

  local cleanup_failed=0
  if ! stop_restore_timer_strict; then
    say "could not stop restore timer ($unit.timer); acceptance is committed and backup is in $backup_dir" >&2
    cleanup_failed=1
  fi
  if ! remove_boot_unit_strict; then
    say "could not remove login restore ($boot_unit); acceptance is committed and backup is in $backup_dir" >&2
    cleanup_failed=1
  fi
  if (( cleanup_failed )); then
    die "recovery cleanup did not complete; re-run --accept to finish cleanup (accepted bar is protected from restore)"
  fi

  # Atomically retire $state so terminal acceptance markers remain intact until
  # the active state path is cleanly removed in one rename.
  local retire_rc=0
  retire_state_dir || retire_rc=$?
  if (( retire_rc == 1 )); then
    die "recovery cleanup completed but could not retire $state; re-run --accept to retry (backup is preserved in $backup_dir)"
  elif (( retire_rc != 0 )); then
    die "accepted $id and retired $state, but final cleanup of retired directory failed (backup is preserved in $backup_dir)"
  fi
  say "accepted current $id installation and shell.json (unchanged, no shell restart)"
  say "previous snapshot preserved in $backup_dir"
}

# Files are back and verified; only the restart is retried, a bounded number of times.
cmd_restart() {
  local attempt=${1:-1}
  local expected_session=${2:-}
  [[ $attempt =~ ^[0-9]+$ ]] || attempt=$retry_limit
  local lock_mode=nowait lock_rc=0
  if [[ -n $expected_session ]]; then
    [[ $expected_session =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid session id '$expected_session'"
    lock_mode=wait
  fi
  acquire_lock "$lock_mode" || lock_rc=$?
  if (( lock_rc == 2 )); then
    say "session $expected_session is no longer active; nothing to restart"
    return 0
  fi
  if ! session_matches "$expected_session"; then
    say "ignoring stale restart trigger for session $expected_session"
    exec 8>&-
    return 0
  fi
  if [[ -e $state/accepted ]]; then
    exec 8>&-
    if [[ -n $expected_session ]]; then
      say "session $expected_session was already accepted; not restarting"
      return 0
    fi
    die "session in $state was accepted; refusing to restart"
  fi
  [[ -e $state/restoring ]] || die "no restore in progress in $state"
  local active_session=""
  if [[ -f $state/session && ! -L $state/session ]]; then
    active_session=$(<"$state/session")
  fi
  if ! session_up || restart_shell; then
    say "shell restarted"
    retire_state_dir || die "shell restarted, but could not retire $state"
  elif (( attempt < retry_limit )); then
    if [[ -n $active_session ]]; then
      arm_timer "$retry_minutes" --restart $((attempt + 1)) --session "$active_session"
    else
      arm_timer "$retry_minutes" --restart $((attempt + 1))
    fi
    exec 8>&-
  else
    say "gave up restarting the shell; files are restored, run: omarchy restart shell"
    exec 8>&-
  fi
}

cmd_status() {
  if [[ -e $state/accepted ]]; then
    say "accepted (cleanup pending): backup in $(cat "$state/accepted" 2>/dev/null); run --accept to finish cleanup"
  elif [[ -e $state/restoring ]]; then
    say "restoring: $(cat "$state/id" 2>/dev/null), snapshot in $state"
  elif [[ -e $state/complete ]]; then
    local sid=""
    [[ -f $state/session && ! -L $state/session ]] && sid=" (session $(<"$state/session"))"
    say "armed: $(cat "$state/id" 2>/dev/null)${sid}, snapshot in $state"
  elif [[ -e $state ]]; then
    say "incomplete snapshot in $state"
  else
    say "not armed"
  fi
  [[ -e $boot_unit_file ]] && say "login restore installed ($boot_unit_file)"
  run_systemctl --user list-timers "$unit.timer" --no-pager 2>/dev/null | sed -n 2p
}

case ${1:-} in
  --arm) cmd_arm "${2:-}" ;;
  --restore)
    if (( $# == 1 )); then
      cmd_restore ""
    elif (( $# == 3 )) && [[ $2 == --session && -n $3 ]]; then
      cmd_restore "$3"
    else
      die "usage: branch-test.sh --restore [--session ID]"
    fi
    ;;
  --accept)
    (( $# == 1 )) || die "usage: branch-test.sh --accept"
    cmd_accept
    ;;
  --restart)
    if (( $# <= 2 )); then
      cmd_restart "${2:-1}" ""
    elif (( $# == 4 )) && [[ $3 == --session && -n $4 ]]; then
      cmd_restart "${2:-1}" "$4"
    else
      die "usage: branch-test.sh --restart ATTEMPT [--session ID]"
    fi
    ;;
  --status) cmd_status ;;
  *) die "usage: branch-test.sh --arm MINUTES | --restore | --accept | --status" ;;
esac
