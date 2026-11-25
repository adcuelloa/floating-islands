#!/usr/bin/env bash
# Runs the QML tests offscreen. Quickshell's own module only loads inside the
# quickshell binary, so tests/qml/stubs stands in for the few Quickshell and
# Omarchy types the tested files use; Omarchy's real PluginBarApi.qml (plain
# QtQuick) is linked in from the installed shell.
set -uo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OMARCHY=${OMARCHY_PATH:-/usr/share/omarchy}
ui=$(mktemp -d /tmp/islands-qmltest.XXXXXX)
trap 'rm -rf "$ui"' EXIT
mkdir -p "$ui/qs/Ui"
ln -s "$OMARCHY/shell/Ui/PluginBarApi.qml" "$ui/qs/Ui/PluginBarApi.qml"
printf 'module qs.Ui\nPluginBarApi 1.0 PluginBarApi.qml\n' >"$ui/qs/Ui/qmldir"
# Before the first TestCase starts Testlib's logger, Qt's default handler may send
# messages to the systemd journal instead of the terminal; forcing stderr keeps
# the first-loaded file's load-time warnings visible. stderr is replayed below.
QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 "${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}" \
  -import "$here/stubs" -import "$ui" -input "$here" "$@" 2>"$ui/err" | tee "$ui/log"
status=${PIPESTATUS[0]}
cat "$ui/err" >&2
# Any logged warning fails the run, including those raised while a scene loads,
# before its TestCase's init() and so out of failOnWarning's reach. Expected
# warnings stay possible through ignoreWarning(), which keeps them out of the log.
warnings=$(grep -cE '^(QWARN|QCRITICAL|QFATAL) ' "$ui/log")
if ((warnings)); then
  echo "FAIL!  : run.sh: $warnings unexpected QWARN/QCRITICAL/QFATAL line(s) above"
  ((status)) || status=1
fi
# Any stderr byte fails the run, even a diagnostic Qt might one day call harmless:
# such output is to be evaluated and fixed or ignored explicitly, not passed over.
if [[ -s "$ui/err" ]]; then
  echo "FAIL!  : run.sh: qmltestrunner wrote $(wc -c <"$ui/err") byte(s) to stderr above"
  ((status)) || status=1
fi
exit "$status"
