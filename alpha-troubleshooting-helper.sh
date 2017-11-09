#!/bin/bash -

#   Name    :   alpha-troubleshooting-helper.sh
#   Author  :   Richard Buchanan II for Alpha Universal, LLC
#   Brief   :   A script to gather useful info to help with
#		troubleshooting all Alpha devices.
#

set -o errexit      # exits if non-true exit status is returned
set -o nounset      # exits if unset vars are present

PATH=/usr/local/bin:/usr/bin:/bin:/sbin:/usr/sbin:/usr/local/sbin

# fail _if_ running as root
if [[ $EUID -ne 0 ]] ; then
    echo "This script requires root privileges." ;
    echo "Please re-run this script with sudo." ;
    exit 1 ;
fi

# general vars
cur_user="$(who | cut -f 1 -d ' ' | uniq)"
full_date="$(date +%a-%F)"
info_file="/home/${cur_user}/${cur_user}-${full_date}_troubleshooting.info"
bios_file="/home/${cur_user}/${cur_user}-${full_date}_bios.info"
dmesg_file="/home/${cur_user}/${cur_user}-${full_date}_dmesg.txt"
final_tar="/home/${cur_user}/${cur_user}-${full_date}_troubleshooting.tar.gz"

# set lightdm dir and xorg log as unavailable
ldm_status=0
x_status=0

# test for availability of lightdm dir and xorg log
if [[ -d /var/log/lightdm ]] ; then
    ldm_status=1
fi
if [[ -f /var/log/Xorg.0.log ]] ; then
    x_status=1
fi

# test for which files to include in final archive
# the --exclude option is for the .gz backups in /var/log/lightdm
tar_test () {
    if [[ "${ldm_status}" == 1 && "${x_status}" == 1 ]] ; then
        tar cvzf "${final_tar}" "${info_file}" "${bios_file}" "${dmesg_file}" \
        /var/log/syslog /var/log/syslog.1 /var/log/lightdm/ /var/log/Xorg.0.log --exclude=*.gz 
    elif [[ "${ldm_status}" == 1 && "${x_status}" == 0 ]] ; then
        tar cvzf "${final_tar}" "${info_file}" "${bios_file}" "${dmesg_file}" \
        /var/log/syslog /var/log/syslog.1 /var/log/lightdm/ --exclude=*.gz 
    elif [[ "${ldm_status}" == 0 && "${x_status}" == 1 ]] ; then
        tar cvzf "${final_tar}" "${info_file}" "${bios_file}" "${dmesg_file}" \
        /var/log/syslog /var/log/syslog.1 /var/log/Xorg.0.log
    else
        # neither lightdm nor Xorg.0.log are present
        tar cvzf "${final_tar}" "${info_file}" "${bios_file}" "${dmesg_file}" \
        /var/log/syslog /var/log/syslog.1
    fi
}

# create function for trap file cleanup
bad_exit () {
	echo "Script exited unexpectedly. Removing all temporary files"
	rm "${dmesg_file}"
	rm "${info_file}"
	rm "${bios_file}" 
	exit 1
}

# have trap remove littered files if the script exits unexpectedly
trap bad_exit SIGINT SIGTERM

# battery vars
battery_locator="$(upower -e | grep -e "BAT[0|1]")"

# net vars
# technically lo is the first iface.  These account for the
# ethernet and wifi, if both interfaces are available.  2: will always match
# the first interface after lo
first_iface="$(ip addr show | grep -m 1 2: | awk '{ print $2 }' | sed  s'/://g')"
# search only for the interface header, since ipv6 addrs will match without it.
second_iface="$(ip addr show | grep state | grep -m 1 3: | awk '{ print $2 }' | sed  s'/://g' || true)"

# install lshw for verbose hardware info
if [[ ! -x /usr/bin/lshw ]] ; then
    apt -y install lshw
fi

# some customers run this in a TTY or other situation where they can't easily
# attach the final archive to an email.  This interactive step is used to later
# automatically mount and copy the archive to a USB drive for those customers.
blocked_gui=0

