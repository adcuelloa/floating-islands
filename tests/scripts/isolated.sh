#!/usr/bin/env bash
# Runs a test inside bubblewrap so it cannot touch the live desktop even by
# mistake:
#   - the root filesystem is read-only, /tmp is a fresh private tmpfs;
#   - the per-user runtime directory (Hyprland, shell, D-Bus sockets) is an
#     empty tmpfs, and the network namespace is separate, which also cuts
#     abstract unix sockets;
#   - the environment is cleared down to what the tests need;
#   - every installed copy of omarchy-shell, hyprctl, quickshell,
#     omarchy-restart-shell and systemd-run is replaced by a tripwire that reports through a
#     file descriptor opened here, outside anything the sandbox can write.
# Any tripwire call fails the run, even if the test itself passed. A
# self-check proves the tripwire reports before the test is run.
#
# Usage: tests/scripts/isolated.sh <command> [args...]
set -uo pipefail

if ! command -v bwrap >/dev/null; then
  echo "isolated: bubblewrap (bwrap) is required to run sandbox tests safely" >&2
  exit 1
fi

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tripwire="$here/tripwire.sh"
log=$(mktemp /tmp/islands-tripwire.XXXXXX)
trap 'rm -f "$log"' EXIT
exec 9>>"$log"

binds=()
seen=" "
for target in omarchy-shell hyprctl quickshell qs omarchy-restart-shell systemd-run; do
  candidates=$(type -a -P "$target" 2>/dev/null)
  for dir in /usr/bin /usr/local/bin /bin /sbin /usr/sbin "${OMARCHY_PATH:-/usr/share/omarchy}/bin" "$HOME/.local/bin"; do
    candidates+=$'\n'"$dir/$target"
  done
  while IFS= read -r path; do
    [[ -n $path && -e $path ]] || continue
    real=$(readlink -f "$path")
    [[ $seen == *" $real "* ]] && continue
    seen+="$real "
    binds+=(--ro-bind "$tripwire" "$real")
  done <<<"$candidates"
done

sandbox() {
  bwrap --ro-bind / / --dev /dev --proc /proc \
    --tmpfs /tmp --tmpfs "/run/user/$(id -u)" \
    "${binds[@]}" \
    --unshare-ipc --unshare-net --unshare-pid --new-session --die-with-parent \
    --clearenv \
    --setenv HOME "$HOME" --setenv PATH "$PATH" --setenv USER "${USER:-}" \
    --setenv LANG "${LANG:-C.UTF-8}" --setenv TERM dumb \
    "$@" </dev/null
}

# The tripwire must be able to report from inside, or a clean log means nothing.
sandbox /usr/bin/omarchy-shell shell ping >/dev/null 2>&1
if ! grep -q 'omarchy-shell shell ping' "$log"; then
  echo "isolated: the tripwire self-check did not report; refusing to run" >&2
  exit 1
fi
: >"$log"

sandbox "$@"
status=$?

if [[ -s $log ]]; then
  echo "isolated: the test reached live commands (tripwire):"
  sed 's/^/  /' "$log"
  exit 1
fi
echo "isolated: no live command was reached ($(( ${#binds[@]} / 3 )) binaries trapped)"
exit $status
