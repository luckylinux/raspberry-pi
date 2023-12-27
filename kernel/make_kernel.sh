#!/bin/bash

# Abort on error
#set -e

# Install requirements (common with ZFS)
sudo apt-get -y --no-install-recommends install dkms
sudo apt-get -y install dh-dkms
sudo apt-get -y install aptitude libcurl4-openssl-dev libpam0g-dev lsb-release build-essential autoconf automake libtool libblkid-dev uuid-dev libudev-dev libssl-dev zlib1g-dev libaio-dev libattr1-dev libelf-dev python3 python3-dev python3-setuptools python3-cffi libffi-dev python3-packaging git libcurl4-openssl-dev debhelper-compat dh-python po-debconf python3-all-dev python3-sphinx
sudo apt-get -y install build-essential autoconf automake libtool gawk fakeroot libblkid-dev uuid-dev libudev-dev libssl-dev zlib1g-dev libaio-dev libattr1-dev libelf-dev python3 python3-dev python3-setuptools python3-cffi libffi-dev python3-packaging git libcurl4-openssl-dev debhelper-compat dh-python po-debconf python3-all-dev python3-sphinx
sudo apt-get -y install git flex bc bison

# Define version
lv="6.6.y"
tag="rpi-$lv"

# Generate timestamp
timestamp=$(date +%Y%m%d-%H-%M)

# Download Kernel Sources from Raspberry PI Linux Kernel Repository
mkdir -p kernel-$lv

if [ ! -d "kernel-$lv/linux-$lv" ]; then
   git clone --depth=1 --branch $tag https://github.com/raspberrypi/linux kernel-$lv/linux-$lv
fi

# Configure
KERNEL=kernel8
make -C "kernel-$lv/linux-$lv" ARCH=arm64 bcm2711_defconfig

# Get version
######krelease=$(cat kernel-$lv/linux-$lv/include/config/kernel.release)
krelease=$(make -s -C "kernel-$lv/linux-$lv" kernelrelease)
#krelease="6.6.8-v8+"

# Set custom version
sed -Ei "s|^CONFIG_LOCALVERSION=\".*\"|CONFIG_LOCALVERSION=\"$localversion\"|g" "kernel-$lv/linux-$lv/.config"
######echo "CONFIG_LOCALVERSION=\"\"" >> kernel-$lv/linux-$lv/.config

# Set local version
customversion="-custom"
localversion="-v8$customversion"

# Set kernel source destination
#ksource="/usr/src/linux-$krelease$localversion"
ksource="/usr/src/linux-$krelease$customversion"

if [ -d "$ksource" ]; then
    mv "$ksource" "$ksource-$timestamp"
fi

# Move Everything to /usr/src before starting
mv "kernel-$lv/linux-$lv" "$ksource"

# Reconfigure
make -C "$ksource" ARCH=arm64 bcm2711_defconfig

# Set custom version again
sed -Ei "s|^CONFIG_LOCALVERSION=\".*\"|CONFIG_LOCALVERSION=\"$localversion\"|g" "$ksource/.config"

echo "ksource = $ksource"
echo "krelease = $krelease"

# Compile
######make -j4 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- Image modules dtbs
######make -C "kernel-$lv/linux-$lv" ARCH=arm64 -j4 zImage modules dtbs
#####make -C "kernel-$lv/linux-$lv" ARCH=arm64 -j4 Image.gz modules dtbs
#####make -C "kernel-$lv/linux-$lv" ARCH=arm64 -j4 Image modules dtbs
make -C "$ksource" ARCH=arm64 -j4 Image modules dtbs

# Backup old kernel
mkdir -p /boot/_backup
#cp /boot/$KERNEL.img /boot/_backup/$KERNEL-backup-$timestamp.img

# Install kernel
#####cp kernel-$lv/linux-$lv/arch/arm64/boot/Image /boot/$KERNEL-$krelease.img
#####cp kernel-$lv/linux-$lv/arch/arm64/boot/dts/broadcom/*.dtb /boot/
#####cp kernel-$lv/linux-$lv/arch/arm64/boot/dts/overlays/*.dtb* /boot/overlays/
#####cp kernel-$lv/linux-$lv/arch/arm64/boot/dts/overlays/README /boot/overlays/
cp $ksource/arch/arm64/boot/Image /boot/$KERNEL-$krelease$customversion.img
cp $ksource/arch/arm64/boot/dts/broadcom/*.dtb /boot/
cp $ksource/arch/arm64/boot/dts/overlays/*.dtb* /boot/overlays/
cp $ksource/arch/arm64/boot/dts/overlays/README /boot/overlays/

mkdir -p /boot/firmware
cp $ksource/arch/arm64/boot/Image /boot/firmware/$KERNEL-$krelease$customversion.img
cp $ksource/arch/arm64/boot/dts/broadcom/*.dtb /boot/firmware/
cp $ksource/arch/arm64/boot/dts/overlays/*.dtb* /boot/firmware/overlays/
cp $ksource/arch/arm64/boot/dts/overlays/README /boot/firmware/overlays/

# Install modules
make -C "$ksource" modules_install

# Copy .config to /boot
# /boot/config-6.6.8-v8-custom+ ia how it should look like when
#     ksource = /usr/src/linux-6.6.8-v8+-custom
#     krelease = 6.6.8-v8+

kstring=${krelease/"-v8"/"${localversion}"}
cp $ksource/.config /boot/config-$kstring

kstring=${kstring/"-v8-custom+"/"-v8+-custom"}
cp $ksource/.config /boot/config-$kstring

# Force DKMS Update
dkms autoinstall -k $krelease$customversion

# Generate initramfs
update-initramfs -k $krelease$customversion -u

