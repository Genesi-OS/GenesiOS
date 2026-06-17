#!/bin/sh
# Genesi Code launch wrapper (/usr/bin/genesi-code).
#
# Its ONE job is to redirect stdio to a per-user log before exec'ing the real
# launcher. That redirect is what fixes "opens from a terminal but loads-and-
# closes from the menu": when started from the KDE menu / KRunner / a plasmoid,
# the app's stdout/stderr is a pipe owned by the launcher's short-lived
# transient scope. Once that scope exits the pipe's read end is gone, and the
# app — which logs to stdout continuously — is killed by SIGPIPE/EIO on its next
# write. A terminal keeps those fds alive, which is why it runs there. Pointing
# stdio at a file keeps the app alive and also leaves a crash log behind.
#
# Deliberately NO `setsid` here. A previous version wrapped the launcher in
# `setsid -f`, which detached the app into a new session and broke the GUI
# launch entirely. `exec` keeps the app as the launcher scope's own process,
# which is exactly what the desktop/menu expects — we only swap its stdio.
#
# The real launcher (/usr/lib/genesi-code/genesi-code, shipped in the release
# tarball) handles VM software-GL fallback and execs the sibling .bin.
LOGDIR="${XDG_CACHE_HOME:-$HOME/.cache}/genesi-code"
mkdir -p "$LOGDIR" 2>/dev/null || true
exec /usr/lib/genesi-code/genesi-code "$@" </dev/null >"$LOGDIR/genesi-code.log" 2>&1
