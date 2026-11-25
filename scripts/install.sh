#!/usr/bin/env bash
# Copy the plugin into ~/.config/omarchy/plugins/<id>. Installing does not
# select the bar: shell.json is not touched and the desktop keeps its current
# bar. Use scripts/activate.sh for that, deliberately.
#
#   install.sh            validate, then install or update
#   install.sh --dry-run  validate and show where it would go
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

dry_run=0
[[ ${1:-} == --dry-run ]] && dry_run=1

stage=$(stage_plugin)
trap 'rm -rf "$stage"' EXIT

omarchy plugin validate "$stage/$plugin_id" >/dev/null || die "omarchy plugin validate rejected the plugin"
say "validated $plugin_id"

if [[ -e $install_dir ]]; then
  [[ -d $install_dir && ! -L $install_dir ]] || die "$install_dir exists and is not a plain directory"
  existing=$(jq -r '.id // empty' "$install_dir/manifest.json" 2>/dev/null || true)
  [[ $existing == "$plugin_id" ]] || die "$install_dir holds something else (id '${existing:-none}'); not touching it"
fi

if (( dry_run )); then
  say "would install to $install_dir"
  exit 0
fi

# Swap in a complete copy so the shell's file watcher never sees a half-written plugin.
mkdir -p "$plugins_dir"
next="$plugins_dir/.$plugin_id.next"
old="$plugins_dir/.$plugin_id.old"
rm -rf -- "$next" "$old"
cp -R "$stage/$plugin_id" "$next"
[[ -d $install_dir ]] && mv -- "$install_dir" "$old"
mv -- "$next" "$install_dir"
rm -rf -- "$old"
say "installed $plugin_id to $install_dir"

for legacy in "${legacy_plugin_ids[@]}"; do
  [[ $legacy != "$plugin_id" && -d $plugins_dir/$legacy ]] \
    && say "legacy installation kept untouched at $plugins_dir/$legacy"
done

current=$(selected_bar)
if [[ $current == "$plugin_id" ]]; then
  say "this bar is selected; the shell reloads it from the new files"
elif is_known_plugin_id "$current"; then
  say "legacy bar $current is still selected; run scripts/activate.sh to switch to $plugin_id"
else
  say "not selected; the current bar is unchanged (activate with scripts/activate.sh)"
fi
