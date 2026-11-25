#!/usr/bin/env bash
# A supervised test of a development build while this bar is the persistent
# daily bar. Arming snapshots the installed plugin and shell.json and sets a
# wall-clock deadline at which they are put back by themselves, so the test
# ends even if the terminal or the session that started it is gone.
#
#   branch-test.sh --arm 45     snapshot, restore by itself in 45 min (1-240)
#   (then scripts/install.sh and `omarchy restart shell` to load the build)
#   branch-test.sh --restore    put the snapshot back now and restart the shell
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
unit=islands-branch-restore
boot_unit=islands-branch-restore-boot.service
boot_unit_file="$HOME/.config/systemd/user/$boot_unit"
retry_minutes=5
retry_limit=24

say() { printf 'branch-test.sh: %s\n' "$*"; }
die() { printf 'branch-test.sh: %s\n' "$*" >&2; exit 1; }

deadline_in() { date -d "+$1 min" '+%Y-%m-%d %H:%M:%S'; }

# The state directory is trusted only if it is ours, private and real.
state_safe() {
  [[ -d $state && ! -L $state && -O $state && $(stat -c %a "$state") == 700 ]]
}

# Every regular file in a plugin tree with its checksum, in a stable order.
tree_sums() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum); }

arm_timer() { # <minutes> <args for the snapshot's copy...>
  local minutes=$1
  shift
  systemctl --user stop "$unit.timer" >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit.service" >/dev/null 2>&1 || true
  systemd-run --user --quiet --unit="$unit" --on-calendar="$(deadline_in "$minutes")" \
    --timer-property=AccuracySec=5s --setenv=OMARCHY_PATH="$OMARCHY_PATH" \
    --setenv=ISLANDS_BRANCH_TEST_DIR="$state" /bin/bash "$state/branch-test.sh" "$@"
}

write_boot_unit() {
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
ExecStart=/bin/bash $state/branch-test.sh --restore

[Install]
WantedBy=default.target
EOF
  mv -- "$boot_unit_file.tmp" "$boot_unit_file" && systemctl --user enable --quiet "$boot_unit"
}

remove_boot_unit() {
  [[ -e $boot_unit_file ]] || return 0
  systemctl --user disable --quiet "$boot_unit" >/dev/null 2>&1 || true
  rm -f -- "$boot_unit_file"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# Only a running desktop has a shell to restart; at login (the boot unit),
# the shell has not started yet and will read the restored files.
session_up() { pgrep -x -u "$(id -u)" Hyprland >/dev/null 2>&1; }

restart_shell() { "$OMARCHY_PATH/bin/omarchy-restart-shell" >/dev/null 2>&1; }

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
    [[ -e $state/complete ]] && die "already armed ($state); run --restore or --status"
    die "an incomplete snapshot is in $state (an interrupted --arm); check it, remove it, then arm again"
  fi
  mkdir -p "${state%/*}" && mkdir -m 700 -- "$state" || die "could not create $state"
  state_safe || die "$state is not a private directory"

  # complete is written last; a restore refuses a snapshot without it.
  if ! { cp -a "$plugins_dir/$id" "$state/plugin" &&
         tree_sums "$plugins_dir/$id" >"$state/plugin.sha256" &&
         [[ $(tree_sums "$state/plugin") == $(<"$state/plugin.sha256") ]] &&
         cp -p "$config" "$state/shell.json" &&
         cmp -s "$config" "$state/shell.json" &&
         sha256sum "$state/shell.json" | cut -d' ' -f1 >"$state/shell.json.sha256" &&
         printf '%s\n' "$id" >"$state/id" &&
         cp "${BASH_SOURCE[0]}" "$state/branch-test.sh" &&
         : >"$state/complete"; }; then
    rm -rf -- "$state"
    die "could not write the snapshot; nothing was armed"
  fi
  if ! write_boot_unit; then
    remove_boot_unit
    rm -rf -- "$state"
    die "could not install the login restore; nothing was armed"
  fi
  if ! arm_timer "$minutes" --restore; then
    remove_boot_unit
    rm -rf -- "$state"
    die "could not arm the restore timer; nothing was armed"
  fi
  say "snapshot of $id and shell.json in $state"
  say "restores by itself at $(deadline_in "$minutes") (wall clock), or at the next login after a reboot"
}

cmd_restore() {
  [[ -e $state || -L $state ]] || die "nothing armed ($state)"
  state_safe || die "$state is not a private directory; not trusting it (scripts/rollback.sh is the fallback)"
  [[ -e $state/complete && -s $state/shell.json && -d $state/plugin && -s $state/id ]] \
    || die "the snapshot in $state is incomplete; run scripts/rollback.sh"
  exec 8>"$state/lock"
  flock -n 8 || die "another restore is running"
  local id
  id=$(<"$state/id")
  [[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $id != *..* ]] || die "the snapshot names no usable plugin id"
  jq -e . "$state/shell.json" >/dev/null 2>&1 || die "the snapshot's shell.json is unreadable; run scripts/rollback.sh"

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
  systemctl --user stop "$unit.timer" >/dev/null 2>&1 || true
  remove_boot_unit

  if ! session_up; then
    say "no desktop session; the shell will start from the restored files"
  elif restart_shell; then
    # The bar's own QML is only rebuilt by a restart (a plugin reload does not).
    say "shell restarted"
  else
    say "the shell refused to restart (locked screen?); retrying every $retry_minutes min"
    arm_timer "$retry_minutes" --restart 1 || say "could not arm the retry; run: omarchy restart shell"
    return 0
  fi
  rm -rf -- "$state"
}

# Files are back and verified; only the restart is retried, a bounded number of times.
cmd_restart() {
  local attempt=${1:-1}
  [[ $attempt =~ ^[0-9]+$ ]] || attempt=$retry_limit
  state_safe || die "$state is not a private directory; not trusting it"
  if ! session_up || restart_shell; then
    say "shell restarted"
    rm -rf -- "$state"
  elif (( attempt < retry_limit )); then
    arm_timer "$retry_minutes" --restart $((attempt + 1))
  else
    say "gave up restarting the shell; files are restored, run: omarchy restart shell"
  fi
}

cmd_status() {
  if [[ -e $state/complete ]]; then
    say "armed: $(cat "$state/id" 2>/dev/null), snapshot in $state"
  elif [[ -e $state ]]; then
    say "incomplete snapshot in $state"
  else
    say "not armed"
  fi
  [[ -e $boot_unit_file ]] && say "login restore installed ($boot_unit_file)"
  systemctl --user list-timers "$unit.timer" --no-pager 2>/dev/null | sed -n 2p
}

case ${1:-} in
  --arm) cmd_arm "${2:-}" ;;
  --restore) cmd_restore ;;
  --restart) cmd_restart "${2:-}" ;;
  --status) cmd_status ;;
  *) die "usage: branch-test.sh --arm MINUTES | --restore | --status" ;;
esac
