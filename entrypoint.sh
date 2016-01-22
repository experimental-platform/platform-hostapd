#!/usr/bin/env bash
set -e

BASEDIR=${BASEDIR:="/wifi"}

INTERFACE=${INTERFACE:="wlan0"}
DRIVER=${DRIVER:="nl80211"}
SSID=${SSID:=$HOSTNAME}

if [[ ! -f "${BASEDIR}/enabled" ]]; then
    echo "Wifi disabled."
    exit 0
fi
echo "Configuring WIFI."
CHANNEL=$([[ -f "${BASEDIR}/channel" ]] && cat "${BASEDIR}/channel")
WPA_PSK=$([[ -f "${BASEDIR}/password" ]] && /usr/bin/wpa_passphrase "${SSID}" "$(cat ${BASEDIR}/password)" | awk -F "=" '/[ \t]+psk=/ { print $2 }')


if [[ ! -f "${BASEDIR}/guest/enabled" ]]; then
    echo "Guest WIFI disabled."
    cat << EOC > "/etc/hostapd/hostapd.conf"
ctrl_interface=/var/run/hostapd
driver=${DRIVER}
hw_mode=g
ieee80211n=1
ieee80211d=1
country_code=US
wme_enabled=1
wmm_enabled=1
channel=${CHANNEL}
ht_capab=[HT20][HT40-][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40][TX-STBC][RX-STBC1]
interface=${INTERFACE}

ssid=${SSID}
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk=${WPA_PSK}


EOC
else
    # TODO: Add guest wifi section to config file
    # TODO: Add password and SSID name to guest wifi config
    #       echo /wifi/guest/{password} > "/etc/hostapd/hostapd.conf"
    echo "Configuring guest wifi"
    WPA_PSK_GUEST=$([[ -f "${BASEDIR}/guest/password" ]] && /usr/bin/wpa_passphrase "${SSID}" "$(cat ${BASEDIR}/guest/password)" | awk -F "=" '/[ \t]+psk=/ { print $2 }')
    cat << EOC > "/etc/hostapd/hostapd.conf"
ctrl_interface=/var/run/hostapd
driver=${DRIVER}
hw_mode=g
ieee80211n=1
ieee80211d=1
country_code=US
wme_enabled=1
wmm_enabled=1
channel=${CHANNEL}
ht_capab=[HT20][HT40-][SHORT-GI-20][SHORT-GI-40][DSSS_CCK-40][TX-STBC][RX-STBC1]
interface=${INTERFACE}

ssid=${SSID} (public)
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk=${WPA_PSK_GUEST}

bss=wlan1
bssid=02:0e:8e:52:8c:01
ssid=${SSID}
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_psk=${WPA_PSK}

EOC
fi


chmod 0644 "/etc/hostapd/hostapd.conf"

exec "$@"