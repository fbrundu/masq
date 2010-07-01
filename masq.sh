#!/bin/bash

# catch Ctrl-C and restore previous configuration 
# TODO: restore config
trap "echo 'Quitting..'; exit 2" 2

# global variables

# if 1 masq is started in debug mode for the ui
DEBUG_UI=0;

# if 1 masq sets default values for some variables
# such ip address
DM=0;

# if 0 masq asks which interfaces to pulldown
# at startup in client mode
NP=0;

# masq thinks by default that the interface of
# the local lan is not a wireless interface
LOCALWIRELESS=0;

# ask something (first parameter) and eventually propose 
# a default value (second parameter) 
function ask {
    
    echo -n "Enter $1"
    if [ -n "$2" ]
    then
        echo -n " [default $2]"
    fi
    echo -n ": "
    read RESP
}

# select one interface (if a is provided as parameter, all
# interfaces are shown, disabled too
function select_iface {
    
    if [ -n "$1" ] 
    then
    select iface in `sudo ifconfig -s -$1 | awk '{if(NR!=1) print $1}' | tr '\n' ' '` 
    do
        break
    done
    else    
        select iface in `sudo ifconfig -s | awk '{if(NR!=1) print $1}' | tr '\n' ' '` 
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
 
# if we have not enough arguments prints help and exit with value 1
if [ $# -lt 2 ]
then
    echo
    echo '  Usage: masq server|client start|stop [options]'
    echo
    echo '  --Available Options:'
    echo
    echo '      -d=ui' 
    echo '      --debug=ui'
    echo '          TO DEBUG UI'
    echo '      -l=<local_interface_name>'
    echo '      --local=<local_interface_name>' 
    echo '          NAME ASSIGNED TO THE LOCAL LAN INTERFACE (NET BETWEEN CLIENT AND SERVER)'
    echo '      -e=<extern_interface_name>'
    echo '      --extern=<extern_interface_name>'
    echo '          NAME ASSIGNED TO THE EXTERN NETWORK INTERFACE (NET BETWEEN SERVER AND INTERNET)'
    echo '      -s=<essid>'
    echo '      --essid=<essid>'
    echo '          ESSID OF THE LOCAL WLAN INTERFACE (WLAN BETWEEN CLIENT AND SERVER)'
    echo '      -np'
    echo '      --no-pulldown'
    echo '          DO NOT ASK FOR INTERFACES TO PULLDOWN AT STARTUP'
    echo '      -dm'
    echo '      --default-mode'
    echo '          USE DEFAULT VALUES FOR NETWORK ADDRESSES'
    echo
    echo '  --Exit Values:'
    echo
    echo '      0 No error'
    echo '      1 Not enough arguments'
    echo '      2 Process interrupted by the user'
    echo '      3 Wrong combinations of options'
    echo
    exit 1
fi

# else parses options
for i in $@
do
    case $i in
    "server" | "client" | "start" | "stop")
        ;;
    "-d=ui" | "--debug=ui")
        DEBUG_UI=1;
        ;;
    -l=[a-zA-Z0-9]* | --local=[a-zA-Z0-9]*)
        LAN=`echo $i | cut -f 2 -d '='`;
        ;;
    -e=[a-zA-Z0-9]* | --extern=[a-zA-Z0-9]*)
        EXT=`echo $i | cut -f 2 -d '='`;
        ;;
    -s=[a-zA-Z0-9]* | --essid=[a-zA-Z0-9]*)
        ESSID=`echo $i | cut -f 2 -d '='`;
        ;;
    "-np" | "--no-pulldown")
        NP=1;
        ;;
    "-dm" | "--default-mode")
        DM=1
        ;;
    *)
        echo 'Wrong combination of options'
        exit 3
        ;;
    esac
done

