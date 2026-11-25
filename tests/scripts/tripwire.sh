#!/bin/sh
# Stands in for a live-desktop command inside tests/scripts/isolated.sh.
# Reports through descriptor 9, which the parent opened outside the sandbox.
echo "${0##*/} $*" >&9 2>/dev/null
exit 1
