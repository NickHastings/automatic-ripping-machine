#!/bin/bash

if [ "$(whoami)" != "arm" ] ; then
    logger -s -t ARM "[ARM] only the \"arm\" user should run $0"
    exit 0
fi

# Check if armui is running. If not, do nothing
systemctl is-active --quiet armui.service || exit 0
set -x
DEVNAME=$1

#######################################################################################
# YAML Parser to read Config
#
# From: https://stackoverflow.com/questions/5014632/how-can-i-parse-a-yaml-file-from-a-linux-shell-script
#######################################################################################

function parse_yaml {
    local prefix=$2
    local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
    sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
        awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}

for f in ~/.config/arm/arm.yaml /etc/arm/arm.yaml /opt/arm/arm.yaml ; do
    if [ ! -e $f ] ; then
        continue
    fi
    logger -t ARM -s "[ARM] Reading config from $f"
    eval $(parse_yaml $f "CONFIG_")
    break
done

#######################################################################################
# Log Discovered Type and Start Rip
#######################################################################################

# ID_CDROM_MEDIA_BD = Bluray
# ID_CDROM_MEDIA_CD = CD
# ID_CDROM_MEDIA_DVD = DVD

if [ "$ID_CDROM_MEDIA_DVD" == "1" ]; then
    if [ "$CONFIG_PREVENT_99" != "false" ]; then
	numtracks=$(lsdvd /dev/${DEVNAME} 2> /dev/null | sed 's/,/ /' | cut -d ' ' -f 2 | grep -E '[0-9]+' | sort -r | head -n 1)
	if [ "$numtracks" == "99" ]; then
	    logger -t ARM -s "[ARM] ${DEVNAME} has 99 Track Protection. Bailing out and ejecting."
	    eject ${DEVNAME}
	    exit
	fi
    fi
    logger -t ARM -s "[ARM] Starting ARM for DVD on ${DEVNAME}"

elif [ "$ID_CDROM_MEDIA_BD" == "1" ]; then
    logger -t ARM -s "[ARM] Starting ARM for Bluray on ${DEVNAME}"

elif [ "$ID_CDROM_MEDIA_CD" == "1" ]; then
    logger -t ARM -s "[ARM] Starting ARM for CD on ${DEVNAME}"

elif [ "$ID_FS_TYPE" != "" ]; then
    logger -t ARM -s "[ARM] Starting ARM for Data Disk on ${DEVNAME} with File System ${ID_FS_TYPE}"

else
    logger -t ARM -s "[ARM] Not CD, Bluray, DVD or Data. Bailing out on ${DEVNAME}"
    exit
fi

export PYTHONPATH="${CONFIG_INSTALLPATH}"
# This is use of "at now" is becuase otherwise systemd-udev will kill it after one minute
# if this script is launched from a udev rule
echo "/usr/bin/python3 ${CONFIG_INSTALLPATH}/arm/ripper/main.py -d ${DEVNAME}" | at now
