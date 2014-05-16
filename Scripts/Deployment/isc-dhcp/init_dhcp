#!/bin/bash
#
#Initial script to install the initial packages for DHCP Server
#Author: Marc López Rubio
#Date 15/05/2014

#Download Packages
pkgin -y in isc-dhcpd dhcpd-pools

#make symbolic links for the dhcpd-pools to work
ln -s /opt/local/etc/dhcp/dhcpd.conf /etc/dhcpd.conf
ln -s /var/db/isc-dhcp/dhcpd.leases /var/db/dhcpd.leases

#Enable service in SMF
/usr/sbin/svcadm enable svc:/pkgsrc/isc-dhcpd:default