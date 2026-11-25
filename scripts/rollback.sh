#!/usr/bin/env bash
# Restore the stock Omarchy bar. Works from a Linux TTY (Ctrl+Alt+F3) with no
# graphical session: it needs only bash, jq and coreutils, edits
# ~/.config/omarchy/shell.json directly when the omarchy CLI is unavailable,
# and never requires the shell to be running.
#
#   rollback.sh                 deselect this bar, then restart omarchy-shell when
#                               it is reachable (a fresh stock bar; see below)
#   rollback.sh --no-restart    deselect only (the shell hot-swaps to the stock bar)
#   rollback.sh --uninstall     ...and remove the installed plugin directory
#   rollback.sh --restore FILE  put a saved shell.json back (e.g. the activation snapshot)
#   rollback.sh --any-bar       deselect whatever third-party bar is selected
#   rollback.sh --dry-run       say what would change, change nothing
#
# Self-contained on purpose: it does not source the rest of the repository,
# so a broken checkout cannot stop it.
set -euo pipefail

PLUGIN_ID_DEFAULT="floating-islands"
LEGACY_PLUGIN_IDS=("islands.bar")
SETTINGS_KEY="islands"

restart=1 uninstall=0 any_bar=0 dry_run=0 restore=""
plugin_id="" explicit_id=0
while (( $# )); do
  case $1 in
    --restart) restart=1 ;;
    --no-restart) restart=0 ;;
    --uninstall) uninstall=1 ;;
    --any-bar) any_bar=1 ;;
    --dry-run) dry_run=1 ;;
    --restore) restore=${2:?--restore needs a file}; shift ;;
    --id) plugin_id=${2:?--id needs a plugin id}; explicit_id=1; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "rollback: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf 'rollback: %s\n' "$*"; }
die() { printf 'rollback: %s\n' "$*" >&2; exit 1; }

command -v jq >/dev/null || die "jq is required"
[[ -n ${HOME:-} && -d $HOME ]] || die "HOME is not set"

# A TTY login may lack the session environment.
export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
# Appended, not prepended: commands already on PATH keep precedence.
[[ -d $OMARCHY_PATH/bin ]] && export PATH="$PATH:$OMARCHY_PATH/bin"
export OMARCHY_SHELL_IPC_TIMEOUT=${OMARCHY_SHELL_IPC_TIMEOUT:-1s}

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -z $plugin_id ]]; then
  plugin_id=$(jq -r '.id // empty' "$here/../plugin/manifest.json" 2>/dev/null || true)
  plugin_id=${plugin_id:-$PLUGIN_ID_DEFAULT}
fi
[[ $plugin_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $plugin_id != *..* && $plugin_id != omarchy.* ]] \
  || die "refusing unsafe plugin id '$plugin_id'"

config="$HOME/.config/omarchy/shell.json"
plugin_dir="$HOME/.config/omarchy/plugins/$plugin_id"
stamp=$(date +%Y%m%d-%H%M%S)

run() {
  if (( dry_run )); then say "would run: $*"; else "$@"; fi
}

backup_config() {
  [[ -f $config ]] || return 0
  local copy="$config.rollback-$stamp"
  run cp -p -- "$config" "$copy"
  (( dry_run )) || say "saved the current shell.json as $copy"
}

selected_bar() {
  [[ -s $config ]] || { echo ""; return; }
  jq -r '.bar.id // ""' "$config" 2>/dev/null || echo "__unreadable__"
}

shell_running() {
  command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1
}

# Deselect with jq: what `omarchy bar reset` does, minus the CLI. Also drops
# the trial marker so a later activation starts clean. Everything else in
# shell.json is kept byte-for-byte as jq re-emits it.
jq_deselect() {
  local tmp
  tmp=$(mktemp "$config.XXXXXX")
  if jq --arg key "$SETTINGS_KEY" '
      del(.bar.id)
      | if (.bar[$key] | type) == "object" then del(.bar[$key].trialInstance) else . end
      | if .bar[$key] == {} then del(.bar[$key]) else . end
    ' "$config" >"$tmp" && jq -e 'type == "object"' "$tmp" >/dev/null; then
    mv -- "$tmp" "$config"
  else
    rm -f -- "$tmp"
    die "could not rewrite $config; it is unchanged"
  fi
}

