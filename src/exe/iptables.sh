#!/usr/bin/env bash

set -e


function start() {
    local DEVICE=$1
    echo -n "Enabling hostapd ip filter for ${DEVICE}..."
    /sbin/iptables -A FORWARD -i wl_private -o ${DEVICE} -m state --state ESTABLISHED,RELATED -j ACCEPT
    /sbin/iptables -A FORWARD -i ${DEVICE} -o wl_private -j ACCEPT
    /sbin/iptables -A FORWARD -i wl_public -o ${DEVICE} -m state --state ESTABLISHED,RELATED -j ACCEPT
    /sbin/iptables -A FORWARD -i ${DEVICE} -o wl_public -j ACCEPT
    /sbin/iptables -t nat -A POSTROUTING -o ${DEVICE} -s 10.42.0.0/16 -j MASQUERADE
    /sbin/iptables -t nat -A POSTROUTING -o ${DEVICE} -s 10.43.0.0/16 -j MASQUERADE
    echo "DONE."
}


function stop() {
    local DEVICE=$1
    echo -n "Disabling hostapd ip filter for ${DEVICE}... "
    /sbin/iptables -D FORWARD -i wl_private -o ${DEVICE} -m state --state ESTABLISHED,RELATED -j ACCEPT
    /sbin/iptables -D FORWARD -i ${DEVICE} -o wl_private -j ACCEPT
    /sbin/iptables -D FORWARD -i wl_public -o ${DEVICE} -m state --state ESTABLISHED,RELATED -j ACCEPT
    /sbin/iptables -D FORWARD -i ${DEVICE} -o wl_public -j ACCEPT
    /sbin/iptables -t nat -D POSTROUTING -o ${DEVICE} -s 10.42.0.0/16 -j MASQUERADE
    /sbin/iptables -t nat -D POSTROUTING -o ${DEVICE} -s 10.43.0.0/16 -j MASQUERADE
    echo "DONE."
}


function run() {
    local DEVICE arg
    arg=$1
    DEVICE=$(ip route get 8.8.8.8 | grep -Po "(?<=dev )en[0-9a-z_]+")

    if [[ -z "${DEVICE}" ]]; then
        echo "Device not found. Can you help me find it?"
        echo $(ip route get 8.8.8.8)
        exit 23
    fi

    case ${arg} in
        start)
            start ${DEVICE}
        ;;
        stop)
            stop ${DEVICE}
        ;;
        *)
            echo "$0 start|stop"
        ;;
    esac
}


run $@



