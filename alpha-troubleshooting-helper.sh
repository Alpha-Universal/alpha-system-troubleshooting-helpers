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
final_tar="${cur_user}-troubleshooting.tar.gz"

# copy dmesg for later
dmesg > /home/"${cur_user}"/dmesg.txt

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
        tar cvzf "${final_tar}" "${info_file}" /var/log/syslog /var/log/syslog.1 \
        /var/log/lightdm/ /var/log/Xorg.0.log /home/"${cur_user}"/dmesg.txt --exclude=*.gz 
    elif [[ "${ldm_status}" == 1 && "${x_status}" == 0 ]] ; then
        tar cvzf "${final_tar}" "${info_file}" /var/log/syslog /var/log/syslog.1 \
        /var/log/lightdm/ /home/"${cur_user}"/dmesg.txt --exclude=*.gz 
    elif [[ "${ldm_status}" == 0 && "${x_status}" == 1 ]] ; then
        tar cvzf "${final_tar}" "${info_file}" /var/log/syslog /var/log/syslog.1 \
        /var/log/Xorg.0.log /home/"${cur_user}"/dmesg.txt
    else
        # neither lightdm nor Xorg.0.log are present
        tar cvzf "${final_tar}" "${info_file}" /var/log/syslog /var/log/syslog.1 \
        /home/"${cur_user}"/dmesg.txt
    fi
}

# create function for trap file cleanup
bad_exit () {
	echo "Script exited unexpectedly. Removing all temporary files"
	rm /home/"${cur_user}"/dmesg.txt 
	rm "${info_file}"
	exit 1
}

# have trap remove littered files if the script exits unexpectedly
trap bad_exit SIGINT SIGTERM

# battery vars
battery_locator="$(upower -e | grep -e "BAT[0,1]")"

# net vars
# technically lo is the first iface.  These account for the
# ethernet and wifi, if both interfaces are available.  2: will always match
# the first interface after lo
first_iface="$(ip addr show | grep -m 1 2: | awk '{ print $2 }' | sed  s'/://g')"
# search only for the interface header, since ipv6 addrs will match without it.
second_iface="$(ip addr show | grep state | grep -m 1 3: | awk '{ print $2 }' | sed  s'/://g' || true)"

# install lshw for verbose hardware info
if [[ ! -x /usr/bin/lshw ]] ; then
    sudo apt -y install lshw
fi

# start file with relevant info
echo "### SYSTEM INFO ###" >> "${info_file}"
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
lshw >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "# LSPCI #" >> "${info_file}"
lspci -v -k -nn >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "# LSUSB #" >> "${info_file}"
lsusb >> "${info_file}"
echo -e "\n" >> "${info_file}"

echo "### LOADED MODULES ###" >> "${info_file}"
lsmod | sort >> "${info_file}"
echo -e "\n" >> "${info_file}"

# print an introductory message
echo "
Welcome to the troubleshooting helper, and thank you for running this script.

Please select the number that matches your issue, and all relevant info / logs 
will be packaged into a tar archive at the end.
"

# main loop
while true ; do
	echo "Please select the number matching your issue:"
	select fault in "battery" "HDDs-SSDs" "networking" "temperature" "Skip-this-step" ; do
		case $fault in
			battery ) 
                selected_field="b"
                echo
				echo "Gathering battery info"
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
                echo
				echo "Gathering drive info"
                echo "### DRIVE INFO ###" >> "${info_file}"
                echo "# FSTAB #" >> "${info_file}"
                cat /etc/fstab >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# DF #" >> "${info_file}"
                df -ha >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# LSBLK #" >> "${info_file}"
                lsblk -a -f >> "${info_file}"
                echo -e "\n" >> "${info_file}"
				break
				;;
			networking ) 
                selected_field="n"
                if [[ ! -x /bin/netstat ]] ; then
                    sudo apt install -y net-tools
                fi
                echo
				echo "Gathering wifi / ethernet info"
                echo "### NETWORKING INFO ###" >> "${info_file}"
                echo "# INTERFACE INFO #" >> "${info_file}"
                ip addr show >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# NETSTAT #" >> "${info_file}"
                netstat -tulpn >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# IPTABLES #" >> "${info_file}"
                iptables -L -v -n --line-numbers >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                # determine signal strength, based on which interface is wlan0
                echo "# WIFI SIGNAL STRENGTH #" >> "${info_file}"
                if [[ -z "${second_iface}" ]] ; then
                    sudo iw dev "${first_iface}" link >> "${info_file}"
                else
                    sudo iw dev "${second_iface}" link >> "${info_file}"
                fi 
                echo -e "\n" >> "${info_file}"
				break
				;;
			temperature ) 
                selected_field="t"
                if [[ ! -x /usr/bin/sensors ]] ; then
                    sudo apt -y install lm-sensors
                fi
                echo
				echo "Gathering temperature info"
                echo "### TEMPERATURE INFO ###" >> "${info_file}"
                # find all CPU hogs, which may be contributing to high temps
                echo "# CPU HOGS #" >> "${info_file}"
                ps -eo pcpu,pid,user,args | sort -k1 -r | head >> "${info_file}"
                echo -e "\n" >> "${info_file}"

                echo "# SENSORS #" >> "${info_file}"
                sensors >> "${info_file}"
                echo -e "\n" >> "${info_file}"
				break
				;;
			Skip-this-step )
				selected_field="s"
				echo
				echo -e "Skipping to the end \n"
				break
				;;
			* )
				echo
				echo -e "That selection is invalid.  Please choose a number that matches your issue \n"
				;;
		esac
	done

# select another field or quit
    # test whether only hardware / system info was gathered
    if [[ "${selected_field}" == "s" ]] ; then
	echo
        echo "Writing only the system info and packaging results"
        echo -e "Please attach the "${final_tar}" archive in your next response \n"
        tar_test
        sudo chown "${cur_user}":"${cur_user}" "${final_tar}"
        rm /home/"${cur_user}"/dmesg.txt
        rm "${info_file}"
        exit 0
    else
		echo
	    echo "Would you like to select another issue to troubleshoot, or quit and package results?"
	    select resp in "Choose-another-field" "Quit" ; do
		    case $resp in 
			    Choose-another-field)
				echo
				    echo -e "Returning to issue selector. \n"
				    break
				    ;;
			    Quit)
				echo
				    echo "OK. Writing info and packaging results"
                    echo -e "Please attach the "${final_tar}" archive in your next response \n"
                    tar_test
                    sudo chown "${cur_user}":"${cur_user}" "${final_tar}"
                    rm /home/"${cur_user}"/dmesg.txt
                    rm "${info_file}"
                    exit 0
				    ;;
			    * )
				echo
				    echo -e "That selection is invalid.  Please choose to continue or quit \n"
				    ;;			
		    esac
        done
    fi
done

exit 0
