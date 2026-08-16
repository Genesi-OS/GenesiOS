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
    GENESI_EXPLAIN_STATUS="$status" /usr/local/bin/genesi-explain "$cmd" </dev/null 2>/dev/null
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
