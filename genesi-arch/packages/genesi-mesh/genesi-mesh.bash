# Bash completion for genesi-mesh. See genesi-mesh.fish for why this matters:
# `genesi-mesh` is a prefix of the daemon `genesi-meshd`, so plain filename
# completion silently upgrades the CLI into the daemon.
_genesi_mesh() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "status peers init show-secret join peer worker serve plan selftest doctor" -- "$cur"))
        return
    fi
    case "$prev" in
        worker|serve) COMPREPLY=($(compgen -W "on off" -- "$cur")) ;;
        plan)   COMPREPLY=($(compgen -f -- "$cur")) ;;
        *)      COMPREPLY=() ;;
    esac
}
complete -F _genesi_mesh genesi-mesh
