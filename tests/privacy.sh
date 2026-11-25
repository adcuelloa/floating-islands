#!/usr/bin/env bash
# Fails if the tree mentions the machine it was written on: the current user
# name, home directory, host name, or anything shaped like an email address or
# a key. The values come from the environment, so none is stored here.
set -uo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo" || exit 1

files=$(git ls-files --cached --others --exclude-standard 2>/dev/null || find . -type f -not -path './.git/*')
patterns=()
[[ -n ${USER:-} && ${#USER} -ge 3 ]] && patterns+=("$USER")
[[ -n ${HOME:-} ]] && patterns+=("$HOME")
host=$(cat /etc/hostname 2>/dev/null || hostname 2>/dev/null || true)
[[ -n $host && ${#host} -ge 3 ]] && patterns+=("$host")

hits=0
for pattern in "${patterns[@]}"; do
  if found=$(grep -nIF -- "$pattern" $files 2>/dev/null); then
    echo "personal value found:"; echo "$found" | sed 's/^/  /'; hits=1
  fi
done
if found=$(grep -nIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}|-----BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}' $files 2>/dev/null); then
  echo "email- or key-shaped text found:"; echo "$found" | sed 's/^/  /'; hits=1
fi
(( hits == 0 )) && echo "privacy: no personal values in $(wc -w <<<"$files") files"
exit $hits
