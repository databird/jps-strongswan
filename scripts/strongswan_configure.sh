#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/..";

action="$1"
baseUrl="$2"
keyexchange="$3"
left="$4"
leftsubnet="$5"
right="$6"
rightsubnet="$7"
psk="$8"
ike="$9"
esp="${10}"
hosts="${11}"
config_setup="${12}"
config_tunnel="${13}"

ipsecConf="/etc/strongswan/ipsec.conf"
ipsecSecrets="/etc/strongswan/ipsec.secrets"
hostsFile="/etc/hosts"

function hostsFileCleanup {
    grep "#strongswan mark" $hostsFile 2>1 >/dev/null
    if [ $? -eq 0 ]; then
        blockStart=$(grep -n "#strongswan mark" $hostsFile | awk -F ":" '{print $1}' | head -n 1)
        blockEnd=$(grep -n "#strongswan mark" $hostsFile | awk -F ":" '{print $1}' | tail -n 1)
        sed "$blockStart,$blockEnd d" -i $hostsFile
    fi

    sed -i '/^$/d' $hostsFile
    echo "" >> $hostsFile
}

if [ "$action" == "uninstall" ]; then
    hostsFileCleanup;

    exit 0;
fi

# left=$(hostname -I | awk '{print $2}')
# left=$(ip addr show | grep "venet" | grep "inet " | grep -v 127.0.0.1 | grep -v 10.10 | awk '{print $2}' | sed 's#/.*##')
# leftSubnet=$(hostname -I | awk '{print $3}')"/32"
# leftSubnet=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | grep 10.10 | awk '{print $2}' | sed 's#/.*##')"/32"

#ipsec.conf

mkdir -p /etc/strongswan/

stat $ipsecConf  2>1 >/dev/null
if [ $? -gt 0 ]; then
    curl -fsSL "${baseUrl}/scripts/ipsec.conf.template" -o $ipsecConf;
fi

grep -q "conn myVPN" $ipsecConf 2>1 >/dev/null
if [ $? -gt 0 ]; then
    cp -p $ipsecConf $ipsecConf.$(date +%F:%R:%S)
    curl -fsSL "${baseUrl}/scripts/ipsec.conf.template" -o $ipsecConf;
fi

sed "s#keyexchange=.*#keyexchange=$keyexchange#" -i $ipsecConf
sed "s#left=.*#left=$left#" -i $ipsecConf
sed "s#leftsubnet=.*#leftsubnet=$leftsubnet#" -i $ipsecConf
sed "s#leftid=.*#leftid=$left#" -i $ipsecConf

sed "s#ike=.*#ike=$ike#" -i $ipsecConf
sed "s#esp=.*#esp=$esp#" -i $ipsecConf

sed "s#right=.*#right=$right#" -i $ipsecConf
sed "s#rightid=.*#rightid=$right#" -i $ipsecConf

escaped_config_setup=$(printf '%s\n' "$config_setup" | sed 's/[&/\#"]/\\&/g')
escaped_config_tunnel=$(printf '%s\n' "$config_tunnel" | sed 's/[&/\#"]/\\&/g')
sed "s|#\[custom_config_setup\]|$escaped_config_setup|" -i $ipsecConf
sed "s|#\[custom_config_tunnel\]|$escaped_config_tunnel|" -i $ipsecConf

if [ "$keyexchange" == "ikev1" ]; then
    IFS=',' read -r -a rightSubnets_ <<< $rightsubnet
    rightSubnets=()
    for subnet in ${rightSubnets_[*]}; do
        rightSubnets+=("$(echo $subnet | sed 's# ##g' )")
    done;
    firstSubnet=${rightSubnets[0]}
    
    sed "s#rightsubnet=.*#rightsubnet=$firstSubnet#" -i $ipsecConf

    for subnet in ${rightSubnets[*]}; do
        if [ "$subnet" != "$firstSubnet" ]; then
            echo "$subnet"
            grep -q "conn.*$subnet" $ipsecConf
            if [ $? -eq 0 ]; then
                blockStart=$(grep -n "conn.*$subnet" $ipsecConf | awk -F ":" '{print $1}')
                if [ $(grep "conn.*$subnet" $ipsecConf -A 99  | grep conn -m 2 |wc -l) -lt 2 ]; then
                    blockEnd=$(cat -n $ipsecConf | tail -n 1 | awk '{print $1}')
                else
                    nextBlock=$(grep "conn.*$subnet" $ipsecConf -A 99  | grep conn -m 2 -B 99 | tail -n 1)
                    blockEnd=$(($(grep -n "$nextBlock" $ipsecConf | awk -F ":" '{print $1}')-1))
                fi
                sed "$blockStart,$blockEnd d" -i $ipsecConf
                nextBlock=$(cat -n $ipsecConf | tail -n 1 | awk '{print $1}')
                blockEnd=$nextBlock
            fi
            echo "conn $subnet" >> $ipsecConf
            echo "        also=myVPN" >> $ipsecConf
            echo "        rightsubnet=$subnet" >> $ipsecConf
            echo "        auto=start" >> $ipsecConf
            echo "" >> $ipsecConf
        fi
    done;

elif [ "$keyexchange" == "ikev2" ]; then
    sed "s#rightsubnet=.*#rightsubnet=$rightsubnet#" -i $ipsecConf

    if [ $(grep "conn.*myVPN" $ipsecConf -A 99  | grep conn |wc -l) -gt 1 ]; then
        nextBlock=$(grep "conn.*myVPN" $ipsecConf -A 99  | grep conn -m 2 | tail -n 1)
        blockStart=$(grep -n "$nextBlock" $ipsecConf | awk -F ":" '{print $1}')
        blockEnd=$(cat -n $ipsecConf | tail -n 1 | awk '{print $1}')

        sed "$blockStart,$blockEnd d" -i $ipsecConf

        nextBlock=$(cat -n $ipsecConf | tail -n 1 | awk '{print $1}')
        blockEnd=$nextBlock
    fi

fi

#ipsec.secrets

stat $ipsecSecrets  2>1 >/dev/null
if [ $? -gt 0 ]; then
    touch $ipsecSecrets;
fi

grep -q "$right" $ipsecSecrets >/dev/null 2>&1
if [ $? -eq 0 ]; then
    cp -p $ipsecSecrets $ipsecSecrets.$(date +%F:%R:%S)
    sed "s#.*$right.*##" -i $ipsecSecrets
fi

# cho "$left $right : PSK $psk" >> $ipsecSecrets
echo "$left : PSK $psk" >> $ipsecSecrets
echo "$right : PSK $psk" >> $ipsecSecrets

sed -i '/^$/d' $ipsecSecrets

echo "" >> $ipsecSecrets


grep -q "^net.ipv4.ip_forward=" /etc/sysctl.conf 2>1 >/dev/null
if [ $? -eq 0 ]; then
    sed 's#net.ipv4.ip_forward=.*#net.ipv4.ip_forward=1#' -i /etc/sysctl.conf
    sed 's#net.ipv6.conf.all.forwarding=.*#net.ipv6.conf.all.forwarding=1#' -i /etc/sysctl.conf
    sed 's#net.ipv4.conf.all.accept_redirects=.*#net.ipv4.conf.all.accept_redirects=0#' -i /etc/sysctl.conf
    sed 's#net.ipv4.conf.all.send_redirects=.*#net.ipv4.conf.all.send_redirects=0#' -i /etc/sysctl.conf
else    
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
    echo "net.ipv4.conf.all.accept_redirects=0" >> /etc/sysctl.conf
    echo "net.ipv4.conf.all.send_redirects=0" >> /etc/sysctl.conf
fi
sysctl -p


#/etc/hosts

hostsFileCleanup

echo "#strongswan mark" >> $hostsFile 
printf "$hosts\n" >> $hostsFile
echo "#strongswan mark" >> $hostsFile 