while [[ "${blocked_gui}" == 0 ]] ; do
	echo -e "\nAre you running this troubleshooter in a TTY?"
	select yn in "Yes" "No" ; do
        case $yn in
            Yes )
				blocked_gui="y"
				# scan /dev for current drives to find USB later.  Couldn't get
				# arrays to play nice with newlines just yet, so sed removes all
				# newlines from ls
				cur_drives="$(ls /dev/sd[a-z] | sed 's/\n/ /g')"

				echo -e "\nOK, please plug in your USB now."
				# use sleep to fake interactivity for now
				sleep 5
				break
				;;
			No )
				blocked_gui="n"				
				echo -e "\nOK, moving on to info collection."
				break
				;;
            * )
                echo -e "\nThat selection is invalid.  Please select yes or no. \n"
                ;;
		esac
	done
done

# start main file with default info
echo "### SYSTEM INFO ###" > "${info_file}"
echo "# KERNEL #" >> "${info_file}"
uname -a >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "# DISTRO #" >> "${info_file}"
lsb_release -a >> "${info_file}" 2> /dev/null
echo -e "\n" >> "${info_file}"

echo "### HARDWARE INFO ###" >> "${info_file}"
echo "# LSCPU #" >> "${info_file}"
lscpu >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "# LSHW #" >> "${info_file}"
lshw >> "${info_file}" || echo "lshw was not installed" >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "# LSPCI #" >> "${info_file}"
lspci -v -k -nn >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "# LSUSB #" >> "${info_file}"
lsusb >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "# PARTITIONS #" >> "${info_file}"
lsblk -a -f >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "# MEMORY #" >> "${info_file}"
free -hwl --si >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "### LOADED MODULES ###" >> "${info_file}"
lsmod | sort >> "${info_file}"
echo -e "\n" >> "${info_file}"

# gather BIOS info in a separate file
echo "### BIOS INFO ###" > "${bios_file}"
dmidecode >> "${bios_file}" 

# copy dmesg for later packaging
echo "### DMESG ###" > "${dmesg_file}"
dmesg >> "${dmesg_file}"

# print an introductory message
echo "
Welcome to the troubleshooting helper, and thank you for running this script.

Please select the number that matches your issue, and all relevant info / logs 
will be packaged into a tar archive at the end.
"

# for breaking out of the main loop
main_break=0

# main loop
while [[ "${main_break}" == 0 ]] ; do
	echo "Please select the number matching your issue:"
	select fault in "battery" "HDDs-SSDs" "networking" "temperature" "Skip-this-step" ; do
        case $fault in
            battery )
                selected_field="b"
                echo -e "\nGathering battery info"
                echo "### BATTERY INFO ###" >> "${info_file}"
                echo "# UPOWER #" >> "${info_file}"
                upower -i "${battery_locator}" >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# TLP DPKG STATUS #" >> "${info_file}"
                dpkg -l tlp >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# TLP SYSTEMCTL STATUS #" >> "${info_file}"
                systemctl status tlp.service >> "${info_file}"
                echo -e "\n" >> "${info_file}"
                break
                ;;
            HDDs-SSDs ) 
                selected_field="d"
                echo -e "\nGathering drive info"
                echo "### DRIVE INFO ###" >> "${info_file}"
                echo "# FSTAB #" >> "${info_file}"
                cat /etc/fstab >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# PARTED #" >> "${info_file}"
                parted --list --script >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# DF #" >> "${info_file}"
                df -ha >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                break
                ;;
            networking ) 
                selected_field="n"
                if [[ ! -x /bin/netstat ]] ; then
                    apt install -y net-tools
                fi
                echo -e "\nGathering wifi / ethernet info"
                echo "### NETWORKING INFO ###" >> "${info_file}"
                echo "# INTERFACE INFO #" >> "${info_file}"
                ip addr show >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# NETSTAT #" >> "${info_file}"
                netstat -tulpn >> "${info_file}" || \
                    echo "netstat was not installed" >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# IPTABLES #" >> "${info_file}"
                iptables -L -v -n --line-numbers >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                # determine signal strength, based on which interface is wlan0
                echo "# WIFI SIGNAL STRENGTH #" >> "${info_file}"
                if [[ -z "${second_iface}" ]] ; then
                    iw dev "${first_iface}" link >> "${info_file}"
                else
                    iw dev "${second_iface}" link >> "${info_file}"
                fi 
                echo -e "\n" >> "${info_file}"
                break
                ;;
            temperature ) 
                selected_field="t"
                if [[ ! -x /usr/bin/sensors ]] ; then
                    apt -y install lm-sensors
                fi
                echo -e "\nGathering temperature info"
                echo "### TEMPERATURE INFO ###" >> "${info_file}"

                # find all CPU hogs, which may be contributing to high temps
                echo "# CPU HOGS #" >> "${info_file}"
                ps -eo pcpu,pid,user,args | sort -k1 -r | head >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# SENSORS #" >> "${info_file}"
                sensors >> "${info_file}" || \
                    echo "sensors was not installed" >> "${info_file}"
                echo -e "\n" >> "${info_file}"
                break
                ;;
            Skip-this-step )
                selected_field="s"
                echo -e "\nSkipping to the end \n"
                break
                ;;
            * )
                echo -e "\nThat selection is invalid.  Please choose a number that matches your issue \n"
                ;;
		esac
	done

