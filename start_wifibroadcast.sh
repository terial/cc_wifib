#!/bin/bash
# start_wifibroadcast.sh
#
##################WifiBroadcast start script##################
#
# videofifo
    # videofifo1: local display, hello_video.bin
    # videofifo2: secondary display, hotspot/usb-tethering
    # videofifo3: recording
    # videofifo4: wbc relay
#
# telemetryfifo
    # telemetryfifo1: local display, osd
    # telemetryfifo2: secondary display, hotspot/usb-tethering
    # telemetryfifo3: recording
    # telemetryfifo4: wbc relay
    # telemetryfifo5: mavproxy downlink
    # telemetryfifo6: serial downlink
#

# Debugging output, commented/disabled by default
set -e
set -x

# Network interfaces for wifibroadcast
# Assumes internal network interface is wlan0
NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot | nice grep -v wlan0`


# Check if config files exists on /boot and convert using dos2unix
function config_convert {
# apconfig.txt
if [ ! -f /boot/apconfig.txt ]; then
    echo " Required file missing! apconfig.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/apconfig.txt /tmp/apconfig.sh
fi
# joyconfig.txt
if [ ! -f /boot/joyconfig.txt ]; then
    echo " Required file missing! joyconfig.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/joyconfig.txt /tmp/rctx.h
fi
# osdconfig.txt
if [ ! -f /boot/osdconfig.txt ]; then
    echo " Required file missing! osdconfig.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/osdconfig.txt /tmp/osdconfig.h
fi
# wifibroadcast.txt
if [ ! -f /boot/wifibroadcast.txt ]; then
    echo " Required file missing! wifibroadcast.txt not found..!"
	EXIT_STATUS=1
else
    dos2unix -n /boot/wifibroadcast.txt /tmp/wifibroadcast_settings.sh
fi
}


# function check enabled, check if WifiBroadcast is enabled in wifibroadcast.txt
function check_enabled {
	if [ "$ENABLED" == "N" ]; then
    echo "WifiBroadcast is disabled in wifibroadcast settings!"
	echo "Check /boot/wifibroadcast.txt"
	collect_debug
	exit 
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
echo "debug function"
}


# function detect nics, detect network interfaces
function detect_nics {
	tmessage "Setting up wifi cards ... "
	echo

	iw reg set DE

	#NUM_CARDS=-1
	#NICSWL=`ls /sys/class/net | nice grep wlan`

#	for NIC in $NICSWL
#	do
#	    # re-name wifi interface to MAC address
#	    NAME=`cat /sys/class/net/$NIC/address`
#	    ip link set $NIC name ${NAME//:}
#	    let "NUM_CARDS++"
#	    #sleep 0.1
#	done

	if [ "$NUM_CARDS" == "-1" ]; then
	    echo "ERROR: No wifi cards detected"
	    collect_debug
	    sleep 365d
	fi

        if [ "$TYPE" == "RX" ]; then # only do relay/hotspot stuff if RX
	    # get wifi hotspot card out of the way
	    if [ "$WIFI_HOTSPOT" == "Y" ]; then
		if [ "$WIFI_HOTSPOT_NIC" != "internal" ]; then
		    # only configure it if it's there
		    if ls /sys/class/net/ | grep -q $WIFI_HOTSPOT_NIC; then
			tmessage -n "Setting up $WIFI_HOTSPOT_NIC for Wifi Hotspot operation.."
			ip link set $WIFI_HOTSPOT_NIC name wifihotspot0
			ifconfig wifihotspot0 192.168.2.1 up
			tmessage "done!"
			let "NUM_CARDS--"
		    else
			tmessage "Wifi Hotspot card $WIFI_HOTSPOT_NIC not found!"
			sleep 0.5
		    fi
		else
		    # only configure it if it's there
		    if ls /sys/class/net/ | grep -q ap0; then
			tmessage -n "Setting up wlan0 for Wifi Hotspot operation.."
			ip link set wlan0 name ap0
			ifconfig ap0 192.168.2.1 up
			tmessage "done!"
		    else
			tmessage "Pi3 Onboard Wifi Hotspot card not found!"
			sleep 0.5
		    fi
		fi
	    fi
	    # get relay card out of the way
	    if [ "$RELAY" == "Y" ]; then
		# only configure it if it's there
		if ls /sys/class/net/ | grep -q $RELAY_NIC; then
		    ip link set $RELAY_NIC name relay0
		    prepare_nic relay0 $RELAY_FREQ
		    let "NUM_CARDS--"
		else
		    tmessage "Relay card $RELAY_NIC not found!"
		    sleep 0.5
		fi
	    fi

	fi

        NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot | nice grep -v wlan0`

	if [ "$TXMODE" != "single" ]; then
	    for i in $(eval echo {0..$NUM_CARDS})
	    do
	        if [ "$TYPE" == "RX" ]; then
		    prepare_nic $NICS $FREQ_RX
	        else
		    prepare_nic $NICS $FREQ_TX
    		fi
		sleep 0.1
	    done
	else
	    # check if auto scan is enabled, if yes, set freq to 0 to let prepare_nic know not to set channel
	    if [ "$FREQSCAN" == "Y" ] && [ "$TYPE" == "RX" ]; then
		for NIC in $NICS
		do
		    prepare_nic $NIC 2484
		    sleep 0.1
		done
		# make sure check_alive function doesnt restart hello_video while we are still scanning for channel
		touch /tmp/pausewhile
		/opt/wifibroadcast/wifibroadcast/rx -p 0 -d 1 -t 6 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEOBLOCKLENGTH $NICS >/dev/null &
		sleep 0.5
		echo
		echo -n "Please wait, scanning for TX ..."
		FREQ=0

		if iw list | nice grep -q 5180; then # cards support 5G and 2.4G
		    FREQCMD="/opt/wifibroadcast/wifibroadcast/channelscan 245 $NICS"
		else
		    if iw list | nice grep -q 2312; then # cards support 2.3G and 2.4G
		        FREQCMD="/opt/wifibroadcast/wifibroadcast/channelscan 2324 $NICS"
		    else # cards support only 2.4G
		        FREQCMD="/opt/wifibroadcast/wifibroadcast/channelscan 24 $NICS"
		    fi
		fi

		while [ $FREQ -eq 0 ]; do
			FREQ=`$FREQCMD`
		done

		echo "found on $FREQ MHz"
		echo
		ps -ef | nice grep "rx -p 0" | nice grep -v grep | awk '{print $2}' | xargs kill -9
		for NIC in $NICS
		do
		    echo -n "Setting frequency on $NIC to $FREQ MHz.. "
		    iw dev $NIC set freq $FREQ
		    echo "done."
		    sleep 0.1
		done
		# all done
		rm /tmp/pausewhile
	    else
		for NIC in $NICS
		do
		    prepare_nic $NIC $FREQ
		    sleep 0.1
		done
	    fi
	fi
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


