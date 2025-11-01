#!/bin/bash

# for downloads
okd_version=4.20.0-okd-scos.6
arch=$(uname -m)

# for install-config
domain=jharmison.dev
cluster_name=okd
machine_cidr=10.1.1.0/24
disk_id=nvme-eui.e8238fa6bf530001001b448b4df1d24e
pull_secret=$(jq -c . ~/.pull-secret.json)
ssh_pub_key=$(cat ~/.ssh/id_ed25519.pub)

echo "Prepping installation..."

set -ex

cd "$(dirname "$(realpath "$0")")"
mkdir -p install
cd install

if [ ! -x oc ]; then
    curl -L "https://github.com/okd-project/okd/releases/download/$okd_version/openshift-client-linux-$okd_version.tar.gz" -o oc.tar.gz
    tar zxf oc.tar.gz
    chmod +x oc
fi
if [ ! -x openshift-install ]; then
    curl -L "https://github.com/okd-project/okd/releases/download/$okd_version/openshift-install-linux-$okd_version.tar.gz" -o openshift-install-linux.tar.gz
    tar zxvf openshift-install-linux.tar.gz
    chmod +x openshift-install
fi
if [ ! -e scos-live.iso ]; then
    iso_url=$(./openshift-install coreos print-stream-json | jq -r ".architectures.$arch.artifacts.metal.formats.iso.disk.location")
    curl -L "$iso_url" -o scos-live.iso
fi

export domain cluster_name machine_cidr disk_id pull_secret ssh_pub_key

< ../install-config.yaml.tpl envsubst '$domain,$cluster_name,$machine_cidr,$disk_id,$pull_secret,$ssh_pub_key' > install-config.yaml

if ! [ -e bootstrap-in-place-for-live-iso.ign ]; then
    ./openshift-install create single-node-ignition-config
fi

if ! [ -e okd-install.iso ]; then
    podman run --privileged --pull always --rm \
        -v /dev:/dev \
        -v /run/udev:/run/udev \
        -v "$PWD:/data" -w /data \
        quay.io/coreos/coreos-installer:release \
        iso ignition embed -f \
        -i bootstrap-in-place-for-live-iso.ign \
        -o okd-install.iso \
        scos-live.iso
fi

{ set +x ; } 2>/dev/null

echo
function available_disks {
    lsblk -J | jq -r .blockdevices[].name
}
echo -n 'Plug in the installation flash drive when ready'
install_disk=''
while ! [ "$install_disk" ]; do
    unset previous_disks
    declare -A previous_disks
    for disk in $(available_disks); do
        previous_disks[$disk]=$disk
    done
    sleep 1
    for disk in $(available_disks); do
        if ! [ "${previous_disks[$disk]}" ]; then
            install_disk="$disk"
            break
        fi
    done
    echo -n '.'
done
echo

lsblk
read -rp "Do you want to flash the installer to /dev/$disk? (THIS WILL ERASE EVERYTHING ON IT) [y/N] " disk_good

if [ "${disk_good,,}" != "y" ]; then
    echo "Wanted: y" >&2
    echo "Got:    ${disk_good}" >&2
    exit 1
fi

sudo dd if=okd-install.iso of="/dev/$install_disk" bs=1M conv=fsync status=progress
echo

read -srp 'Press enter when you have booted the flash drive' _
echo
./openshift-install wait-for install-complete
