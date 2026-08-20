# Genesi AI Assist — fish integration.
#
# Same contract as genesi-assist.sh (bash/zsh): when a command fails, explain it
# using the model already warm on the Genesi Turbo daemon, and offer the fix as
# dim ghost text that → accepts. Installed into fish's vendor_conf.d so it loads
# with no dotfile edits.
#
# fish is a first-class target here, not an afterthought: it is Genesi's default
# interactive shell, so a helper that only spoke bash and zsh did nothing at all
# for the people most likely to see it.
#
# Rules this file must keep, same as the POSIX version:
#   * Runs after EVERY command, so it has to be nearly free. The work is one
#     backgrounded process that exits immediately when no model is warm.
#   * Never breaks the shell, never changes $status, silent on success.
#   * Never re-runs the failed command — and never runs the fix either. The fix
#     is only ever placed ON the command line; the user presses Enter.
#
# Turn it off with `explain_errors = off` in ~/.config/genesi-ai-assist.conf.
# `suggest_fix = off` keeps the explanation and drops the ghost text.

if status is-interactive; and test -x /usr/local/bin/genesi-explain

    # Where genesi-explain leaves the fix for THIS terminal: keyed by the shell
    # pid, on tmpfs, mode 0600. No XDG_RUNTIME_DIR means no ghost text — /tmp is
    # not an acceptable home for a file whose contents get armed onto a keypress.
    if set -q XDG_RUNTIME_DIR
        set -g __genesi_fix_file "$XDG_RUNTIME_DIR/genesi-ai-assist/fix.$fish_pid"
    else
        set -g __genesi_fix_file ""
    end

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

    # Take this terminal's pending fix and consume the file, so a suggestion can
    # never outlive the command it belongs to. Line 1 is the fix, line 2 the
    # flags; `read` is a builtin and the block shares one open file, so the whole
    # read costs no process.
    function __genesi_fix_take
        set -e __genesi_fix_pending
        set -e __genesi_fix_hist
        test -n "$__genesi_fix_file"; or return 0
        test -f "$__genesi_fix_file"; or return 0
        begin
            read -l fix
            read -l flags
            if test -n "$fix"
                set -g __genesi_fix_pending $fix
                if test "$flags" = "hist=1"
                    set -g __genesi_fix_hist 1
                end
            end
        end < "$__genesi_fix_file"
        command rm -f -- "$__genesi_fix_file" 2>/dev/null

        # THE GHOST TEXT, in the one way fish allows.
        #
        # fish has no API for setting an autosuggestion — the feature is
        # deliberately not scriptable (fish-shell#9809) — and its only sources
        # are completions and history. So we put the fix into history, and fish
        # then draws it dim, ahead of the cursor, the instant the user types the
        # first character, with → to accept. That is fish's own renderer and its
        # own keybinding: nothing here paints on the terminal, which is what kept
        # the old backgrounded explainer typing over people.
        #
        # The cost is honest and worth naming: one history entry for a command
        # that was never run. `suggest_fix_history = off` turns it off, and the
        # → binding below still works without it.
        if set -q __genesi_fix_hist; and set -q __genesi_fix_pending
            # `switch` rather than an option-taking builtin: a fix that somehow
            # began with a dash would be read as a flag by `history append`.
            switch $__genesi_fix_pending
                case '-*'
                case '*'
                    history append $__genesi_fix_pending 2>/dev/null
            end
        end
    end

    function __genesi_assist_postexec --on-event fish_postexec
        # MUST be the first statement: any command before it clobbers $status.
        set -l st $status
        set -l cmd $argv[1]

        # Whatever was on offer belongs to the previous command. Drop it first,
        # so an early return below can never leave a stale suggestion armed.
        set -e __genesi_fix_pending

        __genesi_assist_skip_status $st; and return 0
        __genesi_assist_skip_cmd "$cmd"; and return 0

        # Run SYNCHRONOUSLY, here in fish_postexec, which is before the next
        # prompt is drawn.
        #
        # This used to be backgrounded, and that was the wrong call: the model
        # takes a second or two, so the answer always landed AFTER the prompt
        # had been drawn -- printing into the middle of whatever the user had
        # started typing, and sometimes explaining a command from a while back.
        # Running it here means the explanation appears directly under the
        # failed command, like a comment, and never interrupts anything.
        #
        # The cost is a short pause after a FAILED command only. That is
        # bounded by `timeout` in genesi-ai-assist.conf, returns instantly when
        # no model is warm (connection refused), and is free on a cache hit.
        GENESI_EXPLAIN_STATUS=$st GENESI_ASSIST_FIX_FILE=$__genesi_fix_file \
            /usr/local/bin/genesi-explain "$cmd" </dev/null 2>/dev/null

        __genesi_fix_take
    end

    # → on an EMPTY line puts the pending fix on the command line — it does not
    # run it. On any other line it is the plain forward-char, which is also how
    # fish accepts its own autosuggestion, so the key keeps working exactly as
    # it always did.
    function __genesi_fix_accept
        set -l buf (commandline)
        if test -z "$buf"; and set -q __genesi_fix_pending
            commandline --replace $__genesi_fix_pending
            commandline -f end-of-line
            set -e __genesi_fix_pending
            return 0
        end
        commandline -f forward-char
    end

    # Bind at the FIRST prompt, not here: conf.d is sourced before fish installs
    # its own key bindings, which would erase anything we set now. By the first
    # prompt every binding — fish's and the user's — is in place.
    function __genesi_fix_bind --on-event fish_prompt
        functions --erase __genesi_fix_bind
        for seq in \e\[C \eOC \cf
            bind $seq __genesi_fix_accept 2>/dev/null
            bind -M insert $seq __genesi_fix_accept 2>/dev/null
        end
    end
end
