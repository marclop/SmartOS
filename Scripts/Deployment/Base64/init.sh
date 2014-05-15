#!/bin/bash
#
#Initial script to set the initial environment for the Smartos Base 64-Bit Zone
#Author: Marc L�pez Rubio
#Date 15/05/2014

#Set up the env
PATH=/usr/local/sbin:/usr/local/bin:/opt/local/sbin:/opt/local/bin:/usr/sbin:/usr/bin:/sbin
curl -k -o /opt/local/lib/svc/manifest/ssh.xml https://raw.githubusercontent.com/marclop/SmartOS/master/Scripts/Deployment/Base64/ssh.xml
curl -k -O  https://raw.githubusercontent.com/marclop/SmartOS/master/Scripts/Deployment/Base64/pw.sh && chmod u+x pw.sh
tz="Europe/Madrid"

#Set packages to install, Update repository and upgrade all system packages
pkgin up && pkgin -y fug pkgin -y in tcl-expect

#Set Timezone
sm-set-timezone $tz

#Correct vim color scheme to desert
echo "colorscheme desert" >> /home/admin/.vimrc
echo "colorscheme desert" >> /root/.vimrc
echo "colorscheme desert" >> /etc/skel/.vimrc

#Set root and admin passowrd accounts to a 32 character random string and sets it to the Zone Internal Metadata
#For more information on pw.sh script look at the sources
for i in root admin
	do
		./pw.sh $i
	done

#Import and enable the ssh.xml manifest for SSH support
svccfg import /opt/local/lib/svc/manifest/ssh.xml
svcadm enable ssh

#Build desired image from packets
case $choice in
	dhcp)
		curl -k -O  https://raw.githubusercontent.com/marclop/SmartOS/master/Scripts/Deployment/isc-dhcp/init_dhcp.sh && chmod u+x init_dhcp.sh
		./init_dhcp.sh
		;;
	*)
		echo $"Usage: $0 {dhcp|rails}"
		exit 1
esac
