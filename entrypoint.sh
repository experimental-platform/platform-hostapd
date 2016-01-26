#!/usr/bin/env bash
set -e

function cleanup_statusfiles() {
    rm -f "${BASEDIR}/success" \
          "${BASEDIR}/error" \
          "${BASEDIR}/guest/success" \
          "${BASEDIR}/guest/error"
}

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

function find_wireless_interface() {
    # find, parse and extract the first interface name beginning with "wl". Example input:
    # "2: wlp2s0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc mq state DOWN mode DEFAULT group default qlen 1000"
    echo $(ip link show | awk '/^[0-9: \t]+wl[0-9a-z]+:/ {gsub(":", "", $2); print $2}' | head -1)
}

function configure_wifi() {
    echo "Configuring WIFI."
    cleanup_statusfiles
    for variable in DRIVER CHANNEL INTERFACE SSID WPA_PSK; do
        if [[ -z "${!variable}" ]]; then
            echo "Variable '${variable}' unknown, exiting now." | tee "${BASEDIR}/error"
            return 404
        fi
    done
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
    echo "Successfully configured SYSTEM WIFI at $(date +%Y-%m-%dT%H:%M:%S%:z)" | tee "${BASEDIR}/success"
}

function configure_guest_wifi() {
    echo "Configuring SYSTEM and GUEST WIFI."
    cleanup_statusfiles
    for variable in DRIVER CHANNEL INTERFACE SSID WPA_PSK WPA_PSK_GUEST; do
        if [[ -z "${!variable}" ]]; then
            echo "Variable '${variable}' unknown, exiting now." | tee "${BASEDIR}/error" "${BASEDIR}/guest/error"
            return 404
        fi
    done
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
    echo "Successfully configured SYSTEM WIFI at $(date +%Y-%m-%dT%H:%M:%S%:z)" | tee "${BASEDIR}/success" "${BASEDIR}/guest/success"
}



BASEDIR=${BASEDIR:="/wifi"}
INTERFACE=${INTERFACE:=$(find_wireless_interface)}
DRIVER=${DRIVER:="nl80211"}
SSID=${SSID:=$HOSTNAME}

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
exit 1
