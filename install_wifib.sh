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

# Get updated and install packages
sudo apt-get update
sudo apt-get install -y git
sudo apt-get install -y libpcap0.8-dev # For wifibroadcast core 
sudo apt-get install -y wiringpi # For wifibroadcast core
sudo apt-get install -y libjpeg8-dev indent libfreetype6-dev ttf-dejavu-core # Needed DejaVu fonts, and the jpeg and freetype libraries for OpenVG
sudo apt-get install -y libsdl1.2-dev # For WifiBroadcast_rc
sudo apt-get install -y libsdl2-dev # For WifiBroadcast_rc
sudo apt-get install -y dos2unix # convert text files from /boot from dos format to unix

# Build and Install OpenVG for wifibroadcast_osd
cd ~
sudo git clone https://github.com/ajstarks/openvg.git # OpendVG for raspberry pi
cd openvg
make all
make library
make install
