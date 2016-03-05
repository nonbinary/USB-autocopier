#!/usr/bin/env bash

function checkPartitions {

DEVPATHS=( /dev/${1}? )

# Go through the partitions on the chosen device, and check for mount points
J=0
for (( I=0 ; I < ${#DEVPATHS[@]} ; I ++ )) ; do
  DEVMNTS[${J}]="$(findmnt -no TARGET ${DEVPATHS[$I]})"
  # Since spaces are allowed in file names, and bash tends to separate at spaces, we need an enumerator to only count non-empty values
  if [ ! "${DEVMNTS[${J}]}" == "" ] ; then
    DEVNAMS[${J}]="${DEVPATHS[I]}"
    J=$((J+1))
  fi
done

# Check how many mount points we found
# If we have more than one, send another question to teh user and find out which one to use.
# TODO: add size to this listing
if [ ${#DEVMNTS[@]} -gt 1 ] ; then
  for ((I=0;I<J;I++)) ; do
    DEVSLIST+=("${DEVMNTS[${I}]}")
    DEVSLIST+=("${DEVNAMS[${I}]}")
  done
  MNTPATH=$(zenity --list --title "Mount points" --text "Please choose the partition you wish to use" --column "mount point" --column "device" "${DEVSLIST[@]}")
  return 0

# if we have none, throw an error and give the user a chance to mount & rescan
elif [ "${DEVMNTS[0]}" == "" ] ; then
  zenity --question --text "The device you have selected doesn't seem to have any mounted partitions." --ok-label "Retry" --cancel-label "Exit"
  if [ $? == "0" ] ; then
     checkPartitions ${DEVPATHS#*/}
     return 0
   else
     exit 1
   fi

# if there's just one partition, and it's mounted, use that
else
  MNTPATH=${DEVMNTS[0]}
  return 0
fi

return 1
}

# mainscript start

if [ ! -e "$(which rsync)" ] ; then
  echo "This application needs rsync to function. Plz install."
  exit 1
elif [ ! -e "$(which zenity)" ] ; then
  echo "This application nees zenity to function. Plz install."
  exit 1
fi

I=0
# look in /dev/disk/by-id for anything with a "usb" in its name.
for USBPATH in /dev/disk/by-id/*usb* ; do
  if [[ ! ${USBPATH} =~ part ]] ; then
    USBNAME[${I}]=$(udevadm info -q name -n ${USBPATH})
    USBPROPS[${I}]=$(udevadm info -q property -n ${USBPATH})

    USBVENDOR=$(echo "${USBPROPS[${I}]}" | sed -n "s/ID_VENDOR=\(.*\)/\1/gp" )
    USBMODEL=$(echo "${USBPROPS[${I}]}" | sed -n "s/ID_MODEL=\(.*\)/\1/gp" )
    USBSERIAL=$(echo "${USBPROPS[${I}]}" | sed -n "s/ID_SERIAL_SHORT=\(.*\)/\1/gp" )
    USBTABLE[${I}]="${USBNAME[${I}]} ${USBVENDOR}_${USBMODEL}"
  fi
  I=$((I+1))
done

# throw some zenity-boxes at the user, to find out what files should be copied where upon connetion
# TODO: add another infobox after this first line, that allows for files from multiple directories to be chosen
# ie [infobox: you have chosen these files. <done> <choose more>]

PIKDEV=$(zenity --list --title "USBdevices:" --text "USB devices found:" --column "device"  --column "vendor" ${USBTABLE[@]} )
checkPartitions ${PIKDEV}
SRCPATH=$(zenity --file-selection --multiple --separator="//" --title "Source path" --text "Please choose what files to back up")

# the previous line used double dashes as a field divisor. We need spaces in the file names to be escaped, so we'll use sed to do that,
# and then we'll change the double dashes to spaces, so rsync will see them as different entries.

SRCPATH="$(echo ${SRCPATH} | sed -e 's/ /\\ /g' -e 's/\/\// /g')"
DESTPATH=$( zenity --file-selection --directory --filename "${MNTPATH}/" --title "Destination path" --text "Please specify the destination directory")

# escape any spaces in the destination path, and make it relative

DESTPATH="$(echo ${DESTPATH#${MNTPATH}} | sed -e 's/ /\\ /g' -e 's/\/\// /g')"

# TODO: error-check this. If the user picks a directory outside of the chosen partition, throw an error & let them reconsider.

# get serial & partition using udevinfo

DEST_SERL=$(udevadm info -q property -n ${PIKDEV} | sed -n "s/ID_SERIAL_SHORT=\(.*\)/\1/gp")
DEST_PART_NO=$(findmnt -no SOURCE ${MNTPATH} | sed -n "s/^.*\([0-9]\)$/\1/gp")

# TODO: let the user pick rsync options, if they'd like to.
# zenity's checkboxes are currently driving me insane.

SCRIPT_PATH=/usr/bin/udevUSBsyncer_${USBSERIAL}_${DEST_PART_NO}.sh

# here we need some sudo-thingies, so I'd like something graphical to handle sudo passwords.
# find out if we have ssh-askpass. If not, use zenity.
if [ -e $(which ssh-askpass) ] ; then 
  export SUDO_ASKPASS=$(which ssh-askpass)
else
  export SUDO_ASKPASS="$(which zenity) --password --title='sudo password prompt' --timeout=10"
fi

# TODO: remove the serial no's from the script file names
UDEV_SHELLSCRIPT='#!/usr/bin/env bash
if [ ! -d /mnt/backup ] ; then
  /bin/mkdir /mnt/backup
fi

/bin/mount /dev/$1 /mnt/backup

'$(which rsync)' -qc '${SRCPATH}' /mnt/backup'${DESTPATH}'/

RETURN_CODE=$?
if [ ${RETURN_VALUE} == "0" ] ; then
  /usr/bin/logger "files autocopied to pen drive"
else
  /usr/bin/logger "autocopy failed: rsync error ${RETURN_CODE} ${RETURN_VALUE}"
fi
/bin/umount /mnt/backup

exit 0'

UDEV_SHELLSCRIPT="echo '${UDEV_SHELLSCRIPT}' > ${SCRIPT_PATH}"
echo "${UDEV_SHELLSCRIPT}"
sudo -A sh -c "${UDEV_SHELLSCRIPT}"

sudo -A chmod +x ${SCRIPT_PATH}
UDEVLINE="KERNEL==\\\"sd?${DEST_PART_NO}\\\", SUBSYSTEMS==\\\"usb\\\", ATTRS{serial}==\\\"${USBSERIAL}\\\", RUN+=\\\"${SCRIPT_PATH} %k\\\"" 
sudo -A sh -c "echo ${UDEVLINE} > /lib/udev/rules.d/99-usb-filesync-serial-${USBSERIAL}.rules"
sudo -A udevadm control --reload  
exit 0
