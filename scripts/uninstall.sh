#!/usr/bin/env bash
# Remove the installed plugin. If it is the selected bar, the stock bar is
# restored first (through rollback.sh), so the shell never points at a bar
# that no longer exists.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

if [[ $(selected_bar) == "$plugin_id" ]]; then
  "$repo_root/scripts/rollback.sh" --id "$plugin_id"
fi

if [[ -d $install_dir && ! -L $install_dir ]]; then
  rm -rf -- "$install_dir"
  say "removed $install_dir"
else
  say "nothing installed at $install_dir"
fi
