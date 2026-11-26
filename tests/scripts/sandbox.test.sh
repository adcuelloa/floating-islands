#!/usr/bin/env bash
# Exercises install, settings persistence through the real `omarchy bar` CLI,
# and every rollback path, inside a throwaway HOME under /tmp. Nothing here
# can reach the live desktop: omarchy-shell and hyprctl are stubs, the
# Hyprland/Wayland environment is cleared, and `--restart` is never run.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OMARCHY=${OMARCHY_PATH:-/usr/share/omarchy}
plugin_id=$(jq -r .id "$repo/plugin/manifest.json")

sandbox=$(mktemp -d /tmp/islands-sandbox.XXXXXX)
trap 'rm -rf "$sandbox"' EXIT

passed=0
failed=0
check() {
  local name=$1
  shift
  if "$@"; then
    passed=$((passed + 1))
    echo "ok   $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name"
  fi
}

# ------------------------------------------------------------- stubs
stubs="$sandbox/stubs"
mkdir -p "$stubs"
cat >"$stubs/omarchy-shell" <<'EOF'
#!/usr/bin/env bash
# Stand-in for the running shell. $SHELL_STATE: "up" answers, "down" fails.
args="$*"
args=${args#-q }
echo "$args" >>"$SANDBOX_CALLS"
[[ $(cat "$SHELL_STATE_FILE" 2>/dev/null) == up ]] || exit 1
case $args in
  "shell ping") echo pong ;;
  "shell reloadConfig") echo ok ;;
  "shell debugBarGeometry")
    [[ $(cat "$PING_STATE_FILE" 2>/dev/null || echo ok) == ok ]] && echo '[{"screen":"eDP-1","tier":"full","exclusiveZone":50}]' || echo '[]'
    ;;
  *" ping")
    [[ $(cat "$PING_STATE_FILE" 2>/dev/null || echo ok) == ok ]] && echo ok || exit 1
    ;;
  *) : ;;
esac
EOF
printf '#!/usr/bin/env bash\necho "hyprctl $*" >>"$SANDBOX_CALLS"\n' >"$stubs/hyprctl"
# Timers are recorded, never created.
printf '#!/usr/bin/env bash\necho "systemd-run $*" >>"$SANDBOX_CALLS"\n' >"$stubs/systemd-run"
cat >"$stubs/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$SANDBOX_CALLS"
fail_file="${SANDBOX_CALLS%/*}/systemctl-fail"
if [[ -f $fail_file ]]; then
  pat=$(<"$fail_file")
  if [[ -n $pat && "$*" == *"$pat"* ]]; then
    echo "simulated systemctl failure: $*" >&2
    exit 1
  fi
fi
EOF
chmod +x "$stubs"/*

# An Omarchy tree whose omarchy-shell is the stub, so even a script that puts
# $OMARCHY_PATH/bin first on PATH cannot reach the live shell. The shell
# directory is copied (the plugin catalog does not follow a symlinked root).
overlay="$sandbox/omarchy"
mkdir -p "$overlay/bin"
for f in "$OMARCHY"/bin/*; do ln -s "$f" "$overlay/bin/${f##*/}"; done
rm "$overlay/bin/omarchy-shell" "$overlay/bin/omarchy-restart-shell"
cp "$stubs/omarchy-shell" "$overlay/bin/omarchy-shell"
# Fails while restart-fails exists beside the call log (a locked screen).
printf '#!/usr/bin/env bash\necho "restart-shell $*" >>"$SANDBOX_CALLS"\n[[ ! -e ${SANDBOX_CALLS%%/*}/restart-fails ]]\n' >"$overlay/bin/omarchy-restart-shell"
chmod +x "$overlay/bin/omarchy-restart-shell"
cp -R "$OMARCHY/shell" "$overlay/shell"
for d in "$OMARCHY"/*; do [[ -e $overlay/${d##*/} ]] || ln -s "$d" "$overlay/${d##*/}"; done
OMARCHY=$overlay

home="$sandbox/home"
config="$home/.config/omarchy/shell.json"

in_sandbox() {
  env -i \
    HOME="$home" \
    PATH="$stubs:$OMARCHY/bin:/usr/local/bin:/usr/bin:/bin" \
    OMARCHY_PATH="$OMARCHY" \
    SANDBOX_CALLS="$sandbox/calls.log" \
    SHELL_STATE_FILE="$sandbox/shell-state" \
    PING_STATE_FILE="$sandbox/ping-state" \
    TERM=dumb \
    "$@"
}

# A TTY login: no session variables at all, not even OMARCHY_PATH.
in_tty() {
  env -i HOME="$home" PATH="$stubs:/usr/local/bin:/usr/bin:/bin" \
    SANDBOX_CALLS="$sandbox/calls.log" SHELL_STATE_FILE="$sandbox/shell-state" "$@"
}

shell_state() { echo "$1" >"$sandbox/shell-state"; }
fails() { ! "$@" >/dev/null 2>&1; }

# A synthetic configuration shaped like a real one: a custom layout, this
# bar's settings, unrelated plugins and idle settings that must survive.
seed_config() {
  mkdir -p "$(dirname "$config")"
  cat >"$config" <<'EOF'
{
  "version": 1,
  "bar": {
    "background": "opaque",
    "position": "top",
    "islands": { "density": "comfortable", "hosted": ["omarchy.network", "user.audio"] },
    "layout": {
      "left": [{ "id": "omarchy.menu" }, { "id": "omarchy.workspaces" }],
      "centerBegin": [],
      "center": [{ "id": "omarchy.clock", "format": "HH:mm" }],
      "centerEnd": [],
      "right": [{ "id": "omarchy.network" }, { "id": "user.audio", "step": 5 }, { "id": "omarchy.power" }],
      "tray": []
    }
  },
  "plugins": [{ "id": "user.lock" }],
  "disabledPlugins": ["omarchy.lock"],
  "idle": { "lock": 300, "screensaver": 150 }
}
EOF
  cp "$config" "$sandbox/seed.json"
}

