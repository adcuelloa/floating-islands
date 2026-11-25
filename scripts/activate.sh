#!/usr/bin/env bash
# Select the Floating Islands bar on the running desktop. Never run implicitly.
#
#   activate.sh --confirm               trial: this login only (default)
#   activate.sh --confirm --persistent  keep it selected across logins
#   activate.sh --check                 run the pre-flight checks only
#   activate.sh --confirm --watchdog 20 also roll back by itself after 20 min
#
# --watchdog takes whole minutes (1-1440). It sets a wall-clock deadline, so
# time spent suspended counts: a deadline passed during suspend fires on
# resume. It runs rollback.sh, which also restarts the shell, unless the
# session is locked at that moment (Omarchy refuses to restart under a lock).
#
# A trial records the current Hyprland instance in shell.json; in any later
# session (re-login, reboot, compositor restart) the bar hands back to the
# stock bar by itself. After selecting, the script waits for the bar to
# answer over IPC and report its surfaces; if it does not (a load error made
# the shell fall back, or it loaded but drew nothing), it rolls back.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

confirm=0 persistent=0 check_only=0 auto_rollback=1 watchdog=0
while (( $# )); do
  case $1 in
    --confirm) confirm=1 ;;
    --persistent) persistent=1 ;;
    --check) check_only=1 ;;
    --no-auto-rollback) auto_rollback=0 ;;
    --watchdog) watchdog=${2:?--watchdog needs minutes}; shift
      [[ $watchdog =~ ^[1-9][0-9]{0,3}$ ]] && (( watchdog <= 1440 )) || die "--watchdog takes 1-1440 minutes" ;;
    *) die "unknown option $1" ;;
  esac
  shift
done

rollback="$repo_root/scripts/rollback.sh"

# ------------------------------------------------------------- pre-flight
[[ -x $rollback ]] || die "scripts/rollback.sh is missing or not executable"
[[ -d $install_dir ]] || die "not installed; run scripts/install.sh first"
cmp -s "$plugin_src/manifest.json" "$install_dir/manifest.json" || die "installed copy is out of date; run scripts/install.sh"
omarchy plugin validate "$install_dir" >/dev/null || die "the installed plugin does not validate"
"$repo_root/tests/contract/check-contract.sh" --quiet >/dev/null || die "the compatibility contract fails against this Omarchy; see tests/contract/check-contract.sh"
"$repo_root/tests/lint.sh" >/dev/null || die "qmllint reports new warnings; run tests/lint.sh"
shell_running || die "omarchy-shell is not running"
[[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] || die "not inside a Hyprland session"
current=$(selected_bar)
[[ -z $current || $current == omarchy.bar ]] || is_known_plugin_id "$current" || die "another bar is selected ($current)"
say "pre-flight checks passed"
(( check_only )) && exit 0
(( confirm )) || die "pass --confirm to change the bar on this desktop"

# ------------------------------------------------------------- snapshot
snapshot="$HOME/.config/omarchy/shell.json.pre-$plugin_id"
[[ -e $snapshot ]] && snapshot="$snapshot.$(date +%Y%m%d-%H%M%S)"
cp -p -- "$config" "$snapshot"
say "saved the current shell.json as $snapshot"

cat <<EOF
If the desktop becomes unusable, switch to a TTY (Ctrl+Alt+F3), log in, and run:
  $rollback
or, to put the exact previous configuration back:
  $rollback --restore $snapshot
EOF

armed_watchdog=0
restore_previous() {
  if (( armed_watchdog )) && command -v systemctl >/dev/null; then
    systemctl --user stop islands-bar-watchdog.timer >/dev/null 2>&1 || true
  fi
  if ! "$rollback" --restore "$snapshot"; then
    "$rollback" --id "$plugin_id" >/dev/null 2>&1 || true
  fi
}

# ------------------------------------------------------------- select
# The trial marker is written before the bar is selected, so a failure in
# between can never leave a selection that would outlive this session.
if (( persistent )); then
  trial='del(.bar[$key].trialInstance)'
else
  trial='.bar[$key] = ((.bar[$key] // {}) + {trialInstance: $instance})'
fi
tmp=$(mktemp "$config.XXXXXX")
if ! jq --arg key "$settings_key" --arg instance "$HYPRLAND_INSTANCE_SIGNATURE" "$trial" "$config" >"$tmp"; then
  rm -f -- "$tmp"
  die "could not write the trial marker; nothing was selected"
fi
mv -- "$tmp" "$config"

if (( watchdog )); then
  systemctl --user stop islands-bar-watchdog.timer >/dev/null 2>&1 || true
  # OnCalendar (wall clock), not OnActiveSec: a monotonic timer pauses while
  # the machine is suspended and would roll back late.
  deadline=$(date -d "+$watchdog min" '+%Y-%m-%d %H:%M:%S')
  if ! systemd-run --user --quiet --unit=islands-bar-watchdog --on-calendar="$deadline" \
    --timer-property=AccuracySec=5s "$rollback" --id "$plugin_id"; then
    restore_previous >/dev/null 2>&1 || true
    die "could not arm the watchdog; restored previous configuration"
  fi
  armed_watchdog=1
  say "watchdog armed: the stock bar returns by itself at $deadline (transient; gone after logout)"
fi

if ! omarchy bar use "$plugin_id" >/dev/null; then
  restore_previous >/dev/null 2>&1 || true
  die "omarchy bar use failed; restored previous configuration"
fi
omarchy-shell shell reloadConfig >/dev/null 2>&1 || true

# ------------------------------------------------------------- verify
ok=0
for _ in $(seq 1 20); do
  sleep 0.25
  if [[ $(omarchy-shell "$plugin_id" ping 2>/dev/null || true) == ok ]]; then
    geometry=$(omarchy-shell shell debugBarGeometry 2>/dev/null || echo '[]')
    if jq -e 'type == "array" and length > 0 and all(.[]; .tier != null and .exclusiveZone > 0)' <<<"$geometry" >/dev/null 2>&1; then
      ok=1
      break
    fi
  fi
done

if (( ok )); then
  # Clear any leftover legacy or previous trial watchdog when activating without one.
  if (( ! watchdog )) && command -v systemctl >/dev/null; then
    systemctl --user stop islands-bar-watchdog.timer >/dev/null 2>&1 || true
  fi
  say "active on $(jq -r 'map(.screen + " (" + .tier + ")") | join(", ")' <<<"$geometry")"
  (( persistent )) && say "selected persistently" || say "trial for this session only"
  if [[ $current != "$plugin_id" ]]; then
    say "note: Omarchy hot-reload after switching bars can leave hosted widgets inactive; if status-island widgets do not appear or respond, run: omarchy restart shell"
  fi
  exit 0
fi

say "the bar did not report its surfaces within 5 s"
if (( auto_rollback )); then
  restore_previous
  if [[ -n $current && $current != omarchy.bar ]]; then
    die "restored previous bar ($current)"
  fi
  die "rolled back to the stock bar"
fi
die "left selected (--no-auto-rollback); run $rollback to undo"
