# Genesi OS - show a branded fastfetch logo + system info when a terminal opens.
# Installed to /usr/share/fish/vendor_conf.d/, which fish auto-sources on every
# shell start. We guard on `status is-interactive` so it never runs in scripts,
# and on a session flag so split panes / subshells of the same terminal don't
# repeat it (fish exports the flag to children; each NEW terminal starts fresh).
if status is-interactive
    if not set -q GENESI_FASTFETCH_SHOWN
        set -gx GENESI_FASTFETCH_SHOWN 1
        if type -q fastfetch
            # The store's Fastfetch shelf writes config.jsonc into the user's
            # own config directory. Passing --config unconditionally meant
            # that file was never read, so every card on that shelf applied
            # cleanly and changed nothing you would ever see -- the same shape
            # of bug as the lock screens writing a config for a program
            # nobody started.
            set -l own "$XDG_CONFIG_HOME"
            if test -z "$own"
                set own "$HOME/.config"
            end
            set own "$own/fastfetch/config.jsonc"
            if test -f "$own"
                fastfetch --config "$own"
            else
                fastfetch --config /usr/share/genesi/fastfetch/genesi.jsonc
            end
        end
    end
end
