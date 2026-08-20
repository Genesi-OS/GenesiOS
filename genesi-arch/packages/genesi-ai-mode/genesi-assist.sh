# Genesi AI Assist — shell integration.
#
# Explains a command that just failed, using the model already warm on the
# Genesi Turbo daemon, and offers the fix as ghost text that → accepts. Sourced
# for interactive bash and zsh sessions.
#
# Design rules this file must keep:
#   * It runs after EVERY command, so it has to be nearly free. The work is one
#     backgrounded process that exits immediately when no model is warm.
#   * It must never break the shell. No `set -e` interaction, no changes to
#     $?, no output on success.
#   * It must never re-run the failed command. Re-running is how a helper
#     deletes something twice. The same rule governs the fix: it is only ever
#     PUT ON the command line, by a keypress. The user presses Enter.
#
# Turn it off with `explain_errors = off` in ~/.config/genesi-ai-assist.conf,
# or unset GENESI_ASSIST_SHELL below. `suggest_fix = off` keeps the explanation
# and drops the ghost text.

# Not interactive? Nothing to help with.
case $- in
    *i*) ;;
    *) return 0 2>/dev/null || true ;;
esac

[ -x /usr/local/bin/genesi-explain ] || return 0 2>/dev/null || true

# Where genesi-explain leaves the fix for this terminal.
#
# Keyed by the SHELL's pid, on tmpfs, mode 0600: per-terminal, gone at logout,
# unreadable by anyone else. No XDG_RUNTIME_DIR means no ghost text at all —
# /tmp is not an acceptable fallback for a file whose contents get armed onto a
# keypress. The explanation itself still works.
if [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    _GENESI_ASSIST_FIX_FILE="$XDG_RUNTIME_DIR/genesi-ai-assist/fix.$$"
else
    _GENESI_ASSIST_FIX_FILE=""
fi

# Exit codes NOT worth explaining.
#
# 1 and 2 used to be here and that was wrong: exit 1 is what pacman, git, cargo,
# make and almost every real tool returns when it genuinely fails, so skipping
# it threw away nearly every case this helper exists for. The noisy-exit-1
# commands (grep, diff, test) are handled by the command skip-list instead,
# which is the right place for them.
#
# 126/127 stay: the shell already says "command not found" and Arch's pkgfile
# handler already suggests the package. 130/148 are Ctrl-C and Ctrl-Z.
_genesi_assist_skip_status() {
    case "$1" in
        0|126|127|130|148) return 0 ;;
        *) return 1 ;;
    esac
}

# Commands whose non-zero exit is a normal outcome rather than a problem.
_genesi_assist_skip_cmd() {
    case "$1" in
        ''|genesi-explain*|grep*|rg*|diff*|test*|'['*|pgrep*|fc*|history*) return 0 ;;
        *) return 1 ;;
    esac
}

_genesi_assist_report() {
    local status="$1" cmd="$2"
    _genesi_assist_skip_status "$status" && return 0
    _genesi_assist_skip_cmd "$cmd" && return 0
    # Run SYNCHRONOUSLY, before the next prompt is drawn.
    #
    # This used to be backgrounded, which meant the model's answer arrived
    # AFTER the prompt -- printing into the middle of whatever the user had
    # started typing, and occasionally explaining a command from a while back.
    # Running it inline puts the explanation directly under the failed command,
    # like a comment, and it can never interrupt typing.
    #
    # The cost is a short pause after a FAILED command only, bounded by
    # `timeout` in genesi-ai-assist.conf, instant when no model is warm.
    GENESI_EXPLAIN_STATUS="$status" \
    GENESI_ASSIST_FIX_FILE="$_GENESI_ASSIST_FIX_FILE" \
        /usr/local/bin/genesi-explain "$cmd" </dev/null 2>/dev/null
    return 0
}

