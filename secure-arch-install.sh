#!/bin/bash
# uncomment to view debugging information
#set -xeuo pipefail

#check if we're root
if [[ "$UID" -ne 0 ]]; then
    echo "This script needs to be run as root!" >&2
    exit 3
fi

### Config options
target="/dev/nvme0n1"
locale="en_US.UTF-8"
keymap="us"
timezone="America/New_York"
hostname="laptop"
username="kevin"
#SHA512 hash of password. To generate, run 'mkpasswd -m sha-512', don't forget to prefix any $ symbols with \ . The entry below is the hash of 'password'
user_password="\$6\$/VBa6GuBiFiBmi6Q\$yNALrCViVtDDNjyGBsDG7IbnNR0Y/Tda5Uz8ToyxXXpw86XuCVAlhXlIvzy1M8O.DWFB6TRCia0hMuAJiXOZy/"

### Packages to pacstrap ##
pacstrappacs=(
        base
        base-devel
        linux
        linux-firmware
        amd-ucode
        pacman-contrib
        man-db
        vim
        nano
        cryptsetup
        util-linux
        e2fsprogs
        dosfstools
        btrfs-progs
        sudo
        openssh
        bash-completion
        networkmanager
        reflector
        )
### Desktop packages #####
guipacs=(
	hyprland
    dunst
    wofi
    xdg-desktop-portal-hyprland
    qt5-wayland
    qt6-wayland
    kitty
    dolphin
    seatd
	sddm
	firefox
	nm-connection-editor
	neofetch
 	sbctl
    pipewire
    pipewire-alsa
    pipewire-jack
    pipewire-pulse
    gst-plugin-pipewire
    libpulse
    wireplumber
	)

# Partition
if [[ $(echo $target | grep dev) =~ nvme ]]; then
        target_part1="${target}p1"
        target_part2="${target}p2"
else
        target_part1="${target}1"
        target_part2="${target}2"
fi

wipefs -af $target
sgdisk --zap-all --clear $target
sleep 2
partprobe $target
sleep 2

echo "Creating partitions..."
sgdisk -n 0:0:+512M -t 0:ef00 -c 0:esp $target
sgdisk -n 0:0:0 -t 0:8309 -c 0:luks $target

# Reload partition table
sleep 2
partprobe -s $target
sleep 2

echo "Encrypting root partition..."
#Encrypt the root partition. If badidea=yes, then pipe cryptpass and carry on, if not, prompt for it
cryptsetup luksFormat --type luks2 $target_part2 -
cryptsetup luksOpen $target_part2 crypt -

echo "Making File Systems..."
# Create file systems
mkfs.vfat -F32 -n EFISYSTEM $target_part1
mkfs.btrfs -L linux /dev/mapper/crypt

# mount the root, and create + mount the EFI directory
echo "Mounting File Systems..."
mount /dev/mapper/crypt /mnt

btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@srv
btrfs su cr /mnt/@snapshots
btrfs su cr /mnt/@log
btrfs su cr /mnt/@tmp
btrfs su cr /mnt/@cache
sleep 2
umount /mnt

subvol_options="rw,noatime,compress=zstd,space_cache=v2"
mount -o ${subvol_options},subvol=@ /dev/mapper/crypt /mnt
sleep 2
mkdir -p /mnt/{home,srv,.snapshots,var/log,var/tmp,var/cache,efi}
sleep 2

mount -o ${subvol_options},subvol=@home /dev/mapper/crypt /mnt/home
mount -o ${subvol_options},subvol=@srv /dev/mapper/crypt /mnt/srv
mount -o ${subvol_options},subvol=@snapshots /dev/mapper/crypt /mnt/.snapshots
mount -o ${subvol_options},subvol=@log /dev/mapper/crypt /mnt/var/log
mount -o ${subvol_options},subvol=@tmp /dev/mapper/crypt /mnt/var/tmp
mount -o ${subvol_options},subvol=@cache /dev/mapper/crypt /mnt/var/cache
mount ${target_part1} /mnt/efi

