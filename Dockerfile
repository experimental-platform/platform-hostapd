FROM experimentalplatform/ubuntu:latest

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y wpasupplicant hostapd hostap-utils iw iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ADD lib/wifi.rb /lib/wifi.rb
ADD bin/wifi /bin/wifi
RUN chmod 0755 /bin/wifi
ENTRYPOINT ["/bin/wifi"]

CMD ["/usr/sbin/hostapd", "/etc/hostapd/hostapd.conf"]
