#!/bin/bash

# catch Ctrl-C and restore previous configuration
trap "echo 'Quitting..'; sudo $0 $1 stop" 2

# ask something (first parameter) and eventually propose 
# a default value (second parameter) 
function ask {
    echo -n "Enter $1"
    if test -n "$2"
    then
	echo -n " [default $2]"
    fi
    echo -n ": "
    read RESP
}

# select one interface (if a is provided as parameter, all
# interfaces are shown, disabled too
function select_iface {
    
    if test -n "$1" 
    then
	select iface in `ifconfig -s -$1 | awk '{if(NR!=1) print $1}' | tr '\n' ' '` 
	do
            break
	done
    else    
	select iface in `ifconfig -s | awk '{if(NR!=1) print $1}' | tr '\n' ' '` 
	do
            break
	done
    fi
}

# select one essid from a list provided with scanning
function select_essid {
    select es in `sudo iwlist $1 scan | grep ESSID | grep -o "\".*\"" | tr -d "\""` 
    do
        break
    done
}
 
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
	echo 'Choose interface connected to the local network'
        select_iface "a"
        LAN=$iface;
	
	# OBSOLETE
        #ask "name for interface connected to the local network" wlan0   
        ##echo -n 'Enter name for interface connected'
	##echo -n ' to the local network [default wlan0]: '
	##read LAN
	#LAN=$RESP;
       
	#if test -z "$LAN"
	#then
	    #LAN='wlan0'
	#fi
	# END OBSOLETE
	
	echo 'Choose interface connected to the internet'
	select_iface "a"
	INTERNET=$iface;
        # OBSOLETE
	#ask "name for interface connected to the internet" eth0
	##echo -n 'Enter name for interface connected'
	##echo -n ' to the internet [default eth0]: '
	##read INTERNET 
	#INTERNET=$RESP;
	
	#if test -z "$INTERNET"
	#then
	    #INTERNET='eth0'
	#fi
	# END OBSOLETE
		
	echo -n 'Is the local interface a wireless'
	echo -n ' interface? (y/n) [default y]: '
	read resp

	if test "$resp" = "" || test "$resp" = "y"
	then
	    while test -z "$ESSID"
	    do
		ask "essid for ad-hoc wireless network"
	        # OBSOLETE
                #echo -n 'Enter essid for ad-hoc wireless network: '
	        #read ESSID
		# END OBSOLETE
	        ESSID=$RESP;
	    done
	    LOCALWIRELESS=1;
	else
	    LOCALWIRELESS=0;
	fi

	ask 'IP address for local interface' '192.168.1.2'
	
	# OBSOLETE
        #echo -n 'Enter IP Address for local interface'
	#echo -n ' [default 192.168.1.2]: '
	#read IPADDRESS
	# END OBSOLETE
	IPADDRESS=$RESP;
		
	if test -z "$IPADDRESS"
	then
	    IPADDRESS='192.168.1.2'
	fi

	# restarts network interfaces with our parameters
		
	# stops networking subsystem
	sudo /etc/init.d/networking stop
	sudo ifconfig $LAN down
		
	if [[ $LOCALWIRELESS ]]
	then
	    sudo iwconfig $LAN mode Ad-Hoc 
	    sudo iwconfig $LAN essid $ESSID
	fi
		
	sudo ifconfig $LAN up $IPADDRESS
	sudo dhclient $INTERNET
	
	# nats packets from and to the client
	
	# saves pre-configuration
	sudo iptables-save -c > "$HOME/.msq-iptables.bkp"
	
	# flushes filter table
	sudo iptables -F

	# flushes nat table
	sudo iptables -t nat -F

	# sets the policies for the chains in the filter 
	# table: INPUT OUTPUT & FORWARD (list of rules)
	sudo iptables -P INPUT ACCEPT
	sudo iptables -P OUTPUT ACCEPT
	sudo iptables -P FORWARD DROP

	# inserts rules in the INPUT chain
	sudo iptables -I INPUT 1 -i ${LAN} -j ACCEPT
	sudo iptables -I INPUT 1 -i lo -j ACCEPT

	# appends more rules at the end of the INPUT chain
	sudo iptables -A INPUT -p UDP --dport bootps ! -i ${LAN} -j REJECT
	sudo iptables -A INPUT -p UDP --dport domain ! -i ${LAN} -j REJECT
	sudo iptables -A INPUT -p TCP ! -i ${LAN} -d 0/0 --dport 0:1023 -j DROP
	sudo iptables -A INPUT -p UDP ! -i ${LAN} -d 0/0 --dport 0:1023 -j DROP

	# inserts and appends rules in the FORWARD chain
	sudo iptables -I FORWARD -i ${LAN} -d 192.168.0.0/255.255.0.0 -j DROP
	sudo iptables -A FORWARD -i ${LAN} -s 192.168.0.0/255.255.0.0 -j ACCEPT
	sudo iptables -A FORWARD -i ${INTERNET} -d 192.168.0.0/255.255.0.0 -j ACCEPT
		
	# appends at the POSTROUTING table the target MASQUERADE to map
	# the destination address of a packet that is leaving with the network
	# address of the interface the packet is going out
	sudo iptables -t nat -A POSTROUTING -o ${INTERNET} -j MASQUERADE

	# this is used to allow ip forwarding by our host (server) that is the
	# default gateway for the client
	sudo sysctl net.ipv4.ip_forward=1;

	# sets reverse path filter on all interfaces; this could be problematic 
	# if the client is a multihomed host; we assume it isn't
	for f in `ls /proc/sys/net/ipv4/conf/` 
	do 
	    sudo sysctl net.ipv4.conf."$f".rp_filter=1; 
	done

	exit 0

    elif test "$2" = "stop"
    then
	
        # unsets ip packets forwarding
	sudo sysctl net.ipv4.ip_forward=0;
	
	# unsets reverse path filter on all interfaces
	for f in `ls /proc/sys/net/ipv4/conf/` 
	do 
	    sudo sysctl net.ipv4.conf."$f".rp_filter=0; 
	done

	# restore pre-configuration
	sudo iptables-restore -c < "$HOME/.msq-iptables.bkp"

	# restarts networking subsystem
	sudo /etc/init.d/networking start
    
	exit 0
    fi

