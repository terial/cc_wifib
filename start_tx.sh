#!/bin/bash
# start_wifibroadcast.sh
#
################## WifiBroadcast start TX script ##################


# Debugging output, commented/disabled by default
#set -e
#set -x

# Network interfaces for wifibroadcast
# Assumes internal network interface is intwifi0
NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`


# Check if config files exists on /boot and convert using dos2unix
function config_convert {
# apconfig.txt
echo "Getting configuration files from /boot.."

if [ ! -f /boot/apconfig.txt ]; then
    echo " Required file missing! apconfig.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/apconfig.txt $DIR_WIFIBROADCAST_CONFIG/apconfig.sh
fi
# joyconfig.txt
if [ ! -f /boot/joyconfig.txt ]; then
    echo " Required file missing! joyconfig.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/joyconfig.txt $DIR_WIFIBROADCAST_CONFIG/rctx.h
fi
# osdconfig.txt
if [ ! -f /boot/osdconfig.txt ]; then
    echo " Required file missing! osdconfig.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/osdconfig.txt $DIR_WIFIBROADCAST_CONFIG/osdconfig.h
fi
# wifibroadcast.txt
if [ ! -f /boot/wifibroadcast.txt ]; then
    echo " Required file missing! wifibroadcast.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/wifibroadcast.txt $DIR_WIFIBROADCAST_CONFIG/wifibroadcast_settings.sh
fi
# wifibroadcast_bitrates.txt
if [ ! -f /boot/wifibroadcast_bitrates.txt ]; then
    echo " Required file missing! wifibroadcast_bitrates.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/wifibroadcast_bitrates.txt $DIR_WIFIBROADCAST_CONFIG/wifibroadcast_bitrates.sh
fi
}


# function check enabled, check if WifiBroadcast is enabled in wifibroadcast.txt
function check_enabled {
	echo -n "Checking if WifiBroadcast is enabled.."
	if [ "$ENABLED" == "N" ]; then
    echo -n " WifiBroadcast is disabled in wifibroadcast settings!"
	echo " Check /boot/wifibroadcast.txt"
	collect_debug
	exit
else
	echo " WifiBroadcast is set to enabled.."
	fi
}


# function tmessage
function tmessage {
    if [ "$QUIET" == "N" ]; then
	echo $1 "$2"
    fi
}


# function collect debug information 
function collect_debug {
	echo #NOT USED... CAUSES ISSUES WITH VIDEO
}


# function detect nics, detect network interfaces
function detect_nics {
	tmessage "Setting up wifi cards ... "
	echo

	iw reg set DE

	if [ "$NUM_CARDS" == "-1" ]; then
	    echo "ERROR: No wifi cards detected"
	    collect_debug
	    sleep 365d
	fi

NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`

	for NIC in $NICS
	do
		prepare_nic $NIC $FREQ
		sleep 0.1
	done

}


# function prepare network interface cards
function prepare_nic {
    DRIVER=`cat /sys/class/net/$1/device/uevent | nice grep DRIVER | sed 's/DRIVER=//'`
    tmessage -n "Setting up $1: "
    if [ "$DRIVER" == "ath9k_htc" ]; then # set bitrates for Atheros via iw
	tmessage -n "Bringing up.. "
	ifconfig $1 up || {
	    echo
	    echo "ERROR: Bringing up interface $1 failed!"
	    collect_debug
	    sleep 365d
	}
	sleep 0.2
	tmessage -n "done. "

	tmessage -n "bitrate "
	if [ "$TYPE" == "RX" ]; then # we are RX, set bitrate to uplink bitrate
	    tmessage -n "$UPLINK_WIFI_BITRATE Mbit "
	    iw dev $1 set bitrates legacy-2.4 $UPLINK_WIFI_BITRATE || {
		echo
		echo "ERROR: Setting bitrate on $1 failed!"
		collect_debug
		sleep 365d
	    }
	else # we are TX, set bitrate to downstream bitrate
	    tmessage -n "$VIDEO_WIFI_BITRATE Mbit "
	    iw dev $1 set bitrates legacy-2.4 $VIDEO_WIFI_BITRATE || {
		echo
		echo "ERROR: Setting bitrate on $1 failed!"
		collect_debug
		sleep 365d
	    }

	fi
	sleep 0.2
	tmessage -n "done. "

	tmessage -n "down.. "
	ifconfig $1 down || {
	    echo
	    echo "ERROR: Bringing down interface $1 failed!"
	    collect_debug
	    sleep 365d
	}
	sleep 0.2
	tmessage -n "done. "
    fi
# doesnt work, local variable ...
#	VIDEO_FRAMETYPE=1 # set video frametype to 1 (data) for non-Atheros, CTS generation is not supported anyway
#	TELEMETRY_FRAMETYPE=1 # set telemetry frametype to 1 (data) for non-Atheros, CTS generation is not supported anyway
#    fi
    tmessage -n "monitor mode.. "
    iw dev $1 set monitor none || {
	echo
	echo "ERROR: Setting monitor mode on $1 failed!"
	collect_debug
	sleep 365d
    }
    sleep 0.2
    tmessage -n "done. "

    tmessage -n "bringing up.. "
    ifconfig $1 up || {
	echo
	echo "ERROR: Bringing up interface $1 failed!"
	collect_debug
	sleep 365d
    }
    sleep 0.2
    tmessage -n "done. "

    if [ "$2" != "0" ]; then
	tmessage -n "frequency $2 MHz.. "
	iw dev $1 set freq $2 || {
	    echo
	    echo "ERROR: Setting frequency $2 MHz on $1 failed!"
	    collect_debug
	    sleep 365d
	}
	tmessage "done!"
    else
	echo
    fi

}