# if mode is server
if [ "$1" = "server" ]
then

    # if action is start
    if [ "$2" = "start" ]
    then
        
        # sets variables
        
        # if local interface is not set asks for it
        if [ -z "$LAN" ]
        then
            echo 'Choose interface connected to the local network:'
            select_iface "a"
            LAN=$iface;
        fi
    
        # if extern interface is not set asks for it
        if [ -z "$EXT" ]
        then
            echo 'Choose interface connected to the internet:'
            select_iface "a"
            EXT=$iface;
        fi

        # tests if local interface is a wireless interface
        iwconfig $LAN &> /dev/null
        
        # if local interface is a wireless interface
        if [ $? -eq 0 ]
        then
            # asks for an essid for the WLAN to create
            while [ -z "$ESSID" ]
            do
                ask "essid for ad-hoc wireless network"
                ESSID=$RESP;
            done
            LOCALWIRELESS=1;
        fi
        
        # if default mode is disabled asks for IP address
        # for the local interface
        if [ $DM -ne 1 ]
        then
            ask 'IP address for local interface' '192.168.1.2'
            IPADDRESS=$RESP;
        fi

        # if IPADDRESS is not set, uses the default value
        if [ -z "$IPADDRESS" ]
        then
            IPADDRESS='192.168.1.2'
        fi
        
        # if DEBUG_UI is set, prints some variables
        if [ $DEBUG_UI -eq 1 ]
        then
            echo "Local iface chosen: $LAN"
            echo "Bridge iface chosen: $EXT"
            echo "Local iface wireless: $LOCALWIRELESS essid: $ESSID"
            echo "Ip address: $IPADDRESS"
        fi
        
        # if DEBUG_UI is set, doesn't anything 
        if [ $DEBUG_UI -eq 0 ]
        then
            # else restarts network interfaces with our parameters
        
            # stops networking subsystem
            sudo /etc/init.d/networking stop
            
            # pulls down local interface
            sudo ifconfig $LAN down
            
            # if local interface is a wireless interface
            if [ $LOCALWIRELESS ]
            then
                # sets up mode and essid for that
                sudo iwconfig $LAN mode Ad-Hoc 
                sudo iwconfig $LAN essid $ESSID
            fi
            
            # pulls up local interace 
            sudo ifconfig $LAN up $IPADDRESS

            # calls dhcp configuration for the extern 
            # interface
            sudo dhclient $EXT
            
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
            sudo iptables -A FORWARD -i ${EXT} -d 192.168.0.0/255.255.0.0 -j ACCEPT
                
            # appends at the POSTROUTING table the target MASQUERADE to map
            # the destination address of a packet that is leaving with the network
            # address of the interface the packet is going out
            sudo iptables -t nat -A POSTROUTING -o ${EXT} -j MASQUERADE
    
            # this is used to allow ip forwarding by our host (server) that is the
            # default gateway for the client
            sudo sysctl net.ipv4.ip_forward=1;
        
            # sets reverse path filter on all interfaces; this could be problematic 
            # if the client is a multihomed host; we assume it isn't
            for f in `ls /proc/sys/net/ipv4/conf/` 
            do 
                sudo sysctl net.ipv4.conf."$f".rp_filter=1; 
            done
        fi
        exit 0

    elif [ "$2" = "stop" ]
    then
    
        if [ $DEBUG_UI -eq 0 ]
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
        fi
        exit 0
    fi

