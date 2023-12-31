# UEFI + btrfs + Secure Boot + Unified Kernel Image + encrypted root

I'm just trying to make the original script from c0mpile and walian0 more friendly for myself and others.  It's just a learning experience for me right now.

Original description:

This script does a fully automated Arch Linux install with all of the features listed above. It uses a sane default layout for the btrfs subvolumes. This setup is designed to work perfectly with snapper for backup snapshots. Note that the snapshots cannot be booted from directly like they can with grub, so if that's what you're looking for then this setup isn't for you.

I've setup the script to automatically install hyprland but you can easily modify the packages list to suit your graphical environment needs.

Based off of https://github.com/walian0/bashscripts
