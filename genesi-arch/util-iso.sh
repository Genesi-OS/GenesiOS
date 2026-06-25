#!/bin/bash
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

error_function() {
    if [[ -p $logpipe ]]; then
        rm "$logpipe"
    fi
    # first exit all subshells, then print the error
    if (( ! BASH_SUBSHELL )); then
        error "A failure occurred in %s()." "$1"
        plain "Aborting..."
    fi
    umount_fs
    umount_img
    exit 2
}

run_safe() {
    local restoretrap func="$1"
    set -e
    set -E
    restoretrap=$(trap -p ERR)
    trap 'error_function $func' ERR

    if ${verbose}; then
        run_log "$func"
    else
        "$func"
    fi

    eval $restoretrap
    set +E
    set +e
}

check_umount() {
    if mountpoint -q "$1"; then
        umount -l "$1"
    fi
}

trap_exit() {
    local sig=$1; shift
    error "$@"
    umount_fs
    trap -- "$sig"
    kill "-$sig" "$$"
}

generate_motd() {
    cat << 'EOF' > ${src_dir}/archiso/airootfs/etc/motd
This ISO is based on Arch Linux and CachyOS technologies, built for [38;2;29;158;117mGenesi OS[0m.
https://github.com/Genesi-OS/GenesiOS

[38;2;29;158;117mGenesi OS[0m uses CachyOS optimized packages and kernel.
Calamares is used as GUI installer.

Live environment will start now and let you install [38;2;29;158;117mGenesi OS[0m to disk.

Welcome to [38;2;29;158;117mGenesi OS[0m!
EOF
}

fetch_cachyos_mirrorlist() {
    mkdir -p ${src_dir}/archiso/airootfs/etc/pacman.d
    local _mirrorlist_url="https://github.com/CachyOS/CachyOS-PKGBUILDS/raw/master/cachyos-mirrorlist/cachyos-mirrorlist"

    curl -sSL "${_mirrorlist_url}" > ${src_dir}/archiso/airootfs/etc/pacman.d/cachyos-mirrorlist
}

change_grub_version() {
    local _version="$1"
    sed -i "s/GENESI_VERSION=\".*\"/GENESI_VERSION=\"${_version}\"/" ${src_dir}/archiso/grub/grub.cfg
}

generate_environment() {
    local _profile="$1"
    if [ "$_profile" == "desktop" ]; then
        cat << 'EOF' > ${src_dir}/archiso/airootfs/etc/environment
ZPOOL_VDEV_NAME_PATH=1
EOF
    fi
}

generate_version_tag() {
    local _profile="$1"
    local _version="$2"
    if [ "$_profile" == "desktop" ]; then
        echo "${_version}" > ${src_dir}/archiso/airootfs/etc/version-tag
    fi
}

generate_edition_tag() {
    local _edition="$1"
    echo "${_edition}" > ${src_dir}/archiso/airootfs/etc/edition-tag
}

modify_mkarchiso() {
    local _is_hack_applied="$(grep -q 'archlinux-keyring-wkd-sync.timer' /usr/bin/mkarchiso; echo $?)"
    if [ $_is_hack_applied -ne 0 ]; then
        msg "Patching mkarchiso with disabled arch keyrings timer..."

        sudo sed 's/_run_once _make_customize_airootfs/_run_once _make_customize_airootfs\n\trm -f "${pacstrap_dir}\/usr\/lib\/systemd\/system\/timers.target.wants\/archlinux-keyring-wkd-sync.timer"\n/' -i /usr/bin/mkarchiso
    else
        msg "mkarchiso is already patched!"
    fi

    # Ensure mkarchiso actually calls _make_customize_airootfs
    # Some versions skip it. Verify it's in the build flow.
    local _has_customize="$(grep -c '_make_customize_airootfs' /usr/bin/mkarchiso)"
    if [ "$_has_customize" -gt 0 ]; then
        msg "mkarchiso has customize_airootfs support ($_has_customize references)"
    else
        warning "mkarchiso does NOT have customize_airootfs support!"
    fi

    # Ensure the _make_customize_airootfs function actually runs the script
    # by checking if it's called in the main build flow
    local _is_called="$(grep -c '_run_once _make_customize_airootfs' /usr/bin/mkarchiso)"
    msg "customize_airootfs is called $_is_called time(s) in mkarchiso"
}

# Run customize_airootfs.sh manually inside the chroot after mkarchiso
# installs packages. This ensures our branding overrides CachyOS packages.
run_customize_airootfs() {
    local _airootfs="${work_dir}/x86_64/airootfs"
    local _script="${_airootfs}/root/customize_airootfs.sh"

    if [ -f "$_script" ]; then
        msg "Running Genesi OS customize_airootfs.sh in chroot..."
        sudo chmod +x "$_script"
        sudo arch-chroot "$_airootfs" /root/customize_airootfs.sh
        msg "Genesi OS customization complete!"
    else
        warning "customize_airootfs.sh not found at $_script"
    fi
}

prepare_profile(){
    profile=$1

    info "Profile: [%s]" "${profile}"

    # SOURCE_DATE_EPOCH locked at buildiso.sh start so this matches whatever
    # gen_iso_fn / mkarchiso's profiledef.sh compute, even across midnight.
    local _iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%y%m%d)"
    change_grub_version "${_iso_version}"

    # Fetch up-to-date version of CachyOS repo mirrorlist
    fetch_cachyos_mirrorlist

    generate_motd

    rm -f ${src_dir}/archiso/airootfs/etc/systemd/system/display-manager.service
    if [ "$profile" == "desktop" ]; then
        cp ${src_dir}/archiso/packages_desktop.x86_64 ${src_dir}/archiso/packages.x86_64
        ln -sf /usr/lib/systemd/system/plasmalogin.service ${src_dir}/archiso/airootfs/etc/systemd/system/display-manager.service
        # Fix default.target - must be a real symlink, not a text file
        rm -f ${src_dir}/archiso/airootfs/etc/systemd/system/default.target
        ln -sf /usr/lib/systemd/system/graphical.target ${src_dir}/archiso/airootfs/etc/systemd/system/default.target
        # Enable Genesi OS branding service
        mkdir -p ${src_dir}/archiso/airootfs/etc/systemd/system/multi-user.target.wants
        ln -sf /etc/systemd/system/genesi-branding.service ${src_dir}/archiso/airootfs/etc/systemd/system/multi-user.target.wants/genesi-branding.service
    else
        die "Unknown profile: [%s]" "${profile}"
    fi

    generate_environment "${profile}"

    # Write out version to be able to check ISO version
    generate_version_tag "${profile}" "${_iso_version}"

    # Write out edition to be able to check ISO edition
    generate_edition_tag "${profile}"

    iso_file=$(gen_iso_fn).iso
}

run_build() {
    prepare_profile "$1"
    local _profile="$1"

    msg "Prepare [work: ${work_dir}, out: ${outFolder}]"

    if $verbose; then
        msg2 "Making mkarchiso verbose"
        sudo sed -i 's/quiet="y"/quiet="n"/g' /usr/bin/mkarchiso
    fi

    if $clean_first; then
        msg2 "Deleting the build folder if one exists - takes some time"
        umount_fs
        [ -d ${work_dir} ] && sudo rm -rf ${work_dir}
    fi

    msg2 "Copying the Archiso folder to build work"
    mkdir -p ${work_dir}
    cp -r archiso ${work_dir}/archiso

    msg "Start [Build ISO]"

    # insert removal of archlinux keyrings timer on the ISO before pack
    modify_mkarchiso

    [ -d "$outFolder/$_profile" ] || mkdir -p "$outFolder/$_profile"
    cd ${work_dir}/archiso/
    # `sudo` strips the env by default, so SOURCE_DATE_EPOCH would not survive
    # into mkarchiso -> profiledef.sh -> the output filename. Pass it inline
    # (sudo preserves vars set on the command line for the target program).
    sudo SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH}" mkarchiso -v -w ${work_dir} -o "$outFolder/$_profile" ${work_dir}/archiso/

    sudo chown $USER $outFolder

    cp ${work_dir}/iso/arch/pkglist.x86_64.txt "$outFolder/$_profile/$(gen_iso_fn).pkgs.txt"
    mv "$outFolder/$_profile/genesi-$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)-x86_64.iso" "$outFolder/$_profile/${iso_file}"

    msg "Done [Build ISO] ${iso_file}"
    msg "Finished building [%s]" "${_profile}"

    cd "$outFolder/$_profile"
    for f in $(find . -maxdepth 1 -name '*.iso' | cut -d'/' -f2); do
        if [[ ! -e $f.sha256 ]]; then
            create_chksums $f
        elif [[ $f -nt $f.sha256 ]]; then
            create_chksums $f
        else
            info "checksums for [$f] already created"
        fi
        if [[ ! -e $f.sig ]]; then
            sign_with_key $f
        elif [[ $f -nt $f.sig ]]; then
            rm $f.sig
            sign_with_key $f
        else
            info "signature file for [$f] already created"
        fi
    done
    show_elapsed_time "${FUNCNAME}" "${timer_start}"
    if [[ "$build_in_ram" == "true" && "$remove_build_dir" == "false" ]]; then
        msg "!!! Remember to remove $work_dir !!!"
        msg2 "sudo rm -rf $work_dir"
    fi
    if [[ "$remove_build_dir" == "true" ]]; then
        msg "Automatically removing build directory ($work_dir)..."
        umount_fs
        [ -d ${work_dir} ] && sudo rm -rf ${work_dir}
        msg2 "Removed"
    fi
}

gen_iso_fn(){
    local vars=() name
    vars+=("genesi")
    [[ -n ${profile} ]] && vars+=("${profile}")

    vars+=("linux")
    # Use SOURCE_DATE_EPOCH so the pretty filename matches mkarchiso's output
    # even when the build crosses midnight (see buildiso.sh header).
    vars+=("$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%y%m%d)")

    for n in ${vars[@]}; do
        name=${name:-}${name:+-}${n}
    done

    echo $name
}