elif [ "$1" = "client" ]
then
    
    if [ "$2" = "start" ]
    then
        
        if [ $DEBUG_UI -eq 0 ] && [ $NP -ne 1 ]
        then
            # pulls down other interfaces
            while [ "$PULLDOWN" != "n" ] || [ "$PULLDOWN" != "no" ]
            do
                # prints active network interfaces 
                echo '--Network interfaces UP'
                sudo ifconfig -s | awk '{if(NR!=1) print $1}' | tr '\n' ' '
                echo
                echo 'Do you want to pull down anyone of these?'
                read PULLDOWN
                if [ "$PULLDOWN" = "y" ] || [ "$PULLDOWN" = "yes" ]
                then
                    echo 'Select network interface(s) to set down'
                    select_iface
                    sudo ifconfig $iface down
                fi
            done
        fi
        
        # if local interface is not setted asks 
        # the user which one to use
        if [ -z "$LAN" ]
        then
            echo 'Select network interface to use as bridge to server'
            select_iface
            LAN=$iface;
        fi

        # tests if link interface is wireless
        iwconfig $LAN &> /dev/null
        
        # if wireless
        if [ $? -eq 0 ]
        then
            LOCALWIRELESS=1;
            # asks for essid
            while [ -z $ESSID ]
            do 
                echo 'Enter essid of the wireless network you want to use by'
                select ws in insertion scanning 
                do
                    # essid is inserted manually by the user
                    if [ "$ws" = "insertion" ]
                    then
                        ask 'ad-hoc wireless network essid'
                        ESSID=$RESP;
                    # essid is selected from a list of active essids
                    elif [ "$ws" = "scanning" ]
                    then
                        echo 'Scanning..'
                        select_essid $LAN
                        ESSID=$es;
                    fi
                    break
                done
            done
        fi
       
        # if default mode is not setted, asks for ip address
        if [ $DM -ne 1 ]
        then
            ask 'ip address you want to use' '192.168.1.3'
            IPADDRESS=$RESP;
        fi
        
        # if ip address is not setted yet, 
        # inserts default value
        if [ -z $IPADDRESS ]
        then
            IPADDRESS='192.168.1.3'
        fi
        
        # if default mode is not setted, 
        # asks for gateway address
        if [ $DM -ne 1 ]
        then
            ask 'gateway (master) ip address' '192.168.1.2'
            GATEWAY=$RESP;
        fi
        
        # if ip address is not setted yet, 
        # inserts default value
        if [ -z $GATEWAY ]
        then
            GATEWAY='192.168.1.2'
        fi
        
        # if in debug mode prints some values
        if [ $DEBUG_UI -eq 1 ]
        then
            echo "Bridge iface: $LAN"
            echo "Local link wireless: $LOCALWIRELESS essid: $ESSID"
            echo "Ip address: $IPADDRESS"
            echo "Gateway: $GATEWAY"            
        fi
        
        # if not in debug mode
        if [ $DEBUG_UI -eq 0 ]
        then
            # restarts network interfaces with our parameters 
            sudo /etc/init.d/networking stop
            if [ $LOCALWIRELESS ]
            then
                sudo /etc/init.d/wicd stop
            fi
            
            # kills all dhcp related process
            sudo killall dhclient
            sudo killall dhcpcd
            
            # sets down local interface
            sudo ifconfig $LAN down
            if [ $LOCALWIRELESS ]
            then
                # if it is a wireless interfaca
                # inserts essid and set ad-hoc mode
                sudo iwconfig $LAN mode Ad-Hoc
                sudo iwconfig $LAN essid $ESSID
            fi
            # sets up local interface
            sudo ifconfig $LAN up $IPADDRESS
    
            # add the server as default gateway in the routing table
            sudo route add default gw $GATEWAY

            # is this correct? should we swap the two paths?
            sudo cp /etc/resolv.conf.bak /etc/resolv.conf
        fi
        exit 0

    elif [ "$2" = "stop" ]
    then
        if [ $DEBUG_UI -eq 0 ]
        then
            # wiping away the default route
            sudo route del default
    
            # restores network interfaces
            sudo /etc/init.d/networking start
            sudo /etc/init.d/wicd start
            
            # starts dhclient to obtain
            # a lease
            sudo dhclient 
        
            # is this necessary?
            sudo dhcpcd

            # is this correct?
            #sudo mv /etc/resolv.conf.bak /etc/resolv.conf
        fi
        exit 0
    fi
fi

exit 0