#Update pacman mirrors and then pacstrap base install
echo "Pacstrapping..."
sed -i -e '/^#ParallelDownloads = 5/s/^# //'

pacman-key --init
pacman-key --populate archlinux
pacman -Sy archlinux-keyring

reflector --country US --age 24 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
pacstrap -K /mnt "${pacstrappacs[@]}"

# needs fstab because DPS doesn't support btrfs subvolume discovery
genfstab -U -p /mnt >> /mnt/etc/fstab

echo "Setting up environment..."
#set up locale/env
#add our locale to locale.gen
sed -i -e "/^#"$locale"/s/^#//" /mnt/etc/locale.gen
#remove any existing config files that may have been pacstrapped, systemd-firstboot will then regenerate them
rm /mnt/etc/{machine-id,localtime,hostname,shadow,locale.conf} ||
systemd-firstboot --root /mnt \
	--keymap="$keymap" --locale="$locale" \
	--locale-messages="$locale" --timezone="$timezone" \
	--hostname="$hostname" --setup-machine-id \
	--welcome=false
arch-chroot /mnt locale-gen
echo "Configuring for first boot..."
#add the local user
arch-chroot /mnt useradd -G wheel -m -p "$user_password" "$username"
#uncomment the wheel group in the sudoers file
sed -i -e '/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/s/^# //' /mnt/etc/sudoers
#create a basic kernel cmdline, we're using DPS so we don't need to have anything here really, but if the file doesn't exist, mkinitcpio will complain
echo "quiet rw" > /mnt/etc/kernel/cmdline
#change the HOOKS in mkinitcpio.conf to use systemd hooks
sed -i \
    -e 's/base udev/base systemd/g' \
    -e 's/keymap consolefont/sd-vconsole sd-encrypt/g' \
    /mnt/etc/mkinitcpio.conf
#change the preset file to generate a Unified Kernel Image instead of an initram disk + kernel
sed -i \
    -e '/^#ALL_config/s/^#//' \
    -e '/^#default_uki/s/^#//' \
    -e '/^#default_options/s/^#//' \
    -e 's/default_image=/#default_image=/g' \
    -e "s/PRESETS=('default' 'fallback')/PRESETS=('default')/g" \
    /mnt/etc/mkinitcpio.d/linux.preset

#read the UKI setting and create the folder structure otherwise mkinitcpio will crash
declare $(grep default_uki /mnt/etc/mkinitcpio.d/linux.preset)
arch-chroot /mnt mkdir -p "$(dirname "${default_uki//\"}")"

#install the gui packages
echo "Installing GUI..."
arch-chroot /mnt pacman -Sy "${guipacs[@]}" --noconfirm --quiet


#enable the services we will need on start up
echo "Enabling services..."
systemctl --root /mnt enable systemd-resolved systemd-timesyncd NetworkManager sddm
#mask systemd-networkd as we will use NetworkManager instead
systemctl --root /mnt mask systemd-networkd
#regenerate the ramdisk, this will create our UKI
echo "Generating UKI and installing Boot Loader..."
arch-chroot /mnt mkinitcpio -p linux
echo "Setting up Secure Boot..."
if [[ "$(efivar -d --name 8be4df61-93ca-11d2-aa0d-00e098032b8c-SetupMode)" -eq 1 ]]; then
arch-chroot /mnt sbctl create-keys
arch-chroot /mnt sbctl enroll-keys -m
arch-chroot /mnt sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot /mnt sbctl sign -s "${default_uki//\"}"
else
echo "Not in Secure Boot setup mode. Skipping..."
fi
#install the systemd-boot bootloader
arch-chroot /mnt bootctl install --esp-path=/efi
#lock the root account
arch-chroot /mnt usermod -L root
#and we're done


echo "-----------------------------------"
echo "- Install complete. Rebooting.... -"
echo "-----------------------------------"
sleep 10
sync
reboot


