FROM ruby:2.3.0

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y wpasupplicant hostapd hostap-utils iptables iw iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN wget -O /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v1.0.0/dumb-init_1.0.0_amd64 && \
    chmod +x /usr/local/bin/dumb-init

COPY src /src
RUN cd /src && bundle
RUN cd /src && rake test
RUN cd /src rake build && rake install && chmod 0755 /src/exe/wifi


CMD ["dumb-init", "/src/exe/wifi", "/usr/sbin/hostapd", "/etc/hostapd/hostapd.conf"]
