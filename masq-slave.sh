#!/bin/bash

# version: 0.2
# brief changelog
#	* changed deprecated setting of proc variables by using sysctl
#	* for `iptables` changed deprecated option usage from
#		-i ! <something>
#	  to
#		! -i <something>
#	* sudoed everything
# 	* changed variable name "WAN" to "INTERNET"

# sets variables
echo -n 'Enter wired network interface to set down [default eth0]: '
read ETH
if test $ETH = ""
then
	ETH='eth0'
fi

echo -n 'Enter wireless network interface to use as bridge to master [default wlan0]: '
read WLAN
if test $WLAN = ""
then
	WLAN='wlan0'
fi

echo -n 'Enter ip address you want to use [default 192.168.1.77]: '
read IPADDRESS
if test $IPADDRESS = ""
then
	IPADDRESS='192.168.1.77'
fi

echo -n 'Enter ad-hoc wireless network essid: '
read ESSID

echo -n 'Enter gateway (master) ip address [default 192.168.1.2]: '
read GATEWAY
if test $GATEWAY = ""
then
	GATEWAY='192.168.1.2'
fi

# restarts network interfaces with our parameters 
/etc/init.d/networking stop
/etc/init.d/wicd stop
killall dhclient
killall dhcpcd
ifconfig $ETH down
ifconfig $WLAN down
iwconfig $WLAN mode Ad-Hoc
iwconfig $WLAN essid $ESSID
ifconfig $WLAN up $IPADDRESS

# add our gateway as default gateway in the routing table
route add default gw $GATEWAY

cp /etc/resolv.conf.bak /etc/resolv.conf

exit 0

