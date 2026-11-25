# Shared helpers for install.sh, uninstall.sh and activate.sh. Source it.
# (rollback.sh deliberately does not use it; it must work on its own.)

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
plugin_src="$repo_root/plugin"

export OMARCHY_PATH=${OMARCHY_PATH:-/usr/share/omarchy}
# Appended, not prepended: commands already on PATH keep precedence.
[[ -d $OMARCHY_PATH/bin ]] && export PATH="$PATH:$OMARCHY_PATH/bin"
export OMARCHY_SHELL_IPC_TIMEOUT=${OMARCHY_SHELL_IPC_TIMEOUT:-2s}

say() { printf '%s: %s\n' "${0##*/}" "$*"; }
die() { printf '%s: %s\n' "${0##*/}" "$*" >&2; exit 1; }

command -v jq >/dev/null || die "jq is required"

plugin_id=$(jq -r '.id // empty' "$plugin_src/manifest.json" 2>/dev/null) || true
[[ $plugin_id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $plugin_id != *..* && $plugin_id != omarchy.* ]] \
  || die "plugin/manifest.json has no usable id"
legacy_plugin_ids=("islands.bar")
settings_key="islands"

is_known_plugin_id() {
  local id=$1 legacy
  [[ $id == "$plugin_id" ]] && return 0
  for legacy in "${legacy_plugin_ids[@]}"; do
    [[ $id == "$legacy" ]] && return 0
  done
  return 1
}

config="$HOME/.config/omarchy/shell.json"
plugins_dir="$HOME/.config/omarchy/plugins"
install_dir="$plugins_dir/$plugin_id"

selected_bar() {
  [[ -s $config ]] || { echo ""; return; }
  jq -r '.bar.id // ""' "$config"
}

shell_running() {
  command -v omarchy-shell >/dev/null && omarchy-shell shell ping >/dev/null 2>&1
}

# A copy of the plugin as it would be installed, in a fresh /tmp directory
# named after the id (the validator and the shell expect that layout).
stage_plugin() {
  local stage
  stage=$(mktemp -d /tmp/islands-stage.XXXXXX)
  mkdir -p "$stage/$plugin_id"
  cp -R "$plugin_src/." "$stage/$plugin_id/"
  if find "$stage/$plugin_id" -type l | grep -q .; then
    rm -rf "$stage"
    die "the plugin contains symlinks, which Omarchy rejects"
  fi
  printf '%s\n' "$stage"
}
