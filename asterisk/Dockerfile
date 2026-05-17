# Dockerfile.asterisk — Asterisk 18.18.1 + ViciDial Patches + ConfBridge
# Mehrstufiger Build: compile → runtime
FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV ASTERISK_VERSION=18.18.1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc g++ make patch wget curl tar \
    libreadline-dev libxml2-dev libsqlite3-dev libuuid1 uuid-dev \
    libcurl4-openssl-dev libgd-dev libssl-dev libnewt-dev \
    libspeex-dev libspeexdsp-dev libedit-dev libsrtp2-dev \
    libjansson-dev libopus-dev libvorbis-dev libogg-dev \
    liblua5.2-dev libxslt1-dev libavcodec-dev unixodbc-dev \
    ca-certificates pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/asterisk

# Stock Asterisk source
RUN wget -q https://downloads.asterisk.org/pub/telephony/asterisk/old-releases/asterisk-${ASTERISK_VERSION}.tar.gz \
    && tar -xzf asterisk-${ASTERISK_VERSION}.tar.gz \
    && rm asterisk-${ASTERISK_VERSION}.tar.gz

WORKDIR /usr/src/asterisk/asterisk-${ASTERISK_VERSION}

# ViciDial-Patches laden
RUN wget -q http://download.vicidial.com/asterisk-patches/Asterisk-18/amd_stats-18.patch \
    && wget -q http://download.vicidial.com/asterisk-patches/Asterisk-18/iax_peer_status-18.patch \
    && wget -q http://download.vicidial.com/asterisk-patches/Asterisk-18/sip_peer_status-18.patch \
    && wget -q http://download.vicidial.com/asterisk-patches/Asterisk-18/timeout_reset_dial_app-18.patch \
    && wget -q http://download.vicidial.com/asterisk-patches/Asterisk-18/timeout_reset_dial_core-18.patch

# Patches anwenden
RUN patch -p0 < amd_stats-18.patch apps/app_amd.c \
    && patch -p0 < iax_peer_status-18.patch channels/chan_iax2.c \
    && patch -p0 < sip_peer_status-18.patch channels/chan_sip.c \
    && patch -p0 < timeout_reset_dial_app-18.patch apps/app_dial.c \
    && patch -p0 < timeout_reset_dial_core-18.patch main/dial.c

# enter.h / leave.h aus ViciDial
WORKDIR /usr/src/asterisk/asterisk-${ASTERISK_VERSION}/apps
RUN wget -q http://download.vicidial.com/asterisk-patches/Asterisk-18/enter.h \
    && wget -q http://download.vicidial.com/asterisk-patches/Asterisk-18/leave.h \
    && mv -f enter.h.1 enter.h 2>/dev/null; mv -f leave.h.1 leave.h 2>/dev/null; true

WORKDIR /usr/src/asterisk/asterisk-${ASTERISK_VERSION}

# Configure & Compile
RUN : ${JOBS:=$(( $(nproc) + $(nproc) / 2 ))} \
    && ./configure --libdir=/usr/lib/x86_64-linux-gnu \
        --with-gsm=internal \
        --enable-opus \
        --enable-srtp \
        --with-ssl \
        --enable-asteriskssl \
        --with-pjproject-bundled \
        --with-jansson-bundled \
    && make menuselect/menuselect menuselect-tree menuselect.makeopts \
    && menuselect/menuselect --enable app_meetme menuselect.makeopts \
    && menuselect/menuselect --enable res_http_websocket menuselect.makeopts \
    && menuselect/menuselect --enable res_srtp menuselect.makeopts \
    && make -j ${JOBS} all \
    && make install DESTDIR=/install \
    && make samples DESTDIR=/install \
    && make basic-pbx DESTDIR=/install || true

# ── Runtime Image ──────────────────────────────────────────
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libreadline8 libxml2 libsqlite3-0 libuuid1 libcurl4 libgd3 \
    libssl3 libspeex1 libspeexdsp1 libedit2 libsrtp2-1 libjansson4 \
    libopus0 libvorbis0a libogg0 liblua5.2-0 libxslt1.1 unixodbc \
    sox lame procps net-tools iputils-ping tcpdump sngrep \
    perl libdbi-perl libdbd-mysql-perl \
    && rm -rf /var/lib/apt/lists/*

# Asterisk libs brauchen ldconfig
RUN mkdir -p /usr/lib/x86_64-linux-gnu/asterisk/modules \
    && echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/asterisk.conf \
    && ldconfig

COPY --from=builder /install/usr /usr
COPY --from=builder /install/etc /etc
COPY --from=builder /install/var/lib /var/lib
COPY --from=builder /install/var/log /var/log
COPY --from=builder /install/var/spool /var/spool

# Module: chan_sip explizit laden (nicht noload)
RUN sed -i 's|noload = chan_sip.so|;noload = chan_sip.so|g' /etc/asterisk/modules.conf 2>/dev/null || true

# Keine Hardware-Timing-Module — ConfBridge nutzt timerfd
RUN cat >> /etc/asterisk/modules.conf <<'EOF'
noload => res_timing_dahdi.so
noload => chan_dahdi.so
noload => codec_dahdi.so
EOF

# Ordnerstruktur
RUN mkdir -p /var/lib/asterisk/sounds /var/lib/asterisk/moh \
    /var/spool/asterisk/monitor /var/spool/asterisk/monitorDONE/MP3 \
    /var/log/asterisk /var/run/asterisk \
    && useradd -r -d /var/lib/asterisk asterisk 2>/dev/null || true \
    && chown -R asterisk:asterisk /var/lib/asterisk /var/spool/asterisk /var/log/asterisk /var/run/asterisk /etc/asterisk

# ── ConfBridge Konfiguration ──────────────────────────────
COPY confbridge-vicidial.conf /etc/asterisk/
RUN echo '#include confbridge-vicidial.conf' >> /etc/asterisk/confbridge.conf

# Extensions für ConfBridge
COPY extensions-vicidial.conf /etc/asterisk/
RUN echo '#include extensions-vicidial.conf' >> /etc/asterisk/extensions.conf

# Manager-Konfiguration für ViciDial
RUN cat >> /etc/asterisk/manager.conf <<'EOF'
[general]
displayconnects = yes

[cron]
secret = 1234
read = command,reporting
write = command,reporting
eventfilter=Event: Meetme
eventfilter=Event: Confbridge

[confcron]
secret = 1234
read = command,reporting
write = command,reporting
eventfilter=Event: Meetme
eventfilter=Event: Confbridge
EOF

EXPOSE 5060/udp 5060/tcp 10000-20000/udp 5038/tcp

ENTRYPOINT ["asterisk", "-fn"]
