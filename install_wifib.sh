#!/bin/bash
#

# Check if running as root
if [ $(id -u) -ne 0 ]; then
   echo >&2 "Installation must be run as root"
   exit 1
fi

# Output
set -e
set -x

# Install from directory
DIR_INSTALL=$(pwd)
# Install to directory
DIR_INSTALL_WIFIBROADCAST=/usr/local/bin/wifibroadcast

# Get updated and install packages
echo "Updating repository and installing required packages..."
sudo apt-get update
sudo apt-get install -y git
sudo apt-get install -y libpcap0.8-dev # For wifibroadcast core 
sudo apt-get install -y wiringpi # For wifibroadcast core
sudo apt-get install -y libjpeg8-dev indent libfreetype6-dev ttf-dejavu-core # Needed DejaVu fonts, and the jpeg and freetype libraries for OpenVG
sudo apt-get install -y libsdl1.2-dev # For WifiBroadcast_rc
sudo apt-get install -y libsdl2-dev # For WifiBroadcast_rc
sudo apt-get install -y dos2unix # convert text files from /boot from dos format to unix

# Build and Install OpenVG for wifibroadcast_osd
echo "Cloning OpenVG repository and build,make,install..."
cd ~
sudo git clone https://github.com/ajstarks/openvg.git # OpendVG for raspberry pi
cd openvg
make all
make library
make install

# Clone repository
echo "Cloning wifibroadcast repository and build,make,install..."
cd  ~
git clone https://github.com/terial/cc_wifib.git

# Copy configuration text files to /boot
cp $DIR_INSTALL/config/apconfig.txt /boot/apconfig.txt
cp $DIR_INSTALL/config/joyconfig.txt /boot/joyconfig.txt
cp $DIR_INSTALL/config/osdconfig.txt /boot/osdconfig.txt
cp $DIR_INSTALL/config/wifibroadcast-1.txt /boot/wifibroadcast-1.txt

# Copy wifibroadcast files to DIR_INSTALL_WIFIBROADCAST
cp -a $DIR_INSTALL/wifibroadcast/. DIR_INSTALL_WIFIBROADCAST/wifibroadcast
cp -a $DIR_INSTALL/wifibroadcast_misc/. DIR_INSTALL_WIFIBROADCAST/wifibroadcast_misc
cp -a $DIR_INSTALL/wifibroadcast_osd/. DIR_INSTALL_WIFIBROADCAST/wifibroadcast_osd
cp -a $DIR_INSTALL/wifibroadcast_rc/. DIR_INSTALL_WIFIBROADCAST/wifibroadcast_rc
cp -a $DIR_INSTALL/wifibroadcast_status/. DIR_INSTALL_WIFIBROADCAST/wifibroadcast_status

# Using dos2unix, copy the configuration files from /boot and rename as needed
# using flag -n will always write to a new file.
dos2unix -n /boot/osdconfig.txt DIR_INSTALL_WIFIBROADCAST/wifibroadcast_osd/osdconfig.h
dos2unix -n /boot/joyconfig.txt DIR_INSTALL_WIFIBROADCAST/wifibroadcast_rc/rctx.h > /dev/null 2>&1
#dos2unix -n /boot/apconfig.txt /tmp/apconfig.txt # unused until ap is setup

make all
cd ..
cd cd wifibroadcast_osd
make all
cd ..
cd wifibroadcast_rc
chmod 755 build.sh
./build.sh
cd..
cd wifibroadcast_status
make all


