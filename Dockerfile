FROM experimentalplatform/ubuntu:latest

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y wpasupplicant hostapd hostap-utils iptables iw iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.0.0/dumb-init_1.0.0_amd64 && \
    chmod +x /usr/local/bin/dumb-init

COPY platform-hostapd /platform-hostapd

CMD ["dumb-init", "/platform-hostapd", "--hostapd-binary", "/usr/sbin/hostapd", "--skvs-dir", "/etc/protonet", "--config-file", "/etc/hostapd/hostapd.conf"]
