#!/usr/bin/env bash
# Builds the CI test environment inside a stock Arch container, as root, from
# immutable sources only: an Arch Linux Archive date, a per-package archive URL
# for the Qt build the reference host holds, and the Omarchy repository builds,
# each checked against a recorded sha256. Any missing or mismatched artifact
# stops here; nothing falls back to "latest".
#
# Usage (as root): .github/ci/bootstrap.sh <unprivileged-user> <uid>
set -euo pipefail

user=${1:?usage: bootstrap.sh <unprivileged-user> <uid>}
uid=${2:?usage: bootstrap.sh <unprivileged-user> <uid>}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck source=.github/ci/retry.sh
source "$(dirname "${BASH_SOURCE[0]}")/retry.sh"
# Overall deadline for all network operations inside the 15-minute step timeout.
deadline=$(( $(date +%s) + 720 ))

# --- pins: the reference host as of 2026-11-11 (see docs in the PR body) ---
OMARCHY_REPO=https://pkgs.omarchy.org/rc/x86_64
ARCHIVE=https://archive.archlinux.org/packages
pinned=(
  # url                                                                             sha256
  "$OMARCHY_REPO/quickshell-0.3.2.r7.g2b4501a-1-x86_64.pkg.tar.zst                  f9f813213597d1ee25e16860ed326e810857810460c09ee87d06bc3b655c2da1"
  "$OMARCHY_REPO/omarchy-4.5.0-3-x86_64.pkg.tar.zst                                 bfe75d086c8b5c919280372afdd72e8cc7b0f66745f052d826b5a588fdad33eb"
  "$ARCHIVE/q/qt6-declarative/qt6-declarative-6.12.0-2-x86_64.pkg.tar.zst           8072d884df0d344d31a3f56e75feece93013cc20077626327ca8cde3779045bd"
  "$OMARCHY_REPO/omarchy-settings-4.5.0-3-x86_64.pkg.tar.zst                        14a4f0cae0717df80fe2c08e7a3b0ba37b3935f09b31904d94c25b6baa141a87"
)
# Versions the test steps rely on; checked after installation.
expect_versions="omarchy 4.5.0-3
quickshell 0.3.2.r7.g2b4501a-1
qt6-base 6.12.0-3
qt6-declarative 6.12.0-2"

fetch() {
  local url=$1 sum=$2 file="$work/${1##*/}"
  ci_fetch_verified "$deadline" "$url" "$sum" "$file"
  echo "$file"
}

# Arch packages from the same archive date the image and mirror use (set before
# checkout). Signatures are verified by pacman against the image's keyring.
# Skip redundant -y database re-sync when the pre-checkout step already synced
# this immutable archive date; standalone runs without sync DBs still run -Syu.
if [[ -s /var/lib/pacman/sync/core.db && -s /var/lib/pacman/sync/extra.db ]]; then
  pacman_sync_flag="-S"
else
  pacman_sync_flag="-Syu"
fi
ci_pacman_retry "$deadline" 240 -- "$pacman_sync_flag" --noconfirm --needed \
  jq nodejs bubblewrap qt6-base qt6-declarative qt6-svg qt6-wayland \
  noto-fonts ttf-liberation fontconfig

files=()
for entry in "${pinned[@]}"; do
  read -r url sum <<<"$entry"
  file=$(fetch "$url" "$sum")
  files+=("$file")
done

# Local package files are trusted through the recorded sha256 above (pacman's
# default LocalFileSigLevel does not require a signature), so the Omarchy
# keyring is not needed. quickshell's dependencies resolve from the archive
# date; qt6-declarative is moved to the host's build.
ci_pacman_retry "$deadline" 180 -- -U --noconfirm "${files[0]}" "${files[2]}"
# omarchy without its desktop dependencies (Hyprland, SDDM, Limine, ...): the
# tests need its shell tree and CLI scripts only. The package has no install
# script, so skipping dependencies runs no hook that expects them.
pacman -U --noconfirm --nodeps --nodeps "${files[1]}"
# omarchy-settings provides /usr/share/omarchy/default/hypr/ (checked by the
# compatibility contract), the default config/omarchy/shell.json (referenced by
# the capability inventory) and Omarchy's fontconfig policy (50-omarchy.conf,
# which binds sans-serif to Liberation Sans) plus omarchy.ttf. Its .INSTALL
# script overwrites /etc/os-release, /etc/nsswitch.conf, /etc/security/faillock.conf,
# /etc/plymouth/plymouthd.conf, /etc/skel/.bashrc and manages sudoers grants,
# so extract only the verified upstream trees directly rather than running pacman -U.
bsdtar -xf "${files[3]}" -C / \
  usr/share/omarchy/default/hypr \
  usr/share/omarchy/config/omarchy/shell.json \
  usr/share/fontconfig/conf.avail/50-omarchy.conf \
  etc/fonts/conf.d/50-omarchy.conf \
  usr/share/fonts/omarchy
fc-cache -f

actual=$(pacman -Q omarchy quickshell qt6-base qt6-declarative)
if [[ $actual != "$expect_versions" ]]; then
  echo "bootstrap: installed versions differ from the pins:" >&2
  diff <(echo "$expect_versions") <(echo "$actual") >&2
  exit 1
fi

# The unprivileged test user, its runtime directory (Qt warns on stderr without
# one, and isolated.sh mounts a tmpfs over it), and ownership of the checkout
# so git does not refuse it as a foreign repository.
useradd -m -u "$uid" "$user"
install -d -m 700 -o "$user" -g "$user" "/run/user/$uid"
chown -R "$user:$user" "$GITHUB_WORKSPACE"

rm -rf "$work"
echo "$actual"
