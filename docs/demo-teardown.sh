#!/usr/bin/env bash
# Undo docs/demo-setup.sh.
#
# Split out of the tape so a render that dies halfway — a vhs timeout, ^C, a
# broken shim — can be cleaned up with one command instead of leaving a fake
# HOME and a shim directory behind.
#
# Deliberately not `set -e`: every step is best-effort, and the common case is
# tearing down a setup that only half happened.

ROOT="${SETTINGS_DEMO_ROOT:-/tmp/settings-demo}"

# Refuse to delete anything that is not ours. The sandbox is built entirely by
# demo-setup.sh, and demo-setup.sh drops this marker as its last act, so a
# missing marker means the path is something else — an operator's typo in
# SETTINGS_DEMO_ROOT, most likely — and deleting it would be the one
# destructive thing this demo could possibly do.
if [[ -e "$ROOT" && ! -f "$ROOT/.settings-demo" ]]; then
    echo "refusing to remove $ROOT: no .settings-demo marker" >&2
    exit 1
fi

rm -rf "$ROOT"
