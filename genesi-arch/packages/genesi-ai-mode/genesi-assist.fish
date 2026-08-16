# Genesi AI Assist — fish integration.
#
# Same contract as genesi-assist.sh (bash/zsh): when a command fails, explain it
# using the model already warm on the Genesi Turbo daemon. Installed into fish's
# vendor_conf.d so it loads with no dotfile edits.
#
# fish is a first-class target here, not an afterthought: it is Genesi's default
# interactive shell, so a helper that only spoke bash and zsh did nothing at all
# for the people most likely to see it.
#
# Rules this file must keep, same as the POSIX version:
#   * Runs after EVERY command, so it has to be nearly free. The work is one
#     backgrounded process that exits immediately when no model is warm.
#   * Never breaks the shell, never changes $status, silent on success.
#   * Never re-runs the failed command.
#
# Turn it off with `explain_errors = off` in ~/.config/genesi-ai-assist.conf.

if status is-interactive; and test -x /usr/local/bin/genesi-explain

    # Exit codes that are NOT worth explaining.
    #
    # 1 and 2 used to be here and that was wrong: exit 1 is what pacman, git,
    # cargo, make and almost every real tool returns when it genuinely fails, so
    # skipping it threw away nearly every case the helper exists for. A user
    # tested the feature, saw nothing, and reasonably concluded it was broken.
    # The noisy-exit-1 commands (grep, diff, test...) are already handled by the
    # command skip-list below, which is the right place for them.
    #
    # 126/127 stay skipped: the shell already prints "command not found", and
    # Arch's pkgfile handler already suggests which package provides it.
    # 130/148 are Ctrl-C and Ctrl-Z.
    function __genesi_assist_skip_status
        switch $argv[1]
            case 0 126 127 130 148
                return 0
        end
        return 1
    end

    # Commands whose non-zero exit is a normal outcome, not a problem.
    function __genesi_assist_skip_cmd
        switch $argv[1]
            case '' 'genesi-explain*' 'grep*' 'rg*' 'diff*' 'test*' '[*' \
                 'pgrep*' 'fc*' 'history*'
                return 0
        end
        return 1
    end

    function __genesi_assist_postexec --on-event fish_postexec
        # MUST be the first statement: any command before it clobbers $status.
        set -l st $status
        set -l cmd $argv[1]

        __genesi_assist_skip_status $st; and return 0
        __genesi_assist_skip_cmd "$cmd"; and return 0

        # Backgrounded so the prompt never waits on the model. Each descriptor is
        # deliberate:
        #   stdin  -> /dev/null, or the background process holds the terminal's
        #             stdin and competes with the shell for keystrokes.
        #   stdout -> INHERITED. This is the explanation; discarding it would
        #             silently disable the whole feature.
        #   stderr -> /dev/null. A helper must never put noise in the terminal.
        GENESI_EXPLAIN_STATUS=$st /usr/local/bin/genesi-explain "$cmd" \
            </dev/null 2>/dev/null &
        disown
    end
end
