#!/bin/bash

# MY_PATH="`dirname \"$0\"`"              # relative
SCRIPT_PATH="`( cd \"$SCRIPT_PATH\" && pwd )`"  # absolutized and normalized
if [ -z "$SCRIPT_PATH" ] ; then
  # error; for some reason, the path is not accessible
  # to the script (e.g. permissions re-evaled after suid)
  exit 1  # fail
fi
echo "Running script from $SCRIPT_PATH"

# FLAVOUR=$(echo ${1} | tr '[:upper:]' '[:lower:]')
CONFIG_FILE=${SCRIPT_PATH}/${1}
echo "Using ${CONFIG_FILE}"

echo "Installing prerequisites"
sudo apt-get -qq install \
                    squashfs-tools \
                    schroot \
                    genisoimage \
                    xorriso \
                    jq \
                    curl
echo ">> Done"

echo "Checking config file presence"
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
  
    readarray -t FILES_ORIGIN < <(jq -r '.additional_files[].origin_path' ${CONFIG_FILE})
    readarray -t FILES_TARGET < <(jq -r '.additional_files[].target_path' ${CONFIG_FILE})
    readarray -t FILES_DESCRIPTION < <(jq -r '.additional_files[].description' ${CONFIG_FILE})

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
    mkdir iso squashfs out
    echo ">> Done"
fi

case $FLAVOUR in
    ubuntu)
        echo "Ubuntu flavour selected"
        ISO_NAME="ubuntu-20.04.3-desktop-amd64.iso"
        ISO_URL="https://releases.ubuntu.com/20.04.3/ubuntu-20.04.3-desktop-amd64.iso"
    ;;
    kubuntu)
        echo "Kubuntu flavour selected"
        ISO_NAME="kubuntu-20.04.3-desktop-amd64.iso"
        ISO_URL="https://cdimage.ubuntu.com/kubuntu/releases/20.04.3/release/kubuntu-20.04.3-desktop-amd64.iso"
    ;;
    xubuntu)
        echo "Xubuntu flavour selected"
        ISO_NAME="xubuntu-20.04.3-desktop-amd64.iso"
        ISO_URL="https://cdimages.ubuntu.com/xubuntu/releases/20.04/release/xubuntu-20.04.3-desktop-amd64.iso"
    ;;
    lubuntu)
        echo "Lubuntu flavour selected"
        ISO_NAME="lubuntu-20.04.3-desktop-amd64.iso"
        ISO_URL="https://cdimage.ubuntu.com/lubuntu/releases/20.04.3/release/lubuntu-20.04.3-desktop-amd64.iso"
    ;;
    *)
        echo "Please select between Ubuntu, Kubuntu, Xubuntu, Lubuntu"
        exit
esac

cd $SCRIPT_PATH/livecd-${FLAVOUR}

echo "Checking if iso is present"
if [[ ! -f ${ISO_NAME} ]]; then
    echo "Downloading..."
    wget -q ${ISO_URL}
    echo ">> Done"
    echo "Mounting ISO"
    sudo mount -o loop ${ISO_NAME} /mnt
    echo "Copying files"
    sudo cp -a /mnt/. iso
    echo "Unmounting ISO"
    sudo umount /mnt
    echo "Mounting squashfs"
    sudo mount -t squashfs -o loop iso/casper/filesystem.squashfs /mnt
    echo "Copying squashfs"
    sudo cp -a /mnt/. squashfs
    echo "Unmounting squashfs"
    sudo umount /mnt

fi

echo "Preparing system for modification"
sudo mount --bind /proc squashfs/proc 
sudo mount --bind /sys squashfs/sys
sudo mount -t devpts none squashfs/dev/pts
# sudo mount --bind /dev squashfs/dev
# sudo mount --bind /dev/pts squashfs/dev/pts

echo "Updating resolv.conf for network resolution"
sudo cp /etc/resolv.conf squashfs/etc/resolv.conf
sudo cp /etc/apt/sources.list squashfs/etc/apt/sources.list

echo ${JSON} | sudo tee squashfs/tmp/config.json > /dev/null

echo "Listing files to copy"
i=0
for FILES in "${FILES_DESCRIPTION[@]}"; do
    echo "Processing $FILES"
    sudo mkdir -p ${FILES_TARGET[$i]}
    sudo cp ${FILES_ORIGIN[$i]} ${FILES_TARGET[$i]} 
    ((i++))
done
echo ">> Done"

echo "Entering chroot"
sudo chroot squashfs /usr/bin/bash <<"EOT"

apt-get -qq update
apt-get -qq install -y curl jq

# if [[ $(dpkg-query --show --showformat='${db:Status-Status}\n' 'curl') -eq 'not-installed' ]]; then
#     echo "[Error] curl not installed. Exiting."
#     exit
# fi

