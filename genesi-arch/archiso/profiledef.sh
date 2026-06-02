#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="genesi"
iso_label="GENESI_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Genesi OS <https://github.com/zFreshy/GenesiOS>"
iso_application="Genesi OS Live/Install DVD"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="arch"
buildmodes=('iso')
## GRUB
bootmodes=('bios.syslinux' 'uefi.grub')
## systemd-boot
#bootmodes=('bios.syslinux' 'uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd decompresses far faster than xz, which matters a lot for the live boot and
# app launches off slow media (USB/Ventoy). xz was the main cause of multi-minute
# boots and apps taking minutes to open on real hardware (fine in a VM off SSD).
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '19' '-b' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/etc/polkit-1/rules.d"]="0:0:750"
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/g_wheel"]="0:0:440"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/root/customize_airootfs_genesi.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/dmcheck"]="0:0:755"
  ["/usr/local/bin/calamares-online.sh"]="0:0:755"
  ["/usr/local/bin/remove-nvidia"]="0:0:755"
  ["/usr/local/bin/removeun"]="0:0:755"
  ["/usr/local/bin/removeun-online"]="0:0:755"
  ["/usr/local/bin/prepare-live-desktop.sh"]="0:0:755"
  ["/usr/local/bin/nvidia-module-loader"]="0:0:755"
  ["/usr/local/bin/pkexec-wrapper"]="0:0:755"
  ["/usr/local/bin/genesi-branding.sh"]="0:0:755"
  ["/usr/local/bin/genesi-welcome"]="0:0:755"
  ["/usr/local/bin/genesi-aid"]="0:0:755"
  ["/usr/local/bin/genesi-add-aimode-widget.sh"]="0:0:755"
)
