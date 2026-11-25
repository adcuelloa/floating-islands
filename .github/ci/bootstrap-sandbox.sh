#!/usr/bin/env bash
# Stages the minimal genuine upstream files needed by tests/scripts/sandbox.test.sh
# onto an ephemeral Ubuntu 24.04 runner, without pacman, without Omarchy install
# hooks, and without executing any Arch ELF binaries.
#
# Every archive is fetched from the same pinned immutable URLs and verified against
# the same SHA256 digests as .github/ci/bootstrap.sh. Only explicitly allowlisted
# shell scripts, manifests, defaults, and plain-text qmldir files are extracted
# after inspecting archive member paths and symlink targets.
#
# Usage (as root): .github/ci/bootstrap-sandbox.sh
set -euo pipefail

# Verify required Ubuntu host tools exist; never mock missing prerequisites.
required_tools=(
  bash jq curl sha256sum bsdtar flock find sort xargs cmp diff pgrep
  bwrap systemd-run
)
missing=()
for tool in "${required_tools[@]}"; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if (( ${#missing[@]} > 0 )); then
  echo "bootstrap-sandbox: missing required host tool(s): ${missing[*]}" >&2
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# shellcheck source=.github/ci/retry.sh
source "$(dirname "${BASH_SOURCE[0]}")/retry.sh"
# Overall deadline for pinned artifact fetches inside the 10-minute step timeout.
deadline=$(( $(date +%s) + 480 ))

# --- pins: identical to .github/ci/bootstrap.sh ---
OMARCHY_REPO=https://pkgs.omarchy.org/rc/x86_64
ARCHIVE=https://archive.archlinux.org/packages

OMARCHY_URL="$OMARCHY_REPO/omarchy-4.5.0-3-x86_64.pkg.tar.zst"
OMARCHY_SHA="bfe75d086c8b5c919280372afdd72e8cc7b0f66745f052d826b5a588fdad33eb"

OMARCHY_SETTINGS_URL="$OMARCHY_REPO/omarchy-settings-4.5.0-3-x86_64.pkg.tar.zst"
OMARCHY_SETTINGS_SHA="14a4f0cae0717df80fe2c08e7a3b0ba37b3935f09b31904d94c25b6baa141a87"

QT_DECL_URL="$ARCHIVE/q/qt6-declarative/qt6-declarative-6.12.0-2-x86_64.pkg.tar.zst"
QT_DECL_SHA="8072d884df0d344d31a3f56e75feece93013cc20077626327ca8cde3779045bd"

QUICKSHELL_URL="$OMARCHY_REPO/quickshell-0.3.2.r7.g2b4501a-1-x86_64.pkg.tar.zst"
QUICKSHELL_SHA="f9f813213597d1ee25e16860ed326e810857810460c09ee87d06bc3b655c2da1"

fetch() {
  local url=$1 sum=$2 file="$work/${1##*/}"
  ci_fetch_verified "$deadline" "$url" "$sum" "$file"
  echo "verified ${1##*/} ($sum)" >&2
  echo "$file"
}

# Inspect allowlisted archive members before extraction: allow only regular
# files, directories, and expected /usr/share/omarchy/bin/* -> /usr/bin/*
# symlinks. Reject hardlinks, device nodes, FIFOs, sockets, setuid/setgid bits,
# leading slashes, and parent traversal.
verify_members() {
  local archive=$1 allow_omarchy_bin_links=$2
  shift 2
  local listing line perms ftype path target
  listing=$(bsdtar -tvf "$archive" "$@")
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    perms=${line%% *}
    ftype=${perms:0:1}
    if [[ $perms == *[sS]* ]]; then
      echo "bootstrap-sandbox: setuid/setgid bit rejected in ${archive##*/}: $line" >&2
      exit 1
    fi
    case "$ftype" in
      h)
        echo "bootstrap-sandbox: hardlink rejected in ${archive##*/}: $line" >&2
        exit 1
        ;;
      b|c|p|s)
        echo "bootstrap-sandbox: special file ($ftype) rejected in ${archive##*/}: $line" >&2
        exit 1
        ;;
      l)
        path=$(awk '{print $(NF-2)}' <<<"$line")
        target=$(awk '{print $NF}' <<<"$line")
        if [[ $path == /* || $path == *..* || $target == *..* ]]; then
          echo "bootstrap-sandbox: unsafe symlink path in ${archive##*/}: $path -> $target" >&2
          exit 1
        fi
        if [[ $allow_omarchy_bin_links == yes && $path == usr/share/omarchy/bin/* && ${path#usr/share/omarchy/bin/} != */* && $target == "/usr/bin/${path##*/}" ]]; then
          continue
        fi
        echo "bootstrap-sandbox: unexpected symlink in ${archive##*/}: $path -> $target" >&2
        exit 1
        ;;
      -|d)
        path=$(awk '{print $NF}' <<<"$line")
        ;;
      *)
        echo "bootstrap-sandbox: unsupported entry type ($ftype) in ${archive##*/}: $line" >&2
        exit 1
        ;;
    esac
    if [[ $path == /* || $path == *..* ]]; then
      echo "bootstrap-sandbox: unsafe path in ${archive##*/}: $path" >&2
      exit 1
    fi
  done <<<"$listing"
}