# Read this terminal's pending fix into _genesi_fix_pending and consume the
# file, so a suggestion can never outlive the prompt it belongs to.
#
# `read` is a builtin in both bash and zsh and takes only the first line, so the
# read costs no process at all; the `rm` is the only one this whole mechanism
# spawns, and it happens only on a prompt that just printed an explanation —
# i.e. right after we already spent a second on a model.
_genesi_fix_take() {
    _genesi_fix_pending=""
    [ -n "$_GENESI_ASSIST_FIX_FILE" ] || return 0
    [ -f "$_GENESI_ASSIST_FIX_FILE" ] || return 0
    read -r _genesi_fix_pending < "$_GENESI_ASSIST_FIX_FILE" 2>/dev/null
    command rm -f -- "$_GENESI_ASSIST_FIX_FILE" 2>/dev/null
    return 0
}

if [ -n "$BASH_VERSION" ]; then
    # bash cannot draw text that readline does not own, so there is no true
    # ghost text here: genesi-explain prints the fix with a "→ to use" marker
    # and this binds → to accept it. zsh and fish get the dim inline version.
    _genesi_fix_pending=""
    _genesi_fix_armed=0

    _genesi_fix_accept() {
        if [ -z "$READLINE_LINE" ] && [ -n "$_genesi_fix_pending" ]; then
            READLINE_LINE="$_genesi_fix_pending"
            READLINE_POINT=${#READLINE_LINE}
            _genesi_fix_pending=""
            _genesi_fix_disarm
            return 0
        fi
        # Not our case: do exactly what the key we borrowed would have done,
        # then give it back.
        if [ "${READLINE_POINT:-0}" -lt "${#READLINE_LINE}" ]; then
            READLINE_POINT=$((READLINE_POINT + 1))
        fi
        _genesi_fix_disarm
        return 0
    }

    # → is ours only while a fix is pending, which is the single prompt right
    # after a failure. The rest of the time the key is untouched, so nothing a
    # user has bound to it is permanently replaced.
    _genesi_fix_arm() {
        [ "$_genesi_fix_armed" = 1 ] && return 0
        bind -x '"\e[C": _genesi_fix_accept' 2>/dev/null
        bind -x '"\eOC": _genesi_fix_accept' 2>/dev/null
        _genesi_fix_armed=1
        return 0
    }

    _genesi_fix_disarm() {
        [ "$_genesi_fix_armed" = 1 ] || return 0
        bind '"\e[C": forward-char' 2>/dev/null
        bind '"\eOC": forward-char' 2>/dev/null
        _genesi_fix_armed=0
        return 0
    }

    _genesi_assist_bash_prompt() {
        local status=$?
        local cmd
        cmd=$(HISTTIMEFORMAT= builtin history 1 2>/dev/null | sed 's/^ *[0-9]* *//')
        _genesi_assist_report "$status" "$cmd"
        _genesi_fix_take
        if [ -n "$_genesi_fix_pending" ]; then
            _genesi_fix_arm
        else
            _genesi_fix_disarm
        fi
        return 0
    }
    # Append rather than replace: other tools legitimately own PROMPT_COMMAND.
    case ";$PROMPT_COMMAND;" in
        *";_genesi_assist_bash_prompt;"*) ;;
        *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_genesi_assist_bash_prompt" ;;
    esac
