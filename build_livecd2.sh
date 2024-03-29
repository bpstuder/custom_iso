#!/bin/bash

# MY_PATH="`dirname \"$0\"`"              # relative
# SCRIPT_PATH="$( (cd \"$SCRIPT_PATH\" && pwd))" # absolutized and normalized
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
if [ -z "$SCRIPT_PATH" ]; then
    # error; for some reason, the path is not accessible
    # to the script (e.g. permissions re-evaled after suid)
    exit 1 # fail
fi
echo "## Running script from $SCRIPT_PATH ##"

# FLAVOUR=$(echo ${1} | tr '[:upper:]' '[:lower:]')
CONFIG_FILE=${SCRIPT_PATH}/${1}
echo "## Using ${CONFIG_FILE} ##"

echo "## Installing prerequisites ##"
sudo apt-get -qq install \
    squashfs-tools \
    schroot \
    genisoimage \
    xorriso \
    jq \
    curl \
    tree
echo ">> Done"

echo "## Checking config file presence ##"
if [[ -f ${CONFIG_FILE} ]]; then
    echo "Parsing config file"
    JSON=$(cat ${CONFIG_FILE} | jq)
    #handle error here
    FLAVOUR=$(echo ${JSON} | jq -r '.flavour')
    FLAVOUR=$(echo ${FLAVOUR} | tr '[:upper:]' '[:lower:]')
    OUTPUT_ISO=$(echo ${JSON} | jq -r '.output_iso')
    echo "Output iso : ${OUTPUT_ISO}"
    OUTPUT_VOLUME=$(echo ${JSON} | jq -r '.output_volume')
    echo "Output Volume : ${OUTPUT_VOLUME}"

    # readarray -t FILES_ORIGIN < <(jq -r '.additional_files[].origin_path' ${CONFIG_FILE})
    # readarray -t FILES_TARGET < <(jq -r '.additional_files[].target_path' ${CONFIG_FILE})
    # readarray -t FILES_DESCRIPTION < <(jq -r '.additional_files[].description' ${CONFIG_FILE})

    # printf '%s\n' "${FILES_DESCRIPTION[@]}"

    # i=0
    # for FILES in "${FILES_DESCRIPTION[@]}"; do
    #     echo "Processing $FILES"

    #     ((i++))
    # done
else
    echo "Config file not found"
    exit 1
fi

# exit

if [[ ! -d $SCRIPT_PATH/livecd-${FLAVOUR} ]]; then
    echo "Creating folders"
    mkdir $SCRIPT_PATH/livecd-${FLAVOUR}
    cd $SCRIPT_PATH/livecd-${FLAVOUR}
    mkdir iso squashfs out boot
    echo ">> Done"
fi

case $FLAVOUR in
ubuntu)
    echo "Ubuntu flavour selected"
    ISO_NAME="ubuntu-22.04.1-desktop-amd64.iso"
    ISO_URL="https://releases.ubuntu.com/jammy/ubuntu-22.04.1-desktop-amd64.iso"
    ;;
kubuntu)
    echo "Kubuntu flavour selected"
    ISO_NAME="kubuntu-22.04.1-desktop-amd64.iso"
    ISO_URL="https://cdimage.ubuntu.com/kubuntu/releases/22.04.1/release/kubuntu-22.04.1-desktop-amd64.iso"
    ;;
xubuntu)
    echo "Xubuntu flavour selected"
    ISO_NAME="xubuntu-22.04.1-desktop-amd64.iso"
    ISO_URL="https://cdimage.ubuntu.com/xubuntu/releases/22.04.1/release/xubuntu-22.04.1-desktop-amd64.iso"
    ;;
lubuntu)
    echo "Lubuntu flavour selected"
    ISO_NAME="lubuntu-22.04.1-desktop-amd64.iso"
    ISO_URL="https://cdimage.ubuntu.com/lubuntu/releases/22.04.1/release/lubuntu-22.04.1-desktop-amd64.iso"
    ;;
budgie)
    echo "Budgie flavour selected"
    ISO_NAME="ubuntu-budgie-22.04.1-desktop-amd64.iso"
    ISO_URL="https://cdimage.ubuntu.com/ubuntu-budgie/releases/22.04.1/release/ubuntu-budgie-22.04.1-desktop-amd64.iso"
    ;;
*)
    echo "Please select between Ubuntu, Kubuntu, Xubuntu, Lubuntu, Budgie"
    exit
    ;;
esac

cd $SCRIPT_PATH/livecd-${FLAVOUR}

