FROM rust:1.67-buster

WORKDIR /vmod_reqwest
ARG VMOD_REQWEST_VERSION=0.0.8
ARG RELEASE_URL=https://github.com/gquintard/vmod_reqwest.git

RUN curl -s https://packagecloud.io/install/repositories/varnishcache/varnish72/script.deb.sh | bash && apt-get update && apt-get install -y varnish-dev clang libssl-dev git

RUN git clone https://github.com/gquintard/vmod_reqwest.git && \
	cd vmod_reqwest && \
    git checkout 6d7d53a && \
	cargo build --release

FROM varnish:7.2.1
USER root
RUN set -e; \
    apt-get update; \
    apt-get -y install $VMOD_DEPS /pkgs/*.deb autoconf-archive git libpcre2-dev libedit-dev libcurl4-openssl-dev libssl-dev; \
    git clone https://github.com/varnishcache/varnish-cache.git /tmp/varnish-cache; \
    cd /tmp/varnish-cache; \
    git checkout $(varnishd -V 2>&1 | grep -o '[0-9a-f]\{40\}*'); \
    ./autogen.sh; \
    ./configure; \
    make -j 16; \
    export VARNISHSRC=/tmp/varnish-cache; \
    export V=1; \
    find -name VSC_main.h; \
    sed -i '/VERBOSE=1 check/d' /usr/local/bin/install-vmod; \
    install-vmod https://code.uplex.de/uplex-varnish/libvdp-pesi/-/archive/7.2/libvdp-pesi-7.2.tar.gz; \
    install-vmod https://github.com/varnish/varnish-modules/releases/download/0.20.0/varnish-modules-0.20.0.tar.gz; \
#    install-vmod https://github.com/varnish/libvmod-curl/archive/refs/tags/libvmod-curl-1.0.4.tar.gz; \
    apt-get -y purge --auto-remove $VMOD_DEPS varnish-dev libpcre2-dev libedit-dev; \
    rm -rf /var/lib/apt/lists/* /tmp/varnish-cache
RUN apt-get update && apt-get install -y procps vim curl

COPY --from=0 /vmod_reqwest/vmod_reqwest/target/release/libvmod_reqwest.so /usr/lib/varnish/vmods/
COPY custom-entrypoint /usr/local/bin/

RUN cd /opt && \
    curl -OL https://github.com/jonnenauha/prometheus_varnish_exporter/releases/download/1.6.1/prometheus_varnish_exporter-1.6.1.linux-amd64.tar.gz && \
    tar -xf prometheus_varnish_exporter-1.6.1.linux-amd64.tar.gz

RUN mkdir -p /logs/app && touch /logs/app/app.log && mkdir /data

RUN cat /usr/local/bin/custom-entrypoint > /usr/local/bin/docker-varnish-entrypoint
RUN chmod +x /usr/local/bin/docker-varnish-entrypoint

# Downloading Varnish Source Code
RUN rm -rf /etc/varnish/* && git clone http://gitlabweb.infoedge.com/aadarsh.verma/varnish-setup.git /etc/varnish;

ENTRYPOINT ["/usr/local/bin/docker-varnish-entrypoint"]
