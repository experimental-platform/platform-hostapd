#!/usr/bin/env bash
set -e

function get_channel() {
    if [[ -f "${BASEDIR}/channel" ]]; then
        echo $(cat "${BASEDIR}/channel")
    else
        echo 11
    fi
}

function calculate_psk() {
    local PASSWORD_FILE=$1
    if [[ -f "${PASSWORD_FILE}" ]]; then
        echo $(wpa_passphrase "${SSID}" "$(cat ${PASSWORD_FILE})" | awk -F "=" '/[ \t]+psk=/ { print $2 }')
        return 0
    fi
    return 23
}

function configure_wifi() {
    echo "Configuring WIFI."
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
    chmod 0644 "/etc/hostapd/hostapd.conf"
}

function configure_guest_wifi() {
    echo "Configuring guest WIFI."
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
    chmod 0644 "/etc/hostapd/hostapd.conf"
}



BASEDIR=${BASEDIR:="/wifi"}
INTERFACE=${INTERFACE:="wlan0"}
DRIVER=${DRIVER:="nl80211"}
SSID=${SSID:=$HOSTNAME}

echo $(ls -l ${BASEDIR}/*)

if [[ -f "${BASEDIR}/enabled" ]] && [[ -f "${BASEDIR}/password" ]]; then
    CHANNEL=$(get_channel)
    WPA_PSK=$(calculate_psk "${BASEDIR}/password")
    if [[ -f "${BASEDIR}/guest/enabled" ]] && [[ -f "${BASEDIR}/guest/password" ]]; then
        WPA_PSK_GUEST=$(calculate_psk "${BASEDIR}/guest/password")
        configure_guest_wifi
    else
        configure_wifi
    fi
    exec "$@"
    exit 0
fi
echo "Wifi disabled."
exit 0