# Everything except bar.id, the trial marker, and keys NORMALIZE adds.
unrelated() {
  jq -S 'del(.bar.id) | del(.bar.islands.trialInstance) | del(.bar.layout.centerBegin, .bar.layout.centerEnd)
    | .plugins = (.plugins // [])' "$1"
}
same_unrelated() { diff <(unrelated "$sandbox/seed.json") <(unrelated "$config") >/dev/null; }
selected() { jq -r '.bar.id // ""' "$config"; }

shell_state down
seed_config

# Canary: inside the sandbox, every route to omarchy-shell must be the stub.
stub_resolves() {
  [[ $(in_sandbox bash -c 'command -v omarchy-shell') == "$stubs/omarchy-shell" ]] &&
  [[ $(in_tty bash -c 'export PATH="$PATH:/usr/share/omarchy/bin"; command -v omarchy-shell') == "$stubs/omarchy-shell" ]] &&
  cmp -s "$OMARCHY/bin/omarchy-shell" "$stubs/omarchy-shell"
}
if ! stub_resolves; then
  echo "FAIL the omarchy-shell stub does not shadow the real one; refusing to run"
  exit 1
fi

# ------------------------------------------------------------- install
check "install validates and copies the plugin" \
  in_sandbox "$repo/scripts/install.sh"
check "installed copy has the manifest id" \
  test "$(jq -r .id "$home/.config/omarchy/plugins/$plugin_id/manifest.json")" = "$plugin_id"
check "installing leaves shell.json untouched" \
  cmp -s "$config" "$sandbox/seed.json"
check "reinstall is idempotent" \
  in_sandbox "$repo/scripts/install.sh"
lists_bar_option() {
  in_sandbox omarchy-plugin-catalog | jq -e --arg id "$plugin_id" 'any(.[]; .id == $id and (.kinds | index("bar")) and .barPath != null)' >/dev/null
}
check "the catalog lists it as a bar option" lists_bar_option
installed_manifest="$home/.config/omarchy/plugins/$plugin_id/manifest.json"
cp "$installed_manifest" "$sandbox/manifest.keep"
jq '.id = "something.else"' "$sandbox/manifest.keep" >"$installed_manifest"
check "install refuses a directory that holds another plugin" fails in_sandbox "$repo/scripts/install.sh"
cp "$sandbox/manifest.keep" "$installed_manifest"

# ------------------------------------------------------ settings persistence
check "omarchy bar use selects it" \
  in_sandbox omarchy bar use "$plugin_id"
check "  bar.id is set" test "$(selected)" = "$plugin_id"
check "  this bar's settings survive bar use" same_unrelated
check "omarchy bar position bottom" \
  in_sandbox omarchy bar position bottom
check "  bar.islands survives a position change" \
  test "$(jq -c .bar.islands "$config")" = '{"density":"comfortable","hosted":["omarchy.network","user.audio"]}'
in_sandbox omarchy bar position top >/dev/null
# `omarchy bar move` and `omarchy bar set` go through the running shell
# (moveBarWidget), which rewrites shell.json from a deep copy of the whole
# config; tests/contract checks that code path instead.
check "omarchy bar reset deselects it" \
  in_sandbox omarchy bar reset
check "  stock bar selected, everything else intact" \
  bash -c "[[ -z \$(jq -r '.bar.id // \"\"' '$config') ]]"
check "  unrelated configuration unchanged" same_unrelated

# ------------------------------------------------------------- rollback
select_bar() { in_sandbox omarchy bar use "$plugin_id" >/dev/null; }
add_trial() {
  local tmp
  tmp=$(mktemp)
  jq '.bar.islands.trialInstance = "abc_123"' "$config" >"$tmp" && mv "$tmp" "$config"
}

# 1. An invalid QML import in the installed copy. The shell would fall back on
# its own; the config still names the bar, and lint must have caught it first.
broken="$sandbox/broken-plugin"
cp -R "$repo/plugin" "$broken"
sed -i '0,/^import QtQuick$/s//import QtQuick\nimport Not.A.Real.Module/' "$broken/Bar.qml"
check "the import gate rejects an invalid import before activation" fails "$repo/tests/imports.sh" "$broken"
check "  ...and accepts the real plugin" "$repo/tests/imports.sh"
cp "$broken/Bar.qml" "$home/.config/omarchy/plugins/$plugin_id/Bar.qml"
select_bar; add_trial
shell_state down
check "invalid import: rollback from a TTY (no session env, shell down)" \
  in_tty "$repo/scripts/rollback.sh"
check "  stock bar selected" test -z "$(selected)"
check "  trial marker removed" fails jq -e '.bar.islands.trialInstance' "$config"
check "  settings object kept (it had other keys)" jq -e '.bar.islands.density == "comfortable"' "$config"
check "  unrelated configuration unchanged" same_unrelated
has_backup() { compgen -G "$home/.config/omarchy/shell.json.rollback-*" >/dev/null; }
check "  a timestamped backup was kept" has_backup
in_sandbox "$repo/scripts/install.sh" >/dev/null

# 2. Loaded but invisible: the shell is up and must be told to reload.
select_bar
shell_state up
: >"$sandbox/calls.log"
check "invisible bar: rollback with the shell running" \
  in_sandbox "$repo/scripts/rollback.sh"
check "  stock bar selected" test -z "$(selected)"
check "  a controlled shell restart was requested (stub)" grep -q '^restart-shell' "$sandbox/calls.log"

select_bar
: >"$sandbox/calls.log"
check "--no-restart deselects without restarting" in_sandbox "$repo/scripts/rollback.sh" --no-restart
check "  the running shell was asked to reload" grep -qx 'shell reloadConfig' "$sandbox/calls.log"
check "  no restart was requested" fails grep -q 'restart-shell' "$sandbox/calls.log"
check "  unrelated configuration unchanged" same_unrelated

# 3. The shell died and no omarchy CLI exists at all: jq path only. Omarchy
# installs its commands into /usr/bin too, so this PATH holds nothing but the
# tools rollback.sh needs, and OMARCHY_PATH points nowhere.
minbin="$sandbox/minbin"
mkdir -p "$minbin"
for tool in bash env jq cp mv rm mktemp date cat sed grep dirname install timeout id; do
  real=$(command -v "$tool") || { echo "FAIL missing tool $tool"; exit 1; }
  ln -s "$real" "$minbin/$tool"
done
cp "$stubs/omarchy-shell" "$minbin/omarchy-shell"
# The same canary as above, for this environment.
minbin_isolated() {
  [[ $(env -i HOME="$home" PATH="$minbin" "$minbin/bash" -c 'command -v omarchy-shell; command -v omarchy || true') == "$minbin/omarchy-shell" ]] &&
  cmp -s "$minbin/omarchy-shell" "$stubs/omarchy-shell" &&
  [[ ! -e $sandbox/no-omarchy ]]
}
if ! minbin_isolated; then
  echo "FAIL the minimal PATH can reach a real omarchy command; refusing to run"
  exit 1
fi
no_cli_rollback() {
  env -i HOME="$home" PATH="$minbin" OMARCHY_PATH="$sandbox/no-omarchy" \
    SANDBOX_CALLS="$sandbox/calls.log" SHELL_STATE_FILE="$sandbox/shell-state" \
    "$minbin/bash" "$repo/scripts/rollback.sh" >"$sandbox/no-cli.out" 2>&1
}
select_bar
shell_state down
check "shell terminated, omarchy CLI unavailable: direct jq rollback" no_cli_rollback
check "  it took the jq path" grep -q 'by editing' "$sandbox/no-cli.out"
check "  stock bar selected" test -z "$(selected)"
check "  unrelated configuration unchanged" same_unrelated

# Guards and the other modes.
select_bar
cp "$config" "$sandbox/snapshot.json"
check "dry run changes nothing" in_sandbox "$repo/scripts/rollback.sh" --dry-run
check "  still selected after dry run" test "$(selected)" = "$plugin_id"
in_sandbox "$repo/scripts/rollback.sh" >/dev/null
check "restore puts a snapshot back exactly" \
  in_sandbox "$repo/scripts/rollback.sh" --restore "$sandbox/snapshot.json"
check "  snapshot content restored" cmp -s "$config" "$sandbox/snapshot.json"
echo '{"not":"a shell.json"}' >"$sandbox/garbage.json"
check "restore refuses a file that is not a shell.json" fails in_sandbox "$repo/scripts/rollback.sh" --restore "$sandbox/garbage.json"
tmp=$(mktemp); jq '.bar.id = "someone.else"' "$config" >"$tmp" && mv "$tmp" "$config"
check "rollback leaves another third-party bar alone" fails in_sandbox "$repo/scripts/rollback.sh"
check "  that bar is still selected" test "$(selected)" = "someone.else"
check "  ...unless --any-bar" in_sandbox "$repo/scripts/rollback.sh" --any-bar
check "  stock bar selected" test -z "$(selected)"
printf '{ broken' >"$config"
check "an unreadable shell.json is reported" fails in_sandbox "$repo/scripts/rollback.sh"
check "  ...and not overwritten" grep -q '{ broken' "$config"
cp "$sandbox/snapshot.json" "$config"
check "uninstall deselects first, then removes the plugin" \
  in_sandbox "$repo/scripts/uninstall.sh"
check "  stock bar selected" test -z "$(selected)"
check "  plugin directory removed" test ! -e "$home/.config/omarchy/plugins/$plugin_id"
# --watchdog is whole minutes, 1-1440; anything else stops before any change.
before=$(sha256sum "$config")
for bad in 0 15m 1441 -5; do
  check "activate.sh rejects --watchdog $bad" fails in_sandbox "$repo/scripts/activate.sh" --confirm --watchdog "$bad"
done
check "  shell.json untouched by rejected arguments" test "$(sha256sum "$config")" = "$before"

# ------------------------------------------------------- branch-test.sh
# A supervised test over the persistent bar: snapshot, a wall-clock restore
# and a login restore, and the restore putting back exactly what was there.
bt="$sandbox/branch-test"
branch() { in_sandbox env ISLANDS_BRANCH_TEST_DIR="$bt" "$repo/scripts/branch-test.sh" "$@" >/dev/null 2>&1; }
installed="$home/.config/omarchy/plugins/$plugin_id"
boot_unit="$home/.config/systemd/user/islands-branch-restore-boot.service"
ncalls() { wc -l <"$sandbox/calls.log"; }
since() { tail -n +"$(( $1 + 1 ))" "$sandbox/calls.log"; }
# A desktop session is running unless hypr-up is removed (pgrep stub).
printf '#!/usr/bin/env bash\n[[ -e ${SANDBOX_CALLS%%/*}/hypr-up ]]\n' >"$stubs/pgrep"
chmod +x "$stubs/pgrep"
touch "$sandbox/hypr-up"

check "branch-test refuses to arm without a selected plugin bar" fails branch --arm 45
check "  ...and writes nothing" test ! -e "$bt" -a ! -e "$boot_unit"
in_sandbox "$repo/scripts/install.sh" >/dev/null
jq --arg id "$plugin_id" '.bar.id = $id' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
pretest=$(sha256sum "$config" | cut -d' ' -f1)
for bad in 0 241 45m ""; do
  check "branch-test rejects --arm '$bad'" fails branch --arm "$bad"
done
check "  ...and writes nothing" test ! -e "$bt" -a ! -e "$boot_unit"

mark=$(ncalls)
check "branch-test arms over the persistent bar" branch --arm 45
check "  the snapshot is private (700)" test "$(stat -c %a "$bt")" = 700
check "  it holds the plugin, shell.json, checksums and its own copy" \
  bash -c "diff -r '$installed' '$bt/plugin' && cmp '$config' '$bt/shell.json' && test -s '$bt/plugin.sha256' -a -s '$bt/branch-test.sh' -a -e '$bt/complete'"
check "  the deadline is wall clock (OnCalendar), not monotonic" \
  bash -c "since() { tail -n +$((mark + 1)) '$sandbox/calls.log'; }; since | grep -Eq -- '^systemd-run .*--on-calendar=[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} .*$bt/branch-test.sh --restore\$' && ! grep -q -- '--on-active' '$sandbox/calls.log'"
check "  a login restore covers a reboot" \
  bash -c "grep -q 'ConditionPathExists=$bt/complete' '$boot_unit' && grep -q 'ExecStart=/bin/bash $bt/branch-test.sh --restore' '$boot_unit' && grep -q 'Before=graphical-session-pre.target' '$boot_unit' && tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q 'systemctl --user enable --quiet islands-branch-restore-boot.service'"
check "  arming twice is refused" fails branch --arm 45

# The test build and a test setting, as a supervised check would leave them.
echo test >"$installed/TEST-BUILD"
jq '.bar.islands.extraHosted = ["omarchy.weather"]' "$config" >"$config.tmp" && mv "$config.tmp" "$config"

# The state directory is trusted only while it is private.
chmod 755 "$bt"
check "branch-test refuses a state directory others can read" fails branch --restore
check "  ...and changes nothing" test -e "$installed/TEST-BUILD"
chmod 700 "$bt"
# A restore already running holds the lock.
check "a second restore waits out a running one" \
  bash -c "exec 8>'$bt/lock'; flock 8; ! env -i HOME='$home' PATH='$stubs:$OMARCHY/bin:/usr/bin:/bin' OMARCHY_PATH='$OMARCHY' SANDBOX_CALLS='$sandbox/calls.log' ISLANDS_BRANCH_TEST_DIR='$bt' '$repo/scripts/branch-test.sh' --restore >/dev/null 2>&1"

mark=$(ncalls)
check "branch-test --restore succeeds" branch --restore
check "  the plugin is the snapshot again" diff -r "$repo/plugin" "$installed"
check "  shell.json matches the pretest checksum" test "$(sha256sum "$config" | cut -d' ' -f1)" = "$pretest"
check "  the persistent selection is kept" test "$(selected)" = "$plugin_id"
check "  the timer is stopped, the login restore removed, the shell restarted" \
  bash -c "calls=\$(tail -n +$((mark + 1)) '$sandbox/calls.log'); grep -q 'systemctl --user stop islands-branch-restore.timer' <<<\"\$calls\" && grep -q 'systemctl --user disable --quiet islands-branch-restore-boot.service' <<<\"\$calls\" && grep -q '^restart-shell' <<<\"\$calls\" && test ! -e '$boot_unit'"
check "  the snapshot is removed" test ! -e "$bt"
check "  no temporary copies are left" bash -c "! ls -A '$home/.config/omarchy/plugins' '$home/.config/omarchy' | grep -q -e '\.next' -e '\.old' -e 'branch-test'"
check "  --restore with nothing armed fails" fails branch --restore

# A snapshot that does not verify is kept, and nothing is cleaned up.
branch --arm 30
echo tampered >>"$bt/plugin/manifest.json"
check "a restore that does not verify fails" fails branch --restore
check "  ...and keeps the snapshot and the login restore" test -e "$bt/complete" -a -e "$boot_unit"
rm -rf "$bt" "$boot_unit"
in_sandbox "$repo/scripts/install.sh" >/dev/null

# An interrupted --arm leaves no complete marker: neither arm nor restore trusts it.
branch --arm 30
rm "$bt/complete"
check "an incomplete snapshot is refused by --restore" fails branch --restore
check "  ...and by --arm" fails branch --arm 30
rm -rf "$bt" "$boot_unit"

# A symlink in place of the state directory is never followed.
mkdir -p "$sandbox/elsewhere" && ln -s "$sandbox/elsewhere" "$bt"
check "branch-test refuses a symlinked state directory" fails branch --arm 30
check "  ...and --restore through it" fails branch --restore
rm "$bt"

# After a reboot the login restore runs before the session: no restart needed.
branch --arm 30
echo test >"$installed/TEST-BUILD"
rm "$sandbox/hypr-up"
mark=$(ncalls)
check "the login restore (no session yet) restores the files" branch --restore
check "  the plugin is the snapshot again" diff -r "$repo/plugin" "$installed"
check "  shell.json matches the pretest checksum" test "$(sha256sum "$config" | cut -d' ' -f1)" = "$pretest"
check "  no restart is attempted and the snapshot is removed" \
  bash -c "! tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q '^restart-shell' && test ! -e '$bt' -a ! -e '$boot_unit'"
touch "$sandbox/hypr-up"

# A locked screen refuses the restart: files come back, only the restart is retried.
branch --arm 30
echo test >"$installed/TEST-BUILD"
touch "$sandbox/restart-fails"
mark=$(ncalls)
check "branch-test restores files even when the restart is refused" branch --restore
check "  the plugin is the snapshot again" diff -r "$repo/plugin" "$installed"
check "  shell.json matches the pretest checksum" test "$(sha256sum "$config" | cut -d' ' -f1)" = "$pretest"
check "  a wall-clock restart retry is armed" \
  bash -c "tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -Eq -- '^systemd-run .*--on-calendar=.*branch-test.sh --restart 1\$'"
rm -f "$sandbox/restart-fails"
check "  the retry restarts the shell and removes the snapshot" \
  bash -c "env -i HOME='$home' PATH='$stubs:$OMARCHY/bin:/usr/bin:/bin' OMARCHY_PATH='$OMARCHY' SANDBOX_CALLS='$sandbox/calls.log' ISLANDS_BRANCH_TEST_DIR='$bt' bash '$bt/branch-test.sh' --restart 1 >/dev/null && test ! -e '$bt'"

# ---------------------------------------------- branch-test.sh --accept
bt_backups="$sandbox/branch-test-backups"
tree_digest() { (cd "$1" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum | sha256sum | cut -d' ' -f1); }

# 1. Successful acceptance retains plugin + shell.json byte-for-byte, cleans up
#    timer + login unit without restarting the shell, and preserves a recoverable backup.
rm -rf "$bt" "$bt_backups" "$boot_unit"
seed_config
in_sandbox "$repo/scripts/install.sh" >/dev/null
jq --arg id "$plugin_id" '.bar.id = $id' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
pre_accept_plugin=$(tree_digest "$installed")
pre_accept_cfg=$(sha256sum "$config" | cut -d' ' -f1)

check "branch-test --accept with nothing armed fails" fails branch --accept
check "branch-test arms for acceptance test" branch --arm 45
# Simulate an accepted development build and updated bar settings.
echo "// accepted build marker" >"$installed/ACCEPTED-BUILD"
jq '.bar.islands.extraHosted = ["omarchy.weather"]' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
accepted_plugin=$(tree_digest "$installed")
accepted_cfg=$(sha256sum "$config" | cut -d' ' -f1)
cp "$bt/branch-test.sh" "$sandbox/dispatched-branch-test.sh"

mark=$(ncalls)
check "branch-test --accept succeeds" branch --accept
check "  accepted plugin is retained byte-for-byte" \
  test "$(tree_digest "$installed")" = "$accepted_plugin"
check "  accepted shell.json is retained byte-for-byte" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$accepted_cfg"
check "  no shell restart was requested on acceptance" \
  fails bash -c "tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q '^restart-shell'"
check "  timer is stopped and login restore is disabled and removed" \
  bash -c "calls=\$(tail -n +$((mark + 1)) '$sandbox/calls.log'); grep -q 'systemctl --user stop islands-branch-restore.timer' <<<\"\$calls\" && grep -q 'systemctl --user disable --quiet islands-branch-restore-boot.service' <<<\"\$calls\" && grep -q 'systemctl --user daemon-reload' <<<\"\$calls\" && test ! -e '$boot_unit'"
check "  armed state directory is cleaned up" test ! -e "$bt"
check "  backup root is private (700)" test "$(stat -c %a "$bt_backups")" = 700
backup_one=$(find "$bt_backups" -mindepth 1 -maxdepth 1 -type d | head -n 1)
check "  preserved backup is private (700) and complete" \
  bash -c "test -n '$backup_one' && test \"\$(stat -c %a '$backup_one')\" = 700 && test -f '$backup_one/complete'"
check "  preserved backup plugin matches original snapshot and checksums" \
  bash -c "test \"\$(cd '$backup_one/plugin' && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum)\" = \"\$(cat '$backup_one/plugin.sha256')\" && test \"\$(cd '$backup_one/plugin' && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum | sha256sum | cut -d' ' -f1)\" = '$pre_accept_plugin'"
check "  preserved backup shell.json matches original snapshot and checksum" \
  bash -c "test \"\$(sha256sum '$backup_one/shell.json' | cut -d' ' -f1)\" = \"\$(cat '$backup_one/shell.json.sha256')\" && test \"\$(sha256sum '$backup_one/shell.json' | cut -d' ' -f1)\" = '$pre_accept_cfg'"

# 2. Repeated acceptance and a previously dispatched restore do not modify the accepted install.
mark=$(ncalls)
check "repeated --accept fails without modifying accepted installation" fails branch --accept
check "  accepted plugin unchanged after repeated --accept" \
  test "$(tree_digest "$installed")" = "$accepted_plugin"
check "  accepted shell.json unchanged after repeated --accept" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$accepted_cfg"
check "  no duplicate backup created on repeated --accept" \
  test "$(find "$bt_backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 1
check "  no shell restart on repeated --accept" \
  fails bash -c "tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q '^restart-shell'"

check "previously dispatched restore cannot undo completed acceptance" \
  fails in_sandbox env ISLANDS_BRANCH_TEST_DIR="$bt" bash "$sandbox/dispatched-branch-test.sh" --restore
check "  accepted plugin unchanged after dispatched restore" \
  test "$(tree_digest "$installed")" = "$accepted_plugin"
check "  accepted shell.json unchanged after dispatched restore" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$accepted_cfg"

# 3. Documented backup recovery restores the original snapshot while keeping the backup intact.
cp -a "$backup_one" "$bt"
chmod 700 "$bt"
check "preserved backup is recoverable via branch-test --restore" branch --restore
check "  original plugin restored byte-for-byte from backup" \
  test "$(tree_digest "$installed")" = "$pre_accept_plugin"
check "  original shell.json restored byte-for-byte from backup" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$pre_accept_cfg"
check "  backup directory itself remains preserved after recovery" \
  test -d "$backup_one" -a -f "$backup_one/complete"

# 4. Backup destination collision does not overwrite existing recovery data.
branch --arm 30
echo "// second accepted build" >"$installed/SECOND-BUILD"
check "second acceptance creates a distinct backup without overwriting the first" branch --accept
check "  two distinct backups now exist" \
  test "$(find "$bt_backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" = 2
check "  first backup remains intact and checksum-valid" \
  bash -c "test \"\$(sha256sum '$backup_one/shell.json' | cut -d' ' -f1)\" = '$pre_accept_cfg' && test -f '$backup_one/complete'"
rm -f "$installed/SECOND-BUILD"

# 5. Missing, incomplete, unsafe or corrupted snapshots are rejected.
branch --arm 30
rm "$bt/complete"
check "--accept rejects an incomplete snapshot" fails branch --accept
check "  ...and keeps the login restore" test -e "$boot_unit"
rm -rf "$bt" "$boot_unit"

branch --arm 30
chmod 755 "$bt"
check "--accept rejects a non-private state directory" fails branch --accept
check "  ...and keeps the snapshot and login restore" test -e "$bt/complete" -a -e "$boot_unit"
chmod 700 "$bt"
rm -rf "$bt" "$boot_unit"

mkdir -p "$sandbox/accept-elsewhere" && ln -s "$sandbox/accept-elsewhere" "$bt"
check "--accept rejects a symlinked state directory" fails branch --accept
rm -f "$bt"

branch --arm 30
echo tampered >>"$bt/plugin/manifest.json"
check "--accept rejects a corrupted snapshot plugin" fails branch --accept
check "  ...and keeps the snapshot and login restore" test -e "$bt/complete" -a -e "$boot_unit"
rm -rf "$bt" "$boot_unit"

branch --arm 30
printf '\n' >>"$bt/shell.json"
check "--accept rejects a corrupted snapshot shell.json" fails branch --accept
check "  ...and keeps the snapshot and login restore" test -e "$bt/complete" -a -e "$boot_unit"
rm -rf "$bt" "$boot_unit"

branch --arm 30
chmod 755 "$bt_backups"
check "--accept rejects a non-private backup root" fails branch --accept
check "  ...and leaves the session armed for recovery" test -e "$bt/complete" -a ! -e "$bt/accepted" -a -e "$boot_unit"
chmod 700 "$bt_backups"
rm -rf "$bt" "$boot_unit"

# 6. Changed selected bar or invalid current configuration/installation is rejected.
branch --arm 30
cp "$config" "$sandbox/cfg.keep"
jq '.bar.id = "someone.else"' "$sandbox/cfg.keep" >"$config"
check "--accept rejects when selected bar changed to another bar" fails branch --accept
check "  ...and leaves the session armed" test -e "$bt/complete" -a ! -e "$bt/accepted" -a -e "$boot_unit"
jq 'del(.bar.id)' "$sandbox/cfg.keep" >"$config"
check "--accept rejects when selected bar reverted to stock" fails branch --accept
printf '{ broken' >"$config"
check "--accept rejects invalid current shell.json" fails branch --accept
cp "$sandbox/cfg.keep" "$config"

cp "$installed/manifest.json" "$sandbox/m.keep"
jq '.id = "wrong.id"' "$sandbox/m.keep" >"$installed/manifest.json"
check "--accept rejects invalid current plugin manifest" fails branch --accept
check "  ...and leaves the session armed" test -e "$bt/complete" -a ! -e "$bt/accepted" -a -e "$boot_unit"
cp "$sandbox/m.keep" "$installed/manifest.json"
rm -rf "$bt" "$boot_unit"

# 7. Concurrent acceptance and restoration, plus restore-in-progress refusal.
branch --arm 30
check "--accept refuses while lock is held by a running restore" \
  bash -c "exec 8>'$bt/lock'; flock 8; ! env -i HOME='$home' PATH='$stubs:$OMARCHY/bin:/usr/bin:/bin' OMARCHY_PATH='$OMARCHY' SANDBOX_CALLS='$sandbox/calls.log' ISLANDS_BRANCH_TEST_DIR='$bt' '$repo/scripts/branch-test.sh' --accept >/dev/null 2>&1"
check "  session stays armed after lock contention" test -e "$bt/complete" -a ! -e "$bt/accepted"

# Locked-screen restore leaves $bt/restoring while waiting for --restart; --accept must refuse.
touch "$sandbox/restart-fails"
branch --restore
check "--accept refuses after restore has already started (restart-retry window)" fails branch --accept
rm -f "$sandbox/restart-fails"
in_sandbox env ISLANDS_BRANCH_TEST_DIR="$bt" bash "$bt/branch-test.sh" --restart 1 >/dev/null 2>&1

# 8. Cleanup failures (timer stop / boot-unit disable) fail conservatively,
#    protect the accepted bar from dispatched restores, and resume cleanly on retry.
branch --arm 30
echo "// cleanup-retry build" >"$installed/CLEANUP-RETRY"
retry_plugin=$(tree_digest "$installed")
retry_cfg=$(sha256sum "$config" | cut -d' ' -f1)
backups_before=$(find "$bt_backups" -mindepth 1 -maxdepth 1 -type d | wc -l)

printf 'stop islands-branch-restore.timer' >"$sandbox/systemctl-fail"
check "--accept fails when timer cleanup fails" fails branch --accept
check "  acceptance marker is committed so dispatched restore cannot revert" test -f "$bt/accepted"
check "  dispatched restore refuses to undo committed acceptance" \
  fails in_sandbox env ISLANDS_BRANCH_TEST_DIR="$bt" bash "$bt/branch-test.sh" --restore
check "  dispatched restart refuses to touch committed acceptance" \
  fails in_sandbox env ISLANDS_BRANCH_TEST_DIR="$bt" bash "$bt/branch-test.sh" --restart 1
check "  accepted plugin still intact after refused restore" \
  test "$(tree_digest "$installed")" = "$retry_plugin"
check "  accepted shell.json still intact after refused restore" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$retry_cfg"
check "  --arm refuses while acceptance cleanup is pending" fails branch --arm 30
check "  --status reports pending acceptance cleanup" \
  bash -c "env -i HOME='$home' PATH='$stubs:$OMARCHY/bin:/usr/bin:/bin' OMARCHY_PATH='$OMARCHY' SANDBOX_CALLS='$sandbox/calls.log' ISLANDS_BRANCH_TEST_DIR='$bt' '$repo/scripts/branch-test.sh' --status | grep -q 'accepted (cleanup pending)'"

# Clear timer-stop failure and re-run --accept: finishes cleanly without duplicating backup.
rm -f "$sandbox/systemctl-fail"
mark=$(ncalls)
check "re-running --accept completes pending timer cleanup cleanly" branch --accept
check "  armed state and boot unit are now removed" test ! -e "$bt" -a ! -e "$boot_unit"
check "  no duplicate backup was created on cleanup resume" \
  test "$(find "$bt_backups" -mindepth 1 -maxdepth 1 -type d | wc -l)" = $((backups_before + 1))
check "  accepted plugin unchanged byte-for-byte" \
  test "$(tree_digest "$installed")" = "$retry_plugin"
check "  accepted shell.json unchanged byte-for-byte" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$retry_cfg"
check "  no shell restart on cleanup resume" \
  fails bash -c "tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q '^restart-shell'"

# Boot-unit disable failure on a fresh armed session also fails conservatively and resumes cleanly.
branch --arm 30
backups_before=$(find "$bt_backups" -mindepth 1 -maxdepth 1 -type d | wc -l)
printf 'disable --quiet islands-branch-restore-boot.service' >"$sandbox/systemctl-fail"
check "--accept fails when login-unit cleanup fails" fails branch --accept
check "  acceptance marker and boot unit stay present without duplicating backup" \
  bash -c "test -f '$bt/accepted' && test -e '$boot_unit' && test \"\$(find '$bt_backups' -mindepth 1 -maxdepth 1 -type d | wc -l)\" = $((backups_before + 1))"
check "  dispatched restore still refuses to revert after login-unit cleanup failure" \
  fails in_sandbox env ISLANDS_BRANCH_TEST_DIR="$bt" bash "$bt/branch-test.sh" --restore
rm -f "$sandbox/systemctl-fail"
check "re-running --accept completes pending login-unit cleanup cleanly" branch --accept
check "  armed state and boot unit are removed with no duplicate backup" \
  bash -c "test ! -e '$bt' && test ! -e '$boot_unit' && test \"\$(find '$bt_backups' -mindepth 1 -maxdepth 1 -type d | wc -l)\" = $((backups_before + 1))"
rm -f "$installed/CLEANUP-RETRY"

# -------------------------------------- identity migration & legacy compat
# Verify canonical id (floating-islands) and legacy id (islands.bar) across
# install, TTY rollback, upgrade, failed upgrade, failed fresh activation,
# unrelated third-party protection, and branch-test transitions.
check "canonical plugin id is floating-islands" test "$plugin_id" = "floating-islands"

# Isolated repo copy for activate.sh tests so pre-flight lint/contract checks
# (already gated by the Arch qa job) do not require qmllint on Ubuntu runners.
act_repo="$sandbox/act-repo"
mkdir -p "$act_repo/tests/contract"
cp -R "$repo/plugin" "$act_repo/plugin"
cp -R "$repo/scripts" "$act_repo/scripts"
printf '#!/usr/bin/env bash\nexit 0\n' >"$act_repo/tests/contract/check-contract.sh"
printf '#!/usr/bin/env bash\nexit 0\n' >"$act_repo/tests/lint.sh"
chmod +x "$act_repo/tests/contract/check-contract.sh" "$act_repo/tests/lint.sh"

in_hypr() {
  in_sandbox env HYPRLAND_INSTANCE_SIGNATURE="test_sig_123" "$@"
}

legacy_id="islands.bar"
legacy_dir="$home/.config/omarchy/plugins/$legacy_id"
seed_legacy() {
  rm -rf "$legacy_dir"
  cp -R "$repo/plugin" "$legacy_dir"
  jq --arg id "$legacy_id" '.id = $id' "$repo/plugin/manifest.json" >"$legacy_dir/manifest.json"
}

# 1. Legacy TTY rollback & minimal-PATH rollback (no --id, no --any-bar).
seed_config
seed_legacy
in_sandbox omarchy bar use "$legacy_id" >/dev/null
add_trial
shell_state down
check "legacy islands.bar: rollback from a TTY deselects without --any-bar" \
  in_tty "$repo/scripts/rollback.sh"
check "  stock bar selected after legacy TTY rollback" test -z "$(selected)"
check "  trial marker removed after legacy TTY rollback" fails jq -e '.bar.islands.trialInstance' "$config"
check "  legacy settings preserved" same_unrelated
check "  legacy installation directory kept untouched" test -d "$legacy_dir"

in_sandbox omarchy bar use "$legacy_id" >/dev/null
check "legacy islands.bar: direct jq rollback without omarchy CLI" no_cli_rollback
check "  stock bar selected after direct jq rollback" test -z "$(selected)"
check "  legacy settings preserved after direct jq rollback" same_unrelated

# 2. Legacy upgrade: islands.bar -> floating-islands.
seed_config
seed_legacy
in_sandbox omarchy bar use "$legacy_id" >/dev/null
rm -rf "$home/.config/omarchy/plugins/$plugin_id"
check "install.sh installs floating-islands alongside legacy islands.bar" \
  in_sandbox "$repo/scripts/install.sh"
check "  legacy islands.bar directory is not deleted by install.sh" test -d "$legacy_dir"
shell_state up
echo ok >"$sandbox/ping-state"
mark=$(ncalls)
check "activate.sh upgrades legacy islands.bar to floating-islands" \
  bash -c "env -i HOME='$home' PATH='$stubs:$OMARCHY/bin:/usr/local/bin:/usr/bin:/bin' OMARCHY_PATH='$OMARCHY' SANDBOX_CALLS='$sandbox/calls.log' SHELL_STATE_FILE='$sandbox/shell-state' PING_STATE_FILE='$sandbox/ping-state' TERM=dumb HYPRLAND_INSTANCE_SIGNATURE='test_sig_123' '$act_repo/scripts/activate.sh' --confirm >'$sandbox/activate-upgrade.out' 2>&1"
check "  floating-islands is now selected" test "$(selected)" = "$plugin_id"
check "  bar.islands settings preserved across upgrade" \
  test "$(jq -c '.bar.islands | del(.trialInstance)' "$config")" = '{"density":"comfortable","hosted":["omarchy.network","user.audio"]}'
check "  trial marker recorded for current Hyprland session" \
  test "$(jq -r '.bar.islands.trialInstance' "$config")" = "test_sig_123"
check "  any leftover legacy watchdog timer is stopped on success" \
  bash -c "tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q 'systemctl --user stop islands-bar-watchdog.timer'"
check "  legacy upgrade emits hosted-widget restart advisory" \
  grep -q 'omarchy restart shell' "$sandbox/activate-upgrade.out"
check "  legacy upgrade does not automatically restart the shell" \
  fails bash -c "tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q '^restart-shell'"
check "  legacy islands.bar directory remains untouched after upgrade" test -d "$legacy_dir"

# 2b. Fresh activation from stock bar vs. same-identity re-activation advisory.
seed_config
shell_state up
echo ok >"$sandbox/ping-state"
mark=$(ncalls)
check "activate.sh activates cleanly from stock bar" \
  bash -c "env -i HOME='$home' PATH='$stubs:$OMARCHY/bin:/usr/local/bin:/usr/bin:/bin' OMARCHY_PATH='$OMARCHY' SANDBOX_CALLS='$sandbox/calls.log' SHELL_STATE_FILE='$sandbox/shell-state' PING_STATE_FILE='$sandbox/ping-state' TERM=dumb HYPRLAND_INSTANCE_SIGNATURE='test_sig_123' '$act_repo/scripts/activate.sh' --confirm >'$sandbox/activate-fresh.out' 2>&1"
check "  fresh activation emits hosted-widget restart advisory" \
  grep -q 'omarchy restart shell' "$sandbox/activate-fresh.out"
check "  fresh activation does not automatically restart the shell" \
  fails bash -c "tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q '^restart-shell'"

mark=$(ncalls)
check "activate.sh re-activates cleanly when floating-islands is already selected" \
  bash -c "env -i HOME='$home' PATH='$stubs:$OMARCHY/bin:/usr/local/bin:/usr/bin:/bin' OMARCHY_PATH='$OMARCHY' SANDBOX_CALLS='$sandbox/calls.log' SHELL_STATE_FILE='$sandbox/shell-state' PING_STATE_FILE='$sandbox/ping-state' TERM=dumb HYPRLAND_INSTANCE_SIGNATURE='test_sig_123' '$act_repo/scripts/activate.sh' --confirm --persistent >'$sandbox/activate-same.out' 2>&1"
check "  same-identity re-activation omits the bar-switch advisory" \
  fails grep -q 'omarchy restart shell' "$sandbox/activate-same.out"
check "  same-identity re-activation does not automatically restart the shell" \
  fails bash -c "tail -n +$((mark + 1)) '$sandbox/calls.log' | grep -q '^restart-shell'"

# 3. Failed legacy upgrade restores previous selection (islands.bar) and settings.
seed_config
seed_legacy
in_sandbox omarchy bar use "$legacy_id" >/dev/null
before_legacy=$(sha256sum "$config" | cut -d' ' -f1)
echo fail >"$sandbox/ping-state"
check "failed legacy upgrade exits non-zero and auto-rolls back" \
  fails in_hypr "$act_repo/scripts/activate.sh" --confirm
check "  previous legacy selection (islands.bar) is restored" test "$(selected)" = "$legacy_id"
check "  shell.json matches pre-upgrade state byte-for-byte" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$before_legacy"
check "  legacy islands.bar directory still intact" test -d "$legacy_dir"

# 4. Failed fresh activation restores stock bar and exact settings.
seed_config
before_fresh=$(sha256sum "$config" | cut -d' ' -f1)
echo fail >"$sandbox/ping-state"
check "failed fresh activation exits non-zero and auto-rolls back" \
  fails in_hypr "$act_repo/scripts/activate.sh" --confirm
check "  stock bar is restored" test -z "$(selected)"
check "  shell.json matches pre-activation state byte-for-byte" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$before_fresh"

# 5. Unrelated third-party bar protection in activate.sh.
seed_config
jq '.bar.id = "someone.else"' "$config" >"$config.tmp" && mv "$config.tmp" "$config"
check "activate.sh refuses an unrelated third-party bar" \
  fails in_hypr "$act_repo/scripts/activate.sh" --check
check "  unrelated third-party bar stays selected" test "$(selected)" = "someone.else"

# 6. branch-test.sh transition from legacy islands.bar to floating-islands and back.
seed_config
seed_legacy
in_sandbox omarchy bar use "$legacy_id" >/dev/null
legacy_pretest=$(sha256sum "$config" | cut -d' ' -f1)
check "branch-test arms over legacy islands.bar" branch --arm 30
in_sandbox "$repo/scripts/install.sh" >/dev/null
in_sandbox omarchy bar use "$plugin_id" >/dev/null
check "  floating-islands selected during branch test" test "$(selected)" = "$plugin_id"
check "branch-test --restore returns to legacy islands.bar" branch --restore
check "  legacy islands.bar selected again" test "$(selected)" = "$legacy_id"
check "  shell.json matches legacy pretest checksum" \
  test "$(sha256sum "$config" | cut -d' ' -f1)" = "$legacy_pretest"
check "  new floating-islands installation is not deleted by restore" \
  test -d "$home/.config/omarchy/plugins/$plugin_id"

check "nothing called hyprctl" fails grep -q '^hyprctl' "$sandbox/calls.log"

echo "sandbox: $passed passed, $failed failed"
(( failed == 0 ))
