# Genesi AI Assist — shell integration.
#
# Explains a command that just failed, using the model already warm on the
# Genesi Turbo daemon. Sourced for interactive bash and zsh sessions.
#
# Design rules this file must keep:
#   * It runs after EVERY command, so it has to be nearly free. The work is one
#     backgrounded process that exits immediately when no model is warm.
#   * It must never break the shell. No `set -e` interaction, no changes to
#     $?, no output on success.
#   * It must never re-run the failed command. Re-running is how a helper
#     deletes something twice.
#
# Turn it off with `explain_errors = off` in ~/.config/genesi-ai-assist.conf,
# or unset GENESI_ASSIST_SHELL below.

# Not interactive? Nothing to help with.
case $- in
    *i*) ;;
    *) return 0 2>/dev/null || true ;;
esac

[ -x /usr/local/bin/genesi-explain ] || return 0 2>/dev/null || true

# Exit codes that are normal user actions, not failures worth explaining:
#   1   far too common and usually meaningful on its own (grep found nothing,
#       diff differed, test was false)
#   2   usage errors are usually self-explanatory from the tool's own message
#   126/127 handled by the shell's own "command not found" message
#   130 Ctrl-C, 148 Ctrl-Z
_genesi_assist_skip_status() {
    case "$1" in
        0|1|2|126|127|130|148) return 0 ;;
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
    # Backgrounded so the prompt never waits on the model. Each descriptor is
    # deliberate:
    #   stdin  -> /dev/null. Otherwise the background process holds the
    #             terminal's stdin and competes with the shell for keystrokes.
    #   stdout -> INHERITED. This is the explanation; sending it to /dev/null
    #             would silently disable the whole feature.
    #   stderr -> /dev/null. A helper must never put noise in the terminal.
    # The subshell wrapper suppresses bash's "[1]+ Done" job notification.
    ( GENESI_EXPLAIN_STATUS="$status" /usr/local/bin/genesi-explain "$cmd" \
        </dev/null 2>/dev/null & )
    return 0
}

if [ -n "$BASH_VERSION" ]; then
    _genesi_assist_bash_prompt() {
        local status=$?
        local cmd
        cmd=$(HISTTIMEFORMAT= builtin history 1 2>/dev/null | sed 's/^ *[0-9]* *//')
        _genesi_assist_report "$status" "$cmd"
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
        return 0
    }
    _genesi_assist_zsh_preexec() { _genesi_assist_last_cmd="$1"; }
    autoload -Uz add-zsh-hook 2>/dev/null && {
        add-zsh-hook precmd _genesi_assist_zsh_precmd
        add-zsh-hook preexec _genesi_assist_zsh_preexec
    }
fi