is_known_bar() {
  local id=$1 legacy
  [[ $id == "$plugin_id" ]] && return 0
  if (( ! explicit_id )); then
    for legacy in "${LEGACY_PLUGIN_IDS[@]}"; do
      [[ $id == "$legacy" ]] && return 0
    done
  fi
  return 1
}

deselect() {
  local current
  current=$(selected_bar)
  if [[ $current == "__unreadable__" ]]; then
    die "$config is not valid JSON; restore a backup with --restore FILE"
  fi
  if [[ -z $current || $current == omarchy.bar ]]; then
    say "the stock bar is already selected"
    return 0
  fi
  if ! is_known_bar "$current" && (( ! any_bar )); then
    die "another bar is selected ($current); pass --any-bar to deselect it"
  fi

  backup_config
  if (( dry_run )); then
    say "would deselect $current"
    return 0
  fi

  # The supported mechanism first; it also asks a running shell to reload.
  if command -v omarchy >/dev/null && timeout 15 omarchy bar reset >/dev/null 2>&1 && [[ -z $(selected_bar) ]]; then
    say "deselected $current with 'omarchy bar reset'"
  else
    jq_deselect
    say "deselected $current by editing $config directly"
  fi
  [[ -z $(selected_bar) ]] || die "$config still selects $(selected_bar)"
  # Drop the trial marker `omarchy bar reset` leaves behind.
  if jq -e --arg key "$SETTINGS_KEY" '.bar[$key].trialInstance? // empty' "$config" >/dev/null 2>&1; then
    jq_deselect
  fi
}

restore_snapshot() {
  [[ -f $restore ]] || die "no such file: $restore"
  jq -e 'type == "object" and .version == 1' "$restore" >/dev/null 2>&1 \
    || die "$restore is not an Omarchy shell.json (version 1)"
  backup_config
  run install -D -m 0644 -- "$restore" "$config.restore-tmp"
  run mv -- "$config.restore-tmp" "$config"
  (( dry_run )) || say "restored $config from $restore"
}

if [[ -n $restore ]]; then restore_snapshot; else deselect; fi

if (( uninstall )); then
  if [[ -d $plugin_dir && ! -L $plugin_dir ]]; then
    run rm -rf -- "$plugin_dir"
    (( dry_run )) || say "removed $plugin_dir"
  else
    say "no installed plugin at $plugin_dir"
  fi
fi

# A watchdog armed by activate.sh has nothing left to do.
if (( ! dry_run )) && command -v systemctl >/dev/null; then
  # Only the timer: when the watchdog itself runs this script, stopping its
  # service would end this script too. The transient service ends by itself.
  systemctl --user stop islands-bar-watchdog.timer >/dev/null 2>&1 || true
fi

if (( dry_run )); then
  say "dry run: nothing changed"
elif shell_running; then
  # Omarchy 4.5.0rc2 hot-swaps back to the stock bar but leaves the shell
  # without a reference to it (docs/upstream/), so panel hotkeys and summons
  # fail until a restart. `omarchy restart shell` is Omarchy's own controlled
  # restart: it waits for the old instance, relaunches through Hyprland,
  # re-secures a lock and waits for notifications.
  if (( restart )); then
    if omarchy restart shell >/dev/null 2>&1; then
      say "restarted omarchy-shell; the stock bar is fully back"
    else
      omarchy-shell shell reloadConfig >/dev/null 2>&1 || true
      say "the shell reloaded shell.json, but 'omarchy restart shell' failed; run it when you can"
    fi
  else
    omarchy-shell shell reloadConfig >/dev/null 2>&1 || true
    say "the running shell reloaded shell.json (no restart, as asked); run 'omarchy restart shell'"
    say "to restore panel hotkeys and summons (Omarchy keeps no bar reference after a bar switch)"
  fi
else
  say "could not reach omarchy-shell from here (expected in a TTY). A running shell"
  say "picks up shell.json by itself; otherwise it loads the stock bar when it starts."
  say "Back in the graphical session, run 'omarchy restart shell' to restore panel hotkeys,"
  say "and 'systemctl --user stop islands-bar-watchdog.timer' if a trial watchdog was armed."
fi
