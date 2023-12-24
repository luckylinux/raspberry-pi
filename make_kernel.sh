#!/bin/sh

# Originally taken from https://github.com/luckylinux/rock-5b/blob/main/kernel/make_kernel.sh
# Itself being a modified version of https://github.com/inindev/rock-5b/blob/main/kernel/make_kernel.sh

set -e

# script exit codes:
#   1: missing utility
#   5: invalid file hash
#   7: use screen session
#   8: superuser disallowed

config_fixups() {
    local lpath=$1

    # enable rockchip sfc
    #echo 'CONFIG_SPI_ROCKCHIP_SFC=m' >> "$lpath/arch/arm64/configs/defconfig"

    # Avoid duplicated entries in case of multiple invocations of make_kernel.sh
    "./$lpath/scripts/config" --file "$lpath/arch/arm64/configs/defconfig" --module CONFIG_SPI_ROCKCHIP_SFC

    #echo 6 > "$lpath/.version"
}

config_features_after() {
    local lpath=$1

    # Look for all files in features-enabled folder
    # These files will need to act on .config directly since this function is called AFTER `make defconfig`
    for f in features-enabled/*.sh
    do
       echo "Processing <$f> feature ..."
       ./$f "$lpath" ".config"
    done
}

config_features_before() {
    local lpath=$1

    # Look for all files in features-enabled folder
    # These files will need to act on defconfig directly since this function is called BEFORE `make defconfig`
    for f in features-enabled/*.sh
    do
       echo "Processing <$f> feature ..."
       ./$f "$lpath" "arch/arm64/configs/defconfig"
    done
}

main() {
    # Mainline Branch 6.6.5
    local linux='https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.5.tar.xz'
    local lxsha='7c92795854a68d218c576097d50611f8eea86fd55810e0bc27724f020753b19e'

    # Mainline Branch 6.6.4
    #local linux='https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.4.tar.xz'
    #local lxsha='49e49660c93d8d6d58f118360d3ca8131695ec34669263ca8f041c876da93e45'

    # Mainline Branch 6.6.3
    #local linux='https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.3.tar.xz'
    #local lxsha='28edfc3d4f90cd738f2a20f5a2d68510268176d6111f6278d8f495edfd9495a7'

    # Mainline Branch 6.6.2
    #local linux='https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.6.2.tar.xz'
    #local lxsha='73d4f6ad8dd6ac2a41ed52c2928898b7c3f2519ed5dbdb11920209a36999b77e'

    # Mainline Branch 6.6.1
    #local linux='https://mirrors.edge.kernel.org/pub/linux/kernel/v6.x/linux-6.6.1.tar.xz'
    #local lxsha='da1ed7d47c97ed72c9354091628740aa3c40a3c9cd7382871f3cedbd60588234'

    # Mainline Branch 6.6.x Series
    #local linux='https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.tar.xz'
    #local lxsha='d926a06c63dd8ac7df3f86ee1ffc2ce2a3b81a2d168484e76b5b389aba8e56d0'

    # Stable Branch 6.5.x Series
    #local linux='https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.5.9.tar.xz'
    #local lxsha='c6662f64713f56bf30e009c32eac15536fad5fd1c02e8a3daf62a0dc2f058fd5'

    local lf="$(basename "$linux")"
    local lv="$(echo "$lf" | sed -nE 's/linux-(.*)\.tar\..z/\1/p')"

    if [ '_clean' = "_$1" ]; then
        echo "\n${h1}cleaning...${rst}"
        rm -fv *.deb
        rm -rfv kernel-$lv/*.deb
        rm -rfv kernel-$lv/*.buildinfo
        rm -rfv kernel-$lv/*.changes
        rm -rf "kernel-$lv/linux-$lv"
        echo '\nclean complete\n'
        exit 0
    fi

    check_installed 'screen' 'build-essential' 'python3' 'flex' 'bison' 'pahole' 'debhelper'  'bc' 'rsync' 'libncurses-dev' 'libelf-dev' 'libssl-dev' 'lz4' 'zstd'

    if [ -z $STY ] && [ -z $TMUX ]; then
        echo 'reminder: run from a screen or a tmux session, this can take a while...'
        exit 7
    fi

    mkdir -p "kernel-$lv"
    [ -f "kernel-$lv/$lf" ] || wget "$linux" -P "kernel-$lv"

    if [ "_$lxsha" != "_$(sha256sum "kernel-$lv/$lf" | cut -c1-64)" ]; then
        echo "invalid hash for linux source file: $lf"
        exit 5
    fi

    if [ ! -d "kernel-$lv/linux-$lv" ]; then
        tar -C "kernel-$lv" -xavf "kernel-$lv/$lf"

	# Copy defconfig to defconfig.default, so that we don't always re-add entries in case of multiple make_kernel.sh invocations
	cp "kernel-$lv/linux-$lv/arch/arm64/configs/defconfig" "kernel-$lv/linux-$lv/arch/arm64/configs/defconfig.default"

        for patch in patches/*.patch; do
            patch -p1 -d "kernel-$lv/linux-$lv" -i "../../$patch"
        done
    fi

    # build
    if [ '_inc' != "_$1" ]; then
        echo "\n${h1}configuring source tree...${rst}"
        make -C "kernel-$lv/linux-$lv" mrproper
        [ -z "$1" ] || echo "$1" > "kernel-$lv/linux-$lv/.version"

	# First of all restore default (as it shipped with kernel archive) defconfig
	cp "kernel-$lv/linux-$lv/arch/arm64/configs/defconfig.default" "kernel-$lv/linux-$lv/arch/arm64/configs/defconfig"

	# Start with custom config file
        cp "config-available/kernel-6.6.1-1" "kernel-$lv/linux-$lv/arch/arm64/configs/defconfig"
        #"./kernel-$lv/linux-$lv/scripts/config" --file "kernel-$lv/linux-$lv/arch/arm64/configs/defconfig" --module CONFIG_SPI_ROCKCHIP_SFC

	# Then apply required fixes to defconfig
        config_fixups "kernel-$lv/linux-$lv" "arch/arm64/configs/defconfig"

	# Then load (optional) features overriding kernel defaults "a priori"
        config_features_before "kernel-$lv/linux-$lv" "arch/arm64/configs/defconfig"

	# Then Generate Default Configuration
	make -C "kernel-$lv/linux-$lv" ARCH=arm64 defconfig

	# Use custom defconfig
	#wget https://gitlab.com/-/snippets/3622915/raw/main/docker_defconfig -O "kernel-$lv/linux-$lv/.config"
        #cp "config-available/kernel-6.6.1-1" "kernel-$lv/linux-$lv/.config"
        #"./kernel-$lv/linux-$lv/scripts/config" --file "kernel-$lv/linux-$lv/.config" --module CONFIG_SPI_ROCKCHIP_SFC
	#make -C "kernel-$lv/linux-$lv" ARCH=arm64 olddefconfig

	# Then load (optional) features overriding kernel defaults "a posteriori"
        #config_features_after "kernel-$lv/linux-$lv" ".config"
    fi

    echo "\n${h1}beginning compile...${rst}"
    rm -f linux-image-*.deb
    local kv="$(make --no-print-directory -C "kernel-$lv/linux-$lv" kernelversion)"
    local bv="$(expr "$(cat "kernel-$lv/linux-$lv/.version" 2>/dev/null || echo 0)" + 1 2>/dev/null)"
    export SOURCE_DATE_EPOCH="$(stat -c %Y "kernel-$lv/linux-$lv/README")"
    export KDEB_CHANGELOG_DIST='stable'
    export KBUILD_BUILD_TIMESTAMP="Debian $kv-$bv $(date -d @$SOURCE_DATE_EPOCH +'(%Y-%m-%d)')"
    export KBUILD_BUILD_HOST='github.com/inindev'
    export KBUILD_BUILD_USER='linux-kernel'
    export KBUILD_BUILD_VERSION="$bv"

    # Use generic "gcc" using readlink since "gcc-13" might not be available on some systems
    nice make -C "kernel-$lv/linux-$lv" -j"$(nproc)" CC="$(readlink /usr/bin/gcc)" bindeb-pkg KBUILD_IMAGE='arch/arm64/boot/Image' LOCALVERSION="-$bv-arm64"
    echo "\n${cya}kernel package ready${mag}"
    ln -sfv "kernel-$lv/linux-image-$kv-$bv-arm64_$kv-${bv}_arm64.deb"
    echo "${rst}"
}

check_installed() {
    local todo
    for item in "$@"; do
        dpkg -l "$item" 2>/dev/null | grep -q "ii  $item" || todo="$todo $item"
    done

    if [ ! -z "$todo" ]; then
        echo "this script requires the following packages:${bld}${yel}$todo${rst}"
        echo "   run: ${bld}${grn}sudo apt update && sudo apt -y install$todo${rst}\n"
        exit 1
    fi
}

rst='\033[m'
bld='\033[1m'
red='\033[31m'
grn='\033[32m'
yel='\033[33m'
blu='\033[34m'
mag='\033[35m'
cya='\033[36m'
h1="${blu}==>${rst} ${bld}"

if [ 0 -eq $(id -u) ]; then
    echo 'do not compile as root'
    exit 8
fi

cd "$(dirname "$(realpath "$0")")"
main "$@"

