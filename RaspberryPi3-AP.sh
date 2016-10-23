#!/bin/bash
# ==========================================================================
if [ "$EUID" -ne 0 ]
    then [ "$LC_TIME" = "zh_TW.UTF-8" ]&& echo "必須是 root, 會自動使用sudo"||echo "Must be root, so use sudo automatically."
fi
# ==========================================================================
if [[ $# -lt 2 ]]; then 
    if [ "$LC_TIME" = "zh_TW.UTF-8" ]; then 
        echo "請您設定WiFi名稱及密碼（至少8碼）作為參數"
        echo "格式如下:"
        echo "sudo  $0   WiFi名稱   密碼"
        echo "sudo  $0   R-Pi3   raspberry"
        echo "sudo  $0   WiFi名稱   密碼  區域IP前3碼  區域IP最後一碼開頭  區域IP最後一碼結尾"
        echo "sudo  $0   R-Pi3   raspberry  172.18.1  100  160"
    else
        echo "Please use WiFiName and password（minimum: 8 characters）"
        echo "Usage:"
        echo "sudo  $0   WiFiName   password"
        echo "sudo  $0   R-Pi3   raspberry"
        echo "sudo  $0   WiFiName   password  localIP  from  to"
        echo "sudo  $0   R-Pi3   raspberry  172.18.1  100  160"
    fi
    exit
fi
# ==========================================================================
wifi_ID="$1"
wifiPassword="$2"
LocalIP=${3:-'172.18.1'}
LocalIPfrom=${4:-100}
LocalIPto=${5:-160}
# ==========================================================================
sudo apt-get install dnsmasq hostapd
# ==========================================================================
grep 'denyinterfaces wlan0' /etc/dhcpcd.conf  &> /dev/null
(($?==0))  || echo 'denyinterfaces wlan0' >> /etc/dhcpcd.conf
# ==========================================================================
grep 'allow-hotplug wlan0' /etc/network/interfaces &> /dev/null
if [[ $? -eq 0 ]]; then
   nn=$(grep -n 'iface wlan0 inet static' /etc/network/interfaces|cut -d : -f 1)
   if ((nn>0)); then 
        mm=$((nn+4))
        while (( mm>nn ))
        do 
            sed -n "${mm}p" /etc/network/interfaces| egrep "^[[:space:]]*(address|netmask|network|broadcast)"  > /dev/null
            (($?==0))  && sudo sed -i "${mm}d" /etc/network/interfaces
            ((--mm))
        done
        sudo sed -i "${nn}aaddress ${LocalIP}.1\nnetmask 255.255.255.0\nnetwork ${LocalIP}.0\nbroadcast ${LocalIP}.255" /etc/network/interfaces
   else
        sudo sed -i "s/iface wlan0 inet manual/iface wlan0 inet static\naddress ${LocalIP}.1\nnetmask 255.255.255.0\nnetwork ${LocalIP}.0\nbroadcast ${LocalIP}.255/" /etc/network/interfaces
   fi
   egrep "^[[:space:]]*wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf" /etc/network/interfaces > /dev/null && \
        sudo sed -i 's/^[[:space:]]*wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf/# wpa-conf \/etc\/wpa_supplicant\/wpa_supplicant.conf/' /etc/network/interfaces
fi
# ==========================================================================
sudo service dhcpcd restart
sudo ifdown wlan0; sudo ifup wlan0
# ==========================================================================
sudo sed -i 's/#DAEMON_CONF=""/DAEMON_CONF="\/etc\/hostapd\/hostapd.conf"/'  /etc/default/hostapd
# ==========================================================================
sudo bash -c "cat > /etc/hostapd/hostapd.conf" <<EOF
interface=wlan0
driver=nl80211
hw_mode=g
channel=6
ieee80211n=1
wmm_enabled=1
ht_capab=[HT40][SHORT-GI-20][DSSS_CCK-40]
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
ssid=$wifi_ID
wpa_passphrase=$wifiPassword
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
# ==========================================================================
sudo bash -c "cat > /etc/dnsmasq.conf" <<EOF
interface=wlan0
listen-address=${LocalIP}.1
bind-interfaces
server=8.8.8.8
domain-needed
bogus-priv
dhcp-range=${LocalIP}.${LocalIPfrom},${LocalIP}.${LocalIPto},12h
EOF
# ==========================================================================
sudo sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo bash -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
# ==========================================================================
function findAndDelLineAll { 
    while ((1)) 
    do
        nn=$(egrep -n -m1 "${2}"  "${1}"|cut -d : -f 1)
        ((nn>0))  &&   sudo sed -i "${nn}d" "${1}" || return 0
    done
 }
# ==========================================================================
function onlyOneAddBefore { 
    findAndDelLineAll  "${1}"  "^[[:space:]]*${2}[[:space:]]*$"
    sudo sed -i "s/^[[:space:]]*${3}[[:space:]]*$/${2}\n${3}/g"  "${1}"
 }
# ==========================================================================
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE  
sudo iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT  
sudo iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT  
sudo bash -c "iptables-save > /etc/iptables.ipv4.nat"
onlyOneAddBefore  /etc/rc.local  "iptables-restore < \/etc\/iptables.ipv4.nat"  "exit 0"
# ==========================================================================
rpi3Url="myrpi3 pi.rpi3.my"
rpi3shFile="/home/pi/rpi3.sh"
rpi3shFileEsc="\/home\/pi\/rpi3.sh"
pySvrStr="python -m SimpleHTTPServer 4567"
myip=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
# ==================================
sudo bash -c "cat > $rpi3shFile" <<EOF
rpi3Url="$rpi3Url"
pySvrStr="$pySvrStr"
EOF
# ==============
sudo bash -c "cat >> $rpi3shFile" <<"EOF"
myip=$(ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}')
nn=$(egrep -n -m1 "$rpi3Url"  "/etc/hosts"|cut -d : -f 1)
((nn>0))  &&   sudo sed -i "${nn}d" "/etc/hosts" 
bash -c "echo  $myip $rpi3Url >> /etc/hosts"
service dnsmasq restart
cd /home/pi
[[ -d rPi3IP ]] || mkdir rPi3IP
cd rPi3IP
echo "<h1> rPi3 IP  :  $myip </h1>" > index.html
$pySvrStr &>/dev/null &
EOF
# ==================================
onlyOneAddBefore  /etc/rc.local  "bash $rpi3shFileEsc"  "exit 0"
# ==========================================================================
sudo service dnsmasq restart  
sudo service hostapd restart 
[ "$LC_TIME" = "zh_TW.UTF-8" ]&& echo "等待 20 秒..."||echo "Waiting 20 seconds..."
sleep 11
ps aux | grep hostapd | grep -v grep || sudo service hostapd restart
# ==========================================================================
ps aux | grep hostapd | grep -v grep | grep hostapd
ps aux | grep dnsmasq | grep -v grep | grep dnsmasq
# ==========================================================================
sudo bash $rpi3shFile
# ==========================================================================
