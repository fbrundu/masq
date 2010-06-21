#!/bin/bash

if test "$#" != "2"
then
	echo 'Usage: masq server|client start|stop'
	exit 1
fi

if test "$1" = "server"
then

	if test "$2" = "start"
	then
		# sets variables
		echo -n 'Enter interface name for ad-hoc wireless network [default wlan0]: '
		read LAN

		if test "$LAN" = ""
		then
			LAN='wlan0'
		fi

		echo -n 'Enter interface name for wired network [default eth0]: '
		read INTERNET 

		if test "$INTERNET" = ""
		then
			INTERNET='eth0'
		fi

		echo -n 'Enter essid of ad-hoc wireless network: '
		read ESSID

		echo -n 'Enter IP Address for ad-hoc wireless network interface [default 192.168.1.2]: '
		read IPADDRESS

		if test "$IPADDRESS" = ""
		then
			IPADDRESS='192.168.1.2'
		fi

		# restarts network interfaces with our parameters
		sudo /etc/init.d/networking stop
		sudo ifconfig $LAN down
		sudo iwconfig $LAN mode Ad-Hoc
		sudo iwconfig $LAN essid $ESSID
		sudo ifconfig $LAN up $IPADDRESS
		sudo dhclient $INTERNET

		# nats packets from and to the slave
		sudo iptables -F
		sudo iptables -t nat -F

		sudo iptables -P INPUT ACCEPT
		sudo iptables -P OUTPUT ACCEPT
		sudo iptables -P FORWARD DROP

		sudo iptables -I INPUT 1 -i ${LAN} -j ACCEPT
		sudo iptables -I INPUT 1 -i lo -j ACCEPT
		sudo iptables -A INPUT -p UDP --dport bootps ! -i ${LAN} -j REJECT
		sudo iptables -A INPUT -p UDP --dport domain ! -i ${LAN} -j REJECT

		sudo iptables -A INPUT -p TCP ! -i ${LAN} -d 0/0 --dport 0:1023 -j DROP
		sudo iptables -A INPUT -p UDP ! -i ${LAN} -d 0/0 --dport 0:1023 -j DROP

		sudo iptables -I FORWARD -i ${LAN} -d 192.168.0.0/255.255.0.0 -j DROP
		sudo iptables -A FORWARD -i ${LAN} -s 192.168.0.0/255.255.0.0 -j ACCEPT
		sudo iptables -A FORWARD -i ${INTERNET} -d 192.168.0.0/255.255.0.0 -j ACCEPT
		sudo iptables -t nat -A POSTROUTING -o ${WAN} -j MASQUERADE

		# this is used to allow ip forwarding by our host (master) that is the
		# default gateway for the slave
		sudo sysctl net.ipv4.ip_forward=1;

		# sets reverse path filter on all interfaces; this could be problematic 
		# if the slave is a multihomed host; we assume it isn't
		for f in `ls /proc/sys/net/ipv4/conf/` ; do sudo sysctl net.ipv4.conf."$f".rp_filter=1 ; done

		exit 0

	elif test "$2" = "stop"
	fi

elif test "$1" = "client"

	if test "$2" = "start"
	then

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

	elif test "$2" = "stop"
	fi

fi

exit 0

