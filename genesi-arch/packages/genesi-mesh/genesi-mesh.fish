# Completions for genesi-mesh.
#
# These exist for a concrete reason: `genesi-mesh` is a PREFIX of the daemon
# `genesi-meshd`, so without completions fish turns `genesi-mesh <TAB>` into
# `genesi-meshd` -- the daemon, which then sits in its main loop and looks like
# a hang. Defining subcommands makes Tab offer those instead of renaming the
# binary out from under the user.
complete -c genesi-mesh -f
complete -c genesi-mesh -n __fish_use_subcommand -a status      -d 'This node and who it can see'
complete -c genesi-mesh -n __fish_use_subcommand -a peers       -d 'Live peer table'
complete -c genesi-mesh -n __fish_use_subcommand -a init        -d 'Start a new mesh here (root)'
complete -c genesi-mesh -n __fish_use_subcommand -a show-secret -d 'Print this mesh secret (root)'
complete -c genesi-mesh -n __fish_use_subcommand -a join        -d 'Join an existing mesh (root)'
complete -c genesi-mesh -n __fish_use_subcommand -a peer        -d 'Add a peer reachable over VPN (root)'
complete -c genesi-mesh -n __fish_use_subcommand -a worker      -d 'Share this GPU\'s VRAM on/off (root)'
complete -c genesi-mesh -n __fish_use_subcommand -a serve       -d 'Share this machine\'s Turbo on/off (root)'
complete -c genesi-mesh -n __fish_use_subcommand -a plan        -d 'Would pooling help for a model?'
complete -c genesi-mesh -n __fish_use_subcommand -a selftest    -d 'Prove the RPC path works here'
complete -c genesi-mesh -n __fish_use_subcommand -a doctor      -d 'Check prerequisites'
complete -c genesi-mesh -n '__fish_seen_subcommand_from worker' -a 'on off'
complete -c genesi-mesh -n '__fish_seen_subcommand_from serve' -a 'on off'