# select another field or quit
    # test whether only hardware / system info was gathered
    if [[ "${selected_field}" == "s" ]] ; then
        main_break=1
        tar_test
        echo -e "\nWriting only the system info and packaging results"
        echo "Please attach the ${final_tar} archive in your next response."
        chown "${cur_user}":"${cur_user}" "${final_tar}"
        rm "${dmesg_file}"
        rm "${info_file}"
        rm "${bios_file}"
    else
        echo -e "\nWould you like to select another issue to troubleshoot, or quit and package results?"
        select resp in "Choose-another-field" "Quit" ; do
            case $resp in
                Choose-another-field)
                    echo -e "\nReturning to issue selector. \n"
                    break
                    ;;
                Quit)
			        main_break=1
                    tar_test
                    echo -e "\nWriting info and packaging results"
                    echo "Please attach the ${final_tar} archive in your next response"
                    chown "${cur_user}":"${cur_user}" "${final_tar}"
                    rm "${dmesg_file}"
                    rm "${info_file}"
                    rm "${bios_file}"
                    ;;
                * )
                    echo -e "\nThat selection is invalid.  Please choose to continue or quit \n"
                    ;;
            esac
        done
    fi
done

# bring the USB into the picture, if running in a TTY
if [[ "${blocked_gui}" == "y" ]] ; then
	# scan drives in /dev again and compare to what we found the first time
	new_drives="$(ls /dev/sd[a-z] | sed 's/\n/ /g')"

	# loop until the USB is added
	while [[ "${cur_drives}" == "${new_drives}" ]] ; do
		echo "Your USB drive wasn't found.  Please insert it now."
		sleep 5
		# reload our /dev search results
		new_drives="$(ls /dev/sd[a-z] | sed 's/\n/ /g')"
	done
	
	# define the last sequential ls entry as the USB drive.
	usb_drive="$(echo ${new_drives} | awk '{ print $NF }')"
	
	# Concatenate 1 to the USB drive entry.  The drive is currently used as if
	# it had one partition spanning the whole drive, or multiple partitions with
	# only the first used
	usb_drive+=1

	# search for if /mnt is already being used as a mount point
	mnt_search="$(lsblk -a -f | grep mnt || echo x)"

	# search for if the USB was mounted to /media automatically
	if [[ -n "$(mount | grep "${usb_drive}")" ]] ; then
		umount "${usb_drive}"
	fi

	# mount to /mnt or create a new directory, depending on search result	
	echo -e "\nCopying archive to your USB drive. Don't remove drive until finished."
	if [[ "${mnt_search}" == "x" ]] ; then
		# /mnt isn't mounted anywhere
		# sleep is used to ensure that umount doesn't produce a "target is busy" error
		mount "${usb_drive}" /mnt
		mv "${final_tar}" /mnt && sleep 5 && umount /mnt
	else
		if [[ ! -e /tmp/mnt ]] ; then
			mkdir /tmp/mnt
		fi
		mount "${usb_drive}" /tmp/mnt
		mv "${final_tar}" /tmp/mnt && sleep 5 && umount /tmp/mnt
		rmdir /tmp/mnt
	fi

	# wrap everything up for those in a TTY
	echo -e "\nThe archive was copied to your USB drive.  You can now safely remove the drive."
	
	echo "Execute this command to shut this TTY session down:  sudo shutdown -h now"
fi

exit 0
