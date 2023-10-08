# UEFI + btrfs + Secure Boot + Unified Kernel Image + encrypted root

This script does a fully automated Arch Linux install with all of the features listed above. It uses a sane default layout for the btrfs subvolumes. This setup is designed to work perfectly with snapper for backup snapshots. Note that the snapshots cannot be booted from directly like they can with grub, so if that's what you're looking for then this setup isn't for you.

I've setup the script to automatically install qtile window manager but you can easily modify the packages list to suit your needs.

Based off of https://github.com/walian0/bashscripts