# function check health, not used, somehow calling vgencmd seems to cause badblocks
function check_health_function {
	# not used, somehow calling vgencmd seems to cause badblocks
	# check if over-temperature or under-voltage occured
	if nice vcgencmd get_throttled | nice nice grep -q -v "0x0"; then
	    TEMP=`nice vcgencmd measure_temp | cut -f 2 -d "="`
	    echo "ERROR: Over-Temperature or unstable power supply! Current temp:$TEMP"
	    collect_debug
	    ps -ef | nice grep "osd" | nice grep -v grep | awk '{print $2}' | xargs kill -9
	    ps -ef | nice grep "cat /root/telemetryfifo1" | nice grep -v grep | awk '{print $2}' | xargs kill -9
	    while true; do
		killall wbc_status > /dev/null 2>&1
		nice /root/wifibroadcast_status/wbc_status "ERROR: Undervoltage or Overtemp, current temp: $TEMP" 7 55 0
		sleep 6
	    done
	fi
}


# check exit status function
function check_exitstatus {
    STATUS=$1
    case $STATUS in
    9)
	# rx returned with exit code 9 = the interface went down
	# wifi card must've been removed during running
	# check if wifi card is really gone
	NICS2=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v relay | nice grep -v wifihotspot`
	if [ "$NICS" == "$NICS2" ]; then
	    # wifi card has not been removed, something else must've gone wrong
	    echo "ERROR: RX stopped, wifi card _not_ removed!             "
	else
	    # wifi card has been removed
	    echo "ERROR: Wifi card removed!                               "
	fi
    ;;
    2)
	# something else that is fatal happened during running
	echo "ERROR: RX chain stopped wifi card _not_ removed!             "
    ;;
    1)
	# something that is fatal went wrong at rx startup
	echo "ERROR: could not start RX                           "
	#echo "ERROR: could not start RX                           "
    ;;
    *)
	if [  $RX_EXITSTATUS -lt 128 ]; then
	    # whatever it was ...
	    echo "RX exited with status: $RX_EXITSTATUS                        "
	fi
    esac
}


# function tx
function tx_function {
    #if [ "$TXMODE" == "single" ]; then
	#echo -n "Waiting for wifi card to become ready ..."
	#COUNTER=0
	# loop until card is initialized
	#while [ $COUNTER -lt 10 ]; do
    #	    sleep 0.5
    #	    echo -n "."
	#    let "COUNTER++"
    #	    if [ -d "/sys/class/net/$NICS" ]; then
	#	echo -n "card ready"
	#	break
    #	    fi
	#done
    #else
	## just wait some time
	#echo -n "Waiting for wifi cards to become ready ..."
	#sleep 3
    #fi

    echo
    echo
    detect_nics

    sleep 1
    echo

    DRIVER=`cat /sys/class/net/$NICS/device/uevent | nice grep DRIVER | sed 's/DRIVER=//'`
    if [ "$DRIVER" != "ath9k_htc" ]; then #
        VIDEO_FRAMETYPE=1
    fi

    echo "video frametype: $VIDEO_FRAMETYPE"


    # check if over-temperature or under-voltage occured
    if vcgencmd get_throttled | nice grep -q -v "0x0"; then
        TEMP=`nice vcgencmd measure_temp | cut -f 2 -d "="`
        echo "ERROR: Over-Temperature or unstable power supply! Temp:$TEMP"
        collect_debug
    nice -n -9 raspivid -w $WIDTH -h $HEIGHT -fps $FPS -b 3000000 -g $KEYFRAMERATE -t 0 $EXTRAPARAMS -ae 40,0x00,0x8080FF -a "\n\nunder-voltage or over-temperature on TX!" -o - | nice -n -9 /opt/wifibroadcast/wifibroadcast/tx -p 0 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEO_BLOCKLENGTH -t $VIDEO_FRAMETYPE -d $VIDEO_WIFI_BITRATE -y 0 $NICS
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
    nice -n -9 raspivid -w $WIDTH -h $HEIGHT -fps $FPS -b $BITRATE -g $KEYFRAMERATE -t 0 $EXTRAPARAMS $ANNOTATION -o - | nice -n -9 /opt/wifibroadcast/wifibroadcast/tx -p 0 -b $VIDEO_BLOCKS -r $VIDEO_FECS -f $VIDEO_BLOCKLENGTH -t $VIDEO_FRAMETYPE -d $VIDEO_WIFI_BITRATE -y 0 $NICS
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


# function rx

# function osd_tx, runs on osd TX 
function osdtx_function {
    # setup serial port
    #stty -F $FC_TELEMETRY_SERIALPORT $FC_TELEMETRY_STTY_OPTIONS $FC_TELEMETRY_BAUDRATE

    # wait until tx is running to make sure NICS are configured
    echo
    echo -n "Waiting until video TX is running ..."
    VIDEOTXRUNNING=0
    while [ $VIDEOTXRUNNING -ne 1 ]; do
	sleep 0.5
	VIDEOTXRUNNING=`pidof raspivid | wc -w`
	echo -n "."
    done
    echo

    echo "Video running, starting OSD processes ..."

    NICS=`ls /sys/class/net/ | nice grep -v eth0 | nice grep -v lo | nice grep -v usb | nice grep -v intwifi | nice grep -v wlan0`

    DRIVER=`cat /sys/class/net/$NICS/device/uevent | nice grep DRIVER | sed 's/DRIVER=//'`
    if [ "$DRIVER" != "ath9k_htc" ]; then # set frametype to 1 for non-atheros fixed regardless of cts-protection mode
        TELEMETRY_FRAMETYPE=1
    fi

    echo "telemetry frametype: $TELEMETRY_FRAMETYPE"

    echo
    while true; do
        echo "Starting downlink telemetry transmission in $TXMODE mode (FEC: $TELEMETRY_BLOCKS/$TELEMETRY_FECS/$TELEMETRY_BLOCKLENGTH, FC Serialport: $FC_TELEMETRY_SERIALPORT)"
        nice cat $FC_TELEMETRY_SERIALPORT | nice /opt/wifibroadcast/wifibroadcast/tx -p 1 -b $TELEMETRY_BLOCKS -r $TELEMETRY_FECS -f $TELEMETRY_BLOCKLENGTH -m $TELEMETRY_MIN_BLOCKLENGTH -t $TELEMETRY_FRAMETYPE -d $TELEMETRY_WIFI_BITRATE -y 0 $NICS
        ps -ef | nice grep "cat $FC_TELEMETRY_SERIALPORT" | nice grep -v grep | awk '{print $2}' | xargs kill -9
        ps -ef | nice grep "tx -p 1" | nice grep -v grep | awk '{print $2}' | xargs kill -9
	echo "Downlink Telemetry TX exited - restarting ..."
        sleep 1
    done
}


#
function tty1_function {
	echo
	tmessage "Display: `tvservice -s | cut -f 3-20 -d " "`"
	echo
	if [ "$TYPE" == "RX" ]; then
	    rx_function
	else
	    tx_function
	fi
}


#
function tty2_function {
	# only run osdrx if no cam found
	if [ "$TYPE" == "RX" ]; then
	    osdrx_function
	else
	    # only run osdtx if cam found, osd enabled and telemetry input is the tx
	    if [ "$TYPE" == "TX" ] && [ "$TELEMETRY_TRANSMISSION" == "wbc" ]; then
	        osdtx_function
	    fi
	fi
    	echo "OSD not enabled in configfile"
	sleep 365d
}


# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi


# Get settings from /boot
config_convert
check_enabled
source /tmp/wifibroadcast_settings.sh
#collect_debug

# Get bitrate setting and configure
case $BITRATE in
    1)
	UPLINK_WIFI_BITRATE=6
	TELEMETRY_WIFI_BITRATE=6
	if [ "$CTS_PROTECTION" == "Y" ]; then
	    VIDEO_WIFI_BITRATE=12
	else
	    VIDEO_WIFI_BITRATE=6
	fi
	if [ "$TXMODE" != "single" ]; then
	    VIDEO_WIFI_BITRATE=12
	fi
	BITRATE=2500000
    ;;
    2)
	UPLINK_WIFI_BITRATE=12
	TELEMETRY_WIFI_BITRATE=12
	if [ "$CTS_PROTECTION" == "Y" ]; then
	    VIDEO_WIFI_BITRATE=18
	else
	    VIDEO_WIFI_BITRATE=12
	fi
	if [ "$TXMODE" != "single" ]; then
	    VIDEO_WIFI_BITRATE=18
	fi
	BITRATE=4500000
    ;;
    3)
	UPLINK_WIFI_BITRATE=18
	TELEMETRY_WIFI_BITRATE=18
	if [ "$CTS_PROTECTION" == "Y" ]; then
	    VIDEO_WIFI_BITRATE=24
	else
	    VIDEO_WIFI_BITRATE=18
	fi
	if [ "$TXMODE" != "single" ]; then
	    VIDEO_WIFI_BITRATE=24
	fi
	BITRATE=6000000
    ;;
    4)
	UPLINK_WIFI_BITRATE=18
	TELEMETRY_WIFI_BITRATE=24
	if [ "$CTS_PROTECTION" == "Y" ]; then
	    VIDEO_WIFI_BITRATE=36
	else
	    VIDEO_WIFI_BITRATE=24
	fi
	if [ "$TXMODE" != "single" ]; then
	    VIDEO_WIFI_BITRATE=36
	fi
	BITRATE=8500000
    ;;
    5)
	UPLINK_WIFI_BITRATE=24
	TELEMETRY_WIFI_BITRATE=36
	if [ "$CTS_PROTECTION" == "Y" ]; then
	    VIDEO_WIFI_BITRATE=48
	else
	    VIDEO_WIFI_BITRATE=36
	fi
	if [ "$TXMODE" != "single" ]; then
	    VIDEO_WIFI_BITRATE=48
	fi
	BITRATE=11500000
    ;;
esac

# TX telemetry settings
TELEMETRY_BLOCKS=1
TELEMETRY_FECS=0
TELEMETRY_BLOCKLENGTH=32
TELEMETRY_MIN_BLOCKLENGTH=10
FC_TELEMETRY_STTY_OPTIONS="-imaxbel -opost -isig -icanon -echo -echoe -ixoff -ixon"
#
# Updated Settings
#TELEMETRY_BLOCKS=1
#TELEMETRY_FECS=1
#TELEMETRY_BLOCKLENGTH=267
#TELEMETRY_MIN_BLOCKLENGTH=28
#FC_TELEMETRY_STTY_OPTIONS="-icrnl -ocrnl -imaxbel -opost -isig -icanon -echo -echoe -ixoff -ixon"



# RX Display Program
# mmormota's stutter-free hello_video.bin: "hello_video.bin.30-mm" (for 30fps) or "hello_video.bin.48-mm" (for 48 and 59.9fps)
# befinitiv's hello_video.bin: "hello_video.bin.240-befi" (for any fps, use this for higher than 59.9fps)
if [ "$FPS" == "59.9" ]; then
    DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.48-mm
else

    if [ "$FPS" -eq 30 ]; then
	DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.30-mm
    fi
    if [ "$FPS" -lt 60 ]; then
	DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.48-mm
#	DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.240-befi
    fi
    if [ "$FPS" -gt 60 ]; then
	DISPLAY_PROGRAM=/opt/vc/src/hello_pi/hello_video/hello_video.bin.240-befi
    fi
fi

# RX telemetry settings
VIDEO_UDP_BLOCKSIZE=1024
TELEMETRY_UDP_BLOCKSIZE=128

RELAY_VIDEO_BLOCKS=8
RELAY_VIDEO_FECS=4
RELAY_VIDEO_BLOCKLENGTH=1024

RELAY_TELEMETRY_BLOCKS=1
RELAY_TELEMETRY_FECS=0
RELAY_TELEMETRY_BLOCKLENGTH=32

EXTERNAL_TELEMETRY_SERIALPORT_GROUND_STTY_OPTIONS="-imaxbel -opost -isig -icanon -echo -echoe -ixoff -ixon"
TELEMETRY_OUTPUT_SERIALPORT_GROUND_STTY_OPTIONS="-imaxbel -opost -isig -icanon -echo -echoe -ixoff -ixon"

VIDEO_UDP_PORT=5000
RSSI_UDP_PORT=5003

# Some additional settings.....
if cat /boot/osdconfig.txt | grep -q "^#define LTM"; then
    TELEMETRY_UDP_PORT=5001
fi
if cat /boot/osdconfig.txt | grep -q "^#define FRSKY"; then
    TELEMETRY_UDP_PORT=5002
fi
if cat /boot/osdconfig.txt | grep -q "^#define MAVLINK"; then
    TELEMETRY_UDP_PORT=5004
fi

if [ "$CTS_PROTECTION" == "Y" ]; then
    VIDEO_FRAMETYPE=1 # use standard data frames, so that CTS is generated for Atheros
    TELEMETRY_FRAMETYPE=1
    VIDEO_BLOCKLENGTH=1400
else
    VIDEO_FRAMETYPE=5 # use beacon frames, no CTS
    TELEMETRY_FRAMETYPE=5 # use beacon frames, no CTS
fi

if [ "$TXMODE" != "single" ]; then # always type 1 in dual tx mode since ralink beacon injection broken
    VIDEO_FRAMETYPE=1
    TELEMETRY_FRAMETYPE=1
    VIDEO_BLOCKLENGTH=1400
fi

if [ "$CAM" == "0" ]; then # we are RX
    # use fixed 1400bytes on RX to make sure both CTS and no CTS protection works
    VIDEO_BLOCKLENGTH=1400
fi


tx_function & osdtx_function