omarchy_pkg=$(fetch "$OMARCHY_URL" "$OMARCHY_SHA")
settings_pkg=$(fetch "$OMARCHY_SETTINGS_URL" "$OMARCHY_SETTINGS_SHA")
qt_pkg=$(fetch "$QT_DECL_URL" "$QT_DECL_SHA")
qs_pkg=$(fetch "$QUICKSHELL_URL" "$QUICKSHELL_SHA")

# 1. Genuine Omarchy CLI scripts, their /usr/share/omarchy/bin symlinks, and
#    /usr/share/omarchy/shell (plugin manifests and qs.Commons / qs.Ui qmldir).
omarchy_members=(
  usr/bin/omarchy
  usr/bin/omarchy-bar
  usr/bin/omarchy-shell-config
  usr/bin/omarchy-plugin-validate
  usr/bin/omarchy-plugin-catalog
  usr/bin/omarchy-shell
  usr/bin/omarchy-restart-shell
  usr/share/omarchy/bin/omarchy
  usr/share/omarchy/bin/omarchy-bar
  usr/share/omarchy/bin/omarchy-shell-config
  usr/share/omarchy/bin/omarchy-plugin-validate
  usr/share/omarchy/bin/omarchy-plugin-catalog
  usr/share/omarchy/bin/omarchy-shell
  usr/share/omarchy/bin/omarchy-restart-shell
  usr/share/omarchy/shell
)
verify_members "$omarchy_pkg" yes "${omarchy_members[@]}"
bsdtar -xf "$omarchy_pkg" -C / "${omarchy_members[@]}"

# 2. Default shell.json referenced as DEFAULTS_FILE by omarchy-shell-config.
settings_members=(
  usr/share/omarchy/config/omarchy/shell.json
)
verify_members "$settings_pkg" no "${settings_members[@]}"
bsdtar -xf "$settings_pkg" -C / "${settings_members[@]}"

# 3. Plain-text qmldir metadata only (read by tests/imports.sh during sandbox tests).
qt_members=(
  usr/lib/qt6/qml/QtQuick/qmldir
  usr/lib/qt6/qml/QtQuick/Shapes/qmldir
  usr/lib/qt6/qml/QtQuick/Effects/qmldir
  usr/lib/qt6/qml/QtTest/qmldir
)
verify_members "$qt_pkg" no "${qt_members[@]}"
bsdtar -xf "$qt_pkg" -C / "${qt_members[@]}"

qs_members=(
  usr/lib/qt6/qml/Quickshell/qmldir
  usr/lib/qt6/qml/Quickshell/Wayland/qmldir
  usr/lib/qt6/qml/Quickshell/Hyprland/qmldir
  usr/lib/qt6/qml/Quickshell/Io/qmldir
  usr/lib/qt6/qml/Quickshell/Services/Pipewire/qmldir
  usr/lib/qt6/qml/Quickshell/Networking/qmldir
  usr/lib/qt6/qml/Quickshell/Bluetooth/qmldir
  usr/lib/qt6/qml/Quickshell/Services/UPower/qmldir
)
verify_members "$qs_pkg" no "${qs_members[@]}"
bsdtar -xf "$qs_pkg" -C / "${qs_members[@]}"

# Verify required staged files exist and are readable.
for required in \
  /usr/bin/omarchy \
  /usr/bin/omarchy-bar \
  /usr/bin/omarchy-shell-config \
  /usr/bin/omarchy-plugin-validate \
  /usr/bin/omarchy-plugin-catalog \
  /usr/bin/omarchy-shell \
  /usr/bin/omarchy-restart-shell \
  /usr/share/omarchy/bin/omarchy-shell \
  /usr/share/omarchy/shell/Commons/qmldir \
  /usr/share/omarchy/shell/Ui/qmldir \
  /usr/share/omarchy/config/omarchy/shell.json \
  /usr/lib/qt6/qml/QtQuick/qmldir \
  /usr/lib/qt6/qml/QtQuick/Shapes/qmldir \
  /usr/lib/qt6/qml/QtQuick/Effects/qmldir \
  /usr/lib/qt6/qml/QtTest/qmldir \
  /usr/lib/qt6/qml/Quickshell/qmldir \
  /usr/lib/qt6/qml/Quickshell/Wayland/qmldir \
  /usr/lib/qt6/qml/Quickshell/Hyprland/qmldir \
  /usr/lib/qt6/qml/Quickshell/Io/qmldir \
  /usr/lib/qt6/qml/Quickshell/Services/Pipewire/qmldir \
  /usr/lib/qt6/qml/Quickshell/Networking/qmldir \
  /usr/lib/qt6/qml/Quickshell/Bluetooth/qmldir \
  /usr/lib/qt6/qml/Quickshell/Services/UPower/qmldir
do
  if [[ ! -s $required ]]; then
    echo "bootstrap-sandbox: missing or empty staged file: $required" >&2
    exit 1
  fi
done

echo "bootstrap-sandbox: staged verified Omarchy scripts, shell tree, and qmldir metadata"
