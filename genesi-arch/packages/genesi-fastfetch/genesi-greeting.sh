# Genesi OS terminal greeting — sourced from /etc/bash.bashrc for EVERY
# interactive bash (login AND non-login). The old /etc/profile.d version only
# ran for login shells, so it showed under `sudo -i` but NOT when Konsole
# opened a normal interactive bash. This file fixes that.

# Only interactive shells; never in scripts / scp / rsync.
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || true ;;
esac

# Once per terminal (exported flag stops split panes / subshells repeating it).
if [ -z "${GENESI_FASTFETCH_SHOWN:-}" ] && command -v fastfetch >/dev/null 2>&1; then
  export GENESI_FASTFETCH_SHOWN=1
  # The store's Fastfetch shelf writes config.jsonc here. Passing --config
  # unconditionally meant it was never read, so applying a style changed
  # nothing anybody would see.
  genesi_own="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch/config.jsonc"
  if [ -f "$genesi_own" ]; then
    fastfetch --config "$genesi_own"
  else
    fastfetch --config /usr/share/genesi/fastfetch/genesi.jsonc
  fi
  unset genesi_own
fi