# function tx
function tx_function {
    echo
    detect_nics
    sleep 1
    echo

    VIDEO_FRAMETYPE=1
    echo "Video frametype set to: $VIDEO_FRAMETYPE"


    # check if over-temperature or under-voltage occured
    if vcgencmd get_throttled | nice grep -q -v "0x0"; then
        TEMP=`nice vcgencmd measure_temp | cut -f 2 -d "="`
        echo "ERROR: Over-Temperature or unstable power supply! Temp:$TEMP"
        collect_debug
    nice -n -9 raspivid -w $WIDTH -h $HEIGHT -fps $FPS -b 3000000 -g $KEYFRAMERATE -t 0 $EXTRAPARAMS -ae 40,0x00,0x8080FF -a "\n\nunder-voltage or over-temperature on TX!" -o - | nice -n -9 $DIR_WIFIBROADCAST/wifibroadcast/tx -p 0 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEO_BLOCKLENGTH -t $VIDEO_FRAMETYPE -d $VIDEO_WIFI_BITRATE -y 0 $NICS
    sleep 365d
    fi

    # check for potential power-supply problems
    if nice dmesg | nice grep -q over-current; then
        echo "ERROR: Over-current detected - potential power supply problems!"
        collect_debug
    sleep 365d
    fi

    # check for USB disconnects (due to power-supply problems)
    if nice dmesg | nice grep -q disconnect; then
        echo "ERROR: USB disconnect detected - potential power supply problems!"
        collect_debug
    sleep 365d
    fi

    echo "Starting transmission in $TXMODE mode: $WIDTH x $HEIGHT $FPS fps, Bitrate: $BITRATE Bit/s, Keyframerate: $KEYFRAMERATE, Wifi Bitrate: $VIDEO_WIFI_BITRATE"
    nice -n -9 raspivid -w $WIDTH -h $HEIGHT -fps $FPS -b $BITRATE -g $KEYFRAMERATE -t 0 $EXTRAPARAMS $ANNOTATION -o - | nice -n -9 $DIR_WIFIBROADCAST/wifibroadcast/tx -p 0 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEO_BLOCKLENGTH -t $VIDEO_FRAMETYPE -d $VIDEO_WIFI_BITRATE -y 0 $NICS
    TX_EXITSTATUS=${PIPESTATUS[1]}
    # if we arrive here, either raspivid or tx did not start, or were terminated later
    # check if NIC has been removed
    NICS2=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot | nice grep -v wlan0`
    if [ "$NICS" == "$NICS2" ]; then
    	# wifi card has not been removed
	if [ "$TX_EXITSTATUS" != "0" ]; then
	    echo "ERROR: could not start tx or tx terminated!"
	fi
	collect_debug
	sleep 365d
    else
        # wifi card has been removed
        echo "ERROR: Wifi card removed!"
	collect_debug
	sleep 365d
    fi
}


# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Source chonfiguration files
DIR_SETTINGS=$DIR_WIFIBROADCAST_CONFIG
source $DIR_SETTINGS/wifibroadcast_settings.sh
source $DIR_SETTINGS/wifibroadcast_bitrates.sh
# Get settings from /boot
config_convert
# Check if WifiBroadcast is set to enabled
check_enabled
# Start WifiBroadcast TX
tx_function 