elif test "$1" = "client"
then
    
    if test "$2" = "start"
    then

        # pulls down other interfaces
        while [[ "$PULLDOWN" != "n" ]] || [[ "$PULLDOWN" != "no" ]]
	do
	    echo '--Network interfaces UP'
	    ifconfig -s | awk '{if(NR!=1) print $1}' | tr '\n' ' '
	    echo
	    echo 'Do you want to pull down anyone of these?'
	    read PULLDOWN
	    if [[ "$PULLDOWN" = "y" ]] || [[ "$PULLDOWN" = "yes" ]]
	    then
		echo 'Select network interface(s) to set down'
		select_iface
		sudo ifconfig $iface down
	    fi
        done
	
	# OBSOLETE
        #ask 'network interface to set down' 'eth0'
        ##echo -n 'Enter network interface to set down [default eth0]: '
        ##read DOWN
	#DOWN=$RESP
	#if test -z $DOWN
	#then
    	    #DOWN='eth0'
	#fi
	# END OBSOLETE
	
	echo 'Select network interface to use as bridge to server'
	select_iface
	LINK=$iface;
	
	# OBSOLETE
	#ask 'network interface to use as bridge to master' wlan0
        ##echo -n 'Enter network interface to use as bridge to master [default wlan0]: '
        ##read LINK
	#LINK=$RESP;
	#if test -z $LINK
	#then
	    #LINK='wlan0'
	#fi
	# END OBSOLETE
	
	echo -n 'Is the local interface a wireless'
	echo -n ' interface? (y/n) [default y]: '
	read resp

	if test "$resp" = "" || test "$resp" = "y"
	then
	    LOCALWIRELESS=1;
	    while test -z $ESSID
	    do 
		echo 'Enter essid of the wireless network you want to use'
		select write_scan in 'I want to insert essid manually' 'I want to scan for active network essids' 
		do
		    if [[ $write_scan -eq 1 ]]
		    then
			ask 'ad-hoc wireless network essid'
            
	                # OBSOLETE
                        #echo -n 'Enter ad-hoc wireless network essid: '
                        #read ESSID
	                # END OBSOLETE
		        ESSID=$RESP;
		    else
			select_essid $LINK
			ESSID=$es;
		    fi
		break
	    done
	done
	else
	    LOCALWIRELESS=0;
	fi

	ask 'ip address you want to use' '192.168.1.3'
        
	# OBSOLETE
        #echo -n 'Enter ip address you want to use [default 192.168.1.3]: '
        #read IPADDRESS
	# END OBSOLETE

	IPADDRESS=$RESP;
	if test -z $IPADDRESS
	then
	    IPADDRESS='192.168.1.3'
	fi
	
	ask 'gateway (master) ip address' '192.168.1.2'
        
	# OBSOLETE
        #echo -n 'Enter gateway (master) ip address [default 192.168.1.2]: '
        #read GATEWAY
	# END OBSOLETE

	if test -z $GATEWAY
	then
	    GATEWAY='192.168.1.2'
	fi

        # restarts network interfaces with our parameters 
	sudo /etc/init.d/networking stop
	if [[ $LOCALWIRELESS ]]
	then
	    sudo /etc/init.d/wicd stop
	fi
        sudo killall dhclient
	sudo killall dhcpcd
	
	sudo ifconfig $LINK down
	if [[ $LOCALWIRELESS ]]
	then
	    sudo iwconfig $LINK mode Ad-Hoc
	    sudo iwconfig $LINK essid $ESSID
	fi
        sudo ifconfig $LINK up $IPADDRESS
    
        # add the server as default gateway in the routing table
	sudo route add default gw $GATEWAY

	# is this correct? should we swap the two paths?
	sudo cp /etc/resolv.conf.bak /etc/resolv.conf

	exit 0

    elif test "$2" = "stop"
    then
	
	# wiping away the default route
	sudo route del default
	
	# restores network interfaces
	sudo /etc/init.d/networking start
	sudo /etc/init.d/wicd start
	
	sudo dhclient 
	
        # is this necessary?
	sudo dhcpcd

	# is this correct?
        #sudo mv /etc/resolv.conf.bak /etc/resolv.conf
	
	exit 0
    fi

fi

exit 0