echo "## Checking if iso is present ##"
if [[ ! -f ${ISO_NAME} ]]; then
    echo "Downloading..."
    wget -q ${ISO_URL}
    echo ">> Done"
    echo "Mounting ISO"
    sudo mount -o loop ${ISO_NAME} /mnt
    echo "Copying files"
    sudo cp -a /mnt/. iso
    echo "Extracting Boot image"
    dd if=${ISO_NAME} bs=1 count=432 of=boot/boot_hybrid.img
    echo "Extracting EFI image"
    dd if=${ISO_NAME} bs=512 skip=7129428 count=8496 of=boot/efi.img
    echo "Unmounting ISO"
    sudo umount /mnt
    echo "Mounting squashfs"
    sudo mount -t squashfs -o loop iso/casper/filesystem.squashfs /mnt
    echo "Copying squashfs"
    sudo cp -a /mnt/. squashfs
    echo "Unmounting squashfs"
    sudo umount /mnt

fi

echo "## Preparing system for modification ##"
sudo mount --bind /proc squashfs/proc
sudo mount --bind /sys squashfs/sys
sudo mount -t devpts none squashfs/dev/pts
# sudo mount --bind /dev squashfs/dev
# sudo mount --bind /dev/pts squashfs/dev/pts

echo "## Updating resolv.conf for network resolution ##"
sudo cp /etc/resolv.conf squashfs/etc/resolv.conf
# sudo cp /etc/apt/sources.list squashfs/etc/apt/sources.list

echo ${JSON} | sudo tee squashfs/tmp/config.json > /dev/null

echo "## Listing files to copy ##"
FILES_TO_COPY=($(find "$SCRIPT_PATH/files" -type f -print))