# if [[ $(dpkg-query --show --showformat='${db:Status-Status}\n' 'jq') -eq 'not-installed' ]]; then
#     echo "[Error] jq not installed. Exiting.
#     exit
# fi

CONFIG_FILE="/tmp/config.json"

readarray -t REPOSITORIES_NAME < <(jq -r '.repositories[].name' ${CONFIG_FILE})
readarray -t REPOSITORIES_GPG < <(jq -r '.repositories[].gpg_signature' ${CONFIG_FILE})
readarray -t REPOSITORIES_URL < <(jq -r '.repositories[].url' ${CONFIG_FILE})
readarray -t REPOSITORIES_LIST < <(jq -r '.repositories[].list_file' ${CONFIG_FILE})

readarray -t PACKAGES_REMOTE < <(jq --arg type "remote" -r '.packages[] | select(.type == $type).name' ${CONFIG_FILE})
readarray -t PACKAGES_LOCAL < <(jq --arg type "local" -r '.packages[] | select(.type == $type).name' ${CONFIG_FILE})

echo "Installing Zoom"
cd /tmp
wget -q https://zoom.us/client/latest/zoom_amd64.deb
apt-get -qq install -y ./zoom_amd64.deb
echo ">> Done"

echo "Adding repositories"
i=0
for REPOSITORY in ${REPOSITORIES_NAME[@]}; do
    echo "Processing $REPOSITORY"
    echo "Adding GPG"
    # wget -O - ${REPOSITORIES_GPG[$i]} | apt-key add -
    curl -s -L ${REPOSITORIES_GPG[$i]} | apt-key add -
    # echo ">> Done"
    echo "Adding repository"
    echo ${REPOSITORIES_URL[$i]} | tee "/etc/apt/sources.list.d/${REPOSITORIES_LIST[$i]}" > /dev/null
    echo ">> Done"
    ((i++))
done

add-apt-repository universe
add-apt-repository multiverse
apt-get -qq update
apt-get -qq dist-upgrade
apt-get -qq autoremove
apt-get -qq autoclean
echo ">> Done"

echo "Installing remote packages"
i=0
for PACKAGE_REMOTE in ${PACKAGES_REMOTE[@]}; do
    echo "Processing $PACKAGE_REMOTE"
    apt-get -qq install -y $PACKAGE_REMOTE
    echo ">> Done"
    ((i++))
done
echo ">> Done"

echo "Installing local packages"
i=0
for PACKAGE_LOCAL in ${PACKAGES_LOCAL[@]}; do
    echo "Processing $PACKAGE_LOCAL"
    apt-get -qq install -y /tmp/$PACKAGE_LOCAL
    echo ">> Done"
    ((i++))
done
echo ">> Done"

echo "Cleaning packages"
apt-get clean
echo ">> Done"

# echo "Deleting crash log"
# rm -r /var/crash/*

echo "Exiting chroot"
# umount -lf /sys
# umount -lf /proc
# umount -lf /dev/pts
# umount -lf /dev
rm /etc/resolv.conf
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
sudo chroot squashfs dpkg-query -W --showformat='${Package}  ${Version}\n' > iso/casper/filesystem.manifest
sudo chmod go-w iso/casper/filesystem.manifest
echo ">> Done"

echo "Removing old squashfs"
sudo rm iso/casper/filesystem.squashfs
echo ">> Done"

echo "Creating the new squashfs"
cd squashfs
sudo mksquashfs . ../iso/casper/filesystem.squashfs #-info
cd ..
echo ">> Done"

echo "Generating new ISO"
cd iso
sudo bash -c "find . -path ./isolinux -prune -o -type f -not -name md5sum.txt -print0 | xargs -0 md5sum | tee md5sum.txt" > /dev/null
echo ">> Done"

echo "Generating disk image"
# sudo genisoimage -o "Custom.iso" -r -J -no-emul-boot -V "USB_LINUX" -boot-load-size 4 -boot-info-table -b isolinux/isolinux.bin -c isolinux/boot.cat ./ 
sudo xorriso -as mkisofs -r -V "${OUTPUT_VOLUME}" \
             -cache-inodes -J -l \
             -c isolinux/boot.cat \
             -b isolinux/isolinux.bin \
                -no-emul-boot -boot-load-size 4 -boot-info-table \
             -eltorito-alt-boot \
             -e boot/grub/efi.img \
                -no-emul-boot -isohybrid-gpt-basdat \
             -o $SCRIPT_PATH/livecd-${FLAVOUR}/out/${OUTPUT_ISO} ./
echo ">> Done"

echo "Changing rights"
sudo chown $USER:$USER $SCRIPT_PATH/livecd-${FLAVOUR}/out/${OUTPUT_ISO}

echo "Image available in ${OUTPUT_ISO}"