elif [ -n "$ZSH_VERSION" ]; then
    _genesi_assist_zsh_precmd() {
        local status=$?
        local cmd="${_genesi_assist_last_cmd}"
        _genesi_assist_last_cmd=""
        _genesi_assist_report "$status" "$cmd"
        _genesi_fix_take
        if [[ -n $_genesi_fix_pending ]]; then
            _genesi_fix_arm
        else
            _genesi_fix_disarm
        fi
        return 0
    }
    _genesi_assist_zsh_preexec() { _genesi_assist_last_cmd="$1"; }
    autoload -Uz add-zsh-hook 2>/dev/null && {
        add-zsh-hook precmd _genesi_assist_zsh_precmd
        add-zsh-hook preexec _genesi_assist_zsh_preexec
    }

    # ── Ghost text ───────────────────────────────────────────────────────────
    #
    # zsh can display text after the cursor that is not part of the buffer
    # (POSTDISPLAY) — the same mechanism zsh-autosuggestions uses. We use it
    # ONLY while the line is empty, and that is deliberate: an empty line is the
    # one state in which no autosuggestion plugin is showing anything, so this
    # cannot fight one. The first keystroke hands the line straight back.
    typeset -g _genesi_fix_pending=""
    typeset -g _genesi_fix_armed=0
    # Whether the ghost currently on screen is OURS. Without this we would clear
    # POSTDISPLAY unconditionally and wipe zsh-autosuggestions' suggestion.
    typeset -g _genesi_fix_showing=0
    typeset -gA _genesi_fix_orig
    typeset -ga _genesi_fix_keys
    _genesi_fix_keys=('^[[C' '^[OC' '^F')

    # What did those keys do before we existed? Captured once per shell, at a
    # prompt — i.e. after .zshrc and every plugin has had its turn — and only
    # the first time there is actually something to offer.
    _genesi_fix_capture() {
        (( ${#_genesi_fix_orig} )) && return 0
        local k w
        for k in $_genesi_fix_keys; do
            w=${${(z)$(bindkey -- $k 2>/dev/null)}[2]}
            _genesi_fix_orig[$k]=${w:-undefined-key}
        done
        return 0
    }

    _genesi_fix_arm() {
        (( _genesi_fix_armed )) && return 0
        _genesi_fix_capture
        local k
        for k in $_genesi_fix_keys; do bindkey -- $k _genesi_fix_accept; done
        _genesi_fix_armed=1
        return 0
    }

    _genesi_fix_disarm() {
        (( _genesi_fix_armed )) || return 0
        local k
        for k in $_genesi_fix_keys; do bindkey -- $k "${_genesi_fix_orig[$k]}"; done
        _genesi_fix_armed=0
        return 0
    }

    # Erase the ghost, but ONLY if it is the one we drew.
    _genesi_fix_hide() {
        (( _genesi_fix_showing )) || return 0
        POSTDISPLAY=""
        _genesi_fix_showing=0
        return 0
    }

    _genesi_fix_accept() {
        if [[ -z $BUFFER && -n $_genesi_fix_pending ]]; then
            BUFFER=$_genesi_fix_pending
            CURSOR=${#BUFFER}
            _genesi_fix_pending=""
            _genesi_fix_hide
            region_highlight=()
            _genesi_fix_disarm
            return 0
        fi
        # Not ours. Put the real bindings back and replay the keypress through
        # them, so whatever the user (or zsh-autosuggestions) had on this key
        # still happens, exactly once.
        _genesi_fix_pending=""
        _genesi_fix_hide
        _genesi_fix_disarm
        zle -U -- "$KEYS"
        return 0
    }

    _genesi_fix_show() {
        if [[ -z $_genesi_fix_pending ]]; then
            _genesi_fix_hide
            return 0
        fi
        if [[ -n $BUFFER ]]; then      # the user is typing: stand down
            _genesi_fix_pending=""
            _genesi_fix_hide
            _genesi_fix_disarm
            return 0
        fi
        POSTDISPLAY=$_genesi_fix_pending
        _genesi_fix_showing=1
        # Safe to own the whole array here: the buffer is empty, so there is no
        # user text for a syntax highlighter to be styling.
        region_highlight=("0 ${#POSTDISPLAY} fg=8")
        return 0
    }

    # Enter must not carry the ghost into the accepted line.
    _genesi_fix_finish() {
        _genesi_fix_hide
        _genesi_fix_disarm
        return 0
    }

    zle -N _genesi_fix_accept
    zle -N _genesi_fix_show
    zle -N _genesi_fix_finish
    autoload -Uz add-zle-hook-widget 2>/dev/null && {
        add-zle-hook-widget line-init       _genesi_fix_show
        add-zle-hook-widget line-pre-redraw _genesi_fix_show
        add-zle-hook-widget line-finish     _genesi_fix_finish
    }
fi