for FILE in "${FILES_TO_COPY[@]}"; do
    fullPath=${FILE#$SCRIPT_PATH/files/}
    targetPath="squashfs/$(dirname $fullPath)"
    echo "Processing $fullPath"
    if [[ ! -d ${targetPath} ]]; then
        echo "Creating directory ${targetPath}"
        mkdir -p ${targetPath}
    fi
    echo "Copying to ${targetPath}"
    cp -rf ${FILE} ${targetPath}
done
echo ">> Done"

echo "## Listing packages to copy ##"
PACKAGES_TO_COPY=($(find "$SCRIPT_PATH/packages" -type f -print))

for PKG in "${PACKAGES_TO_COPY[@]}"; do
    fullPath=${PKG}
    targetPath="squashfs/tmp/${PKG##*/}"
    echo "Processing $fullPath"
    echo "Copying to $targetPath"
    # mkdir -p ${targetPath}
    cp -rf ${PKG} ${targetPath}
done
echo ">> Done"

echo "Entering chroot"
sudo chroot squashfs /usr/bin/bash <<"EOT"


add-apt-repository universe > /dev/null
add-apt-repository multiverse > /dev/null
apt-get -qq update

dpkg --configure -a
apt-get -qq dist-upgrade
apt-get -qq install -y curl jq whois

CONFIG_FILE="/tmp/config.json"

readarray -t REPOSITORIES_NAME < <(jq -r '.repositories[].name' ${CONFIG_FILE})
readarray -t REPOSITORIES_GPG < <(jq -r '.repositories[].gpg_signature' ${CONFIG_FILE})
readarray -t REPOSITORIES_URL < <(jq -r '.repositories[].url' ${CONFIG_FILE})
readarray -t REPOSITORIES_LIST < <(jq -r '.repositories[].list_file' ${CONFIG_FILE})

readarray -t PACKAGES_APT < <(jq --arg type "apt" -r '.packages[] | select(.type == $type).name' ${CONFIG_FILE})
readarray -t PACKAGES_SNAP < <(jq --arg type "snap" -r '.packages[] | select(.type == $type).name' ${CONFIG_FILE})

echo "Adding repositories"
i=0
for REPOSITORY in ${REPOSITORIES_NAME[@]}; do
    REPOSITORY=$(echo $REPOSITORY | tr '[:upper:]' '[:lower:]')
    echo "Processing $REPOSITORY"
    
    echo "Adding GPG"
    wget -O- ${REPOSITORIES_GPG[$i]} | gpg --dearmor | tee /usr/share/keyrings/$REPOSITORY-archive-keyring.gpg
    echo ">> Done"

    echo "Adding repository"
    echo ${REPOSITORIES_URL[$i]} | tee "/etc/apt/sources.list.d/${REPOSITORIES_LIST[$i]}" > /dev/null
    echo ">> Done"
    ((i++))
done

apt-get -qq autoremove
apt-get -qq autoclean
echo ">> Done"

echo "Installing APT packages"
i=0
for PACKAGE_APT in ${PACKAGES_APT[@]}; do
    echo "Processing $PACKAGE_APT"
    apt-get -qq install -y $PACKAGE_APT
    echo ">> Done"
    ((i++))
done
echo ">> Done"

echo "Installing Snap packages"
i=0
for PACKAGE_SNAP in ${PACKAGES_SNAP[@]}; do
    echo "Processing $PACKAGE_SNAP"
    apt-get -qq install -y $PACKAGE_SNAP
    echo ">> Done"
    ((i++))
done
echo ">> Done"

echo "Installing local packages"
apt-get -qq install -y /tmp/*.deb
echo ">> Done"

echo "Cleaning packages"
apt-get clean
echo ">> Done"

# echo "Deleting crash log"
# rm -r /var/crash/*

echo "Updating Grub"
update-grub
echo ">> Done"

echo "Exiting chroot"
# umount -lf /sys
# umount -lf /proc
# umount -lf /dev/pts
# umount -lf /dev
# rm /etc/resolv.conf
# rm /etc/hosts
exit
EOT
echo "Exited chroot"

echo "Cleaning"
sudo umount ./squashfs/proc
sudo umount ./squashfs/sys
sudo umount ./squashfs/dev/pts
echo ">> Done"

echo "Generating new manifest"
sudo chmod a+w iso/casper/filesystem.manifest
sudo chroot squashfs dpkg-query -W --showformat='${Package}  ${Version}\n' >iso/casper/filesystem.manifest
sudo chmod go-w iso/casper/filesystem.manifest
echo ">> Done"

echo "Removing old squashfs"
sudo rm iso/casper/filesystem.squashfs
echo ">> Done"

echo "Creating the new squashfs"
cd squashfs
sudo mksquashfs . ../iso/casper/filesystem.squashfs >/dev/null #-info
cd ..
echo ">> Done"

echo "Generating new ISO"
cd iso
sudo bash -c "find . -path ./isolinux -prune -o -type f -not -name md5sum.txt -print0 | xargs -0 md5sum | tee md5sum.txt" >/dev/null
echo ">> Done"

# echo "Generating disk image"
# sudo genisoimage -o "Custom.iso" -r -J -no-emul-boot -V "USB_LINUX" -boot-load-size 4 -boot-info-table -b isolinux/isolinux.bin -c isolinux/boot.cat ./
# sudo xorriso -as mkisofs -r -V "${OUTPUT_VOLUME}" \
#              -cache-inodes -J -l \
#              -c isolinux/boot.cat \
#              -b isolinux/isolinux.bin \
#                 -no-emul-boot -boot-load-size 4 -boot-info-table \
#              -eltorito-alt-boot \
#              -e boot/grub/efi.img \
#                 -no-emul-boot -isohybrid-gpt-basdat \
#              -o $SCRIPT_PATH/livecd-${FLAVOUR}/out/${OUTPUT_ISO} ./

echo "Copying boot img"
dd if=$SCRIPT_PATH/livecd-${FLAVOUR}/${ISO_NAME} bs=1 count=432 of=$SCRIPT_PATH/livecd-${FLAVOUR}/boot/boot_hybrid.img

echo "Copying EFI img"
dd if=$SCRIPT_PATH/livecd-${FLAVOUR}/${ISO_NAME} bs=512 skip=7129428 count=8496 of=$SCRIPT_PATH/livecd-${FLAVOUR}/boot/efi.img

echo "Generating ISO"
# sudo xorriso -as mkisofs -r \
#     -V "${OUTPUT_VOLUME}" \
#     -o $SCRIPT_PATH/livecd-${FLAVOUR}/out/${OUTPUT_ISO} \
#     --grub2-mbr $SCRIPT_PATH/livecd-${FLAVOUR}/boot/boot_hybrid.img \
#     -partition_offset 16 \
#     --mbr-force-bootable \
#     -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b $SCRIPT_PATH/livecd-${FLAVOUR}/boot/efi.img \
#     -appended_part_as_gpt \
#     -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
#     -c '/boot.catalog' \
#     -b '/boot/grub/i386-pc/eltorito.img' \
#     -no-emul-boot -boot-load-size 4 -boot-info-table --grub2-boot-info \
#     -eltorito-alt-boot \
#     -e '--interval:appended_partition_2:::' \
#     -no-emul-boot \
#     ./

# sudo xorriso -indev $SCRIPT_PATH/livecd-${FLAVOUR}/${ISO_NAME} -report_el_torito as_mkisofs \
sudo xorriso -report_el_torito as_mkisofs \
    -V "${OUTPUT_VOLUME}" \
    --grub2-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:"$SCRIPT_PATH/livecd-${FLAVOUR}/${ISO_NAME}" \
    --protective-msdos-label \
    -partition_cyl_align off \
    -partition_offset 16 \
    --mbr-force-bootable \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b --interval:local_fs:7129428d-7137923d::"$SCRIPT_PATH/livecd-${FLAVOUR}/${ISO_NAME}" \
    -appended_part_as_gpt \
    -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
    -c "$SCRIPT_PATH/livecd-${FLAVOUR}/iso/boot.catalog" \
    -b "$SCRIPT_PATH/livecd-${FLAVOUR}/iso/boot/grub/i386-pc/eltorito.img" \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    -eltorito-alt-boot \
    -e '--interval:appended_partition_2_start_1782357s_size_8496d:all::' \
    -no-emul-boot \
    -boot-load-size 8496 \
    ./

echo ">> Done"

echo "Changing rights"
sudo chown $USER:$USER $SCRIPT_PATH/livecd-${FLAVOUR}/out/${OUTPUT_ISO}

echo "Image available in ${OUTPUT_ISO}"
