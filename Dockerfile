FROM ruby:2.3.0

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y wpasupplicant hostapd hostap-utils iw iproute2 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY src /src
RUN cd /src && bundle
RUN cd /src && rake test
RUN cd /src rake build && rake install && chmod 0755 /src/exe/wifi


ENTRYPOINT ["/src/bin/wifi"]

CMD ["/usr/sbin/hostapd", "/etc/hostapd/hostapd.conf"]




