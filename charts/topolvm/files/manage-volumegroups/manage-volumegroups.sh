#!/bin/bash

set -eu

function pv_in_vg {
  for local_pv in $(chroot /host pvdisplay -C --no-headings -o pv_name -S "vgname=${2}"); do
    if [ "$local_pv" = "${1}" ]; then
      return 0
    fi
  done
  return 1
}

vg="${1}"
shift

found_pvs=()
for disk in "${@}"; do
  if [ -e "/host${disk}" ]; then
    echo "Found disk: $disk"
    if chroot /host pvdisplay "$disk" >/dev/null 2>&1; then
      echo "Already a PV"
    else
      echo "Wiping disk and creating a PV"
      chroot /host dd if=/dev/zero of="$disk" bs=1M count=5 conv=fsync
      chroot /host pvcreate "$disk"
    fi
    found_pvs+=($(chroot /host pvdisplay -C --no-headings -o pv_name "$disk"))
  fi
done

if chroot /host vgdisplay "$vg" >/dev/null 2>&1; then
  echo "Found VG: $vg"
  for pv in "${found_pvs[@]}"; do
    if pv_in_vg "$pv" "$vg"; then
      echo "PV ${pv} is in VG ${vg} already"
    else
      echo "Adding PV ${pv} to VG ${vg}"
      chroot /host vgextend "$vg" "$pv"
    fi
  done
else
  chroot /host vgcreate "$vg" "${found_pvs[@]}"
fi

echo
echo -n "Confirming all PVs in VG."
failed=false
for pv in "${found_pvs[@]}"; do
  if pv_in_vg "$pv" "$vg"; then
    echo -n .
  else
    echo
    echo "PV $pv missing!" >&2
    failed=true
  fi
done
echo
if $failed; then
  exit 1
fi
echo "Done!"
