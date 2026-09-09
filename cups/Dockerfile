FROM ghcr.io/home-assistant/base:latest

# Add env
ENV LANG=C.UTF-8
# Set CUPS environment variables for data persistence (HA shared directory)
ENV CUPS_DATADIR=/share/cups
ENV CUPS_CACHEDIR=/share/cups/cache
ENV CUPS_LOGDIR=/share/cups/logs
ENV CUPS_STATEDIR=/share/cups/state
ENV CUPS_SERVERROOT=/share/cups/config

# Setup base
# Note: hplip, foomatic-db, and foomatic-db-ppds were removed from Alpine 3.23
# and are no longer available in stable repositories.
# Gutenprint covers most printer models as a replacement.
RUN \
    echo "http://dl-cdn.alpinelinux.org/alpine/v$(cat /etc/alpine-release | cut -d'.' -f1,2)/main" > /etc/apk/repositories && \
    echo "http://dl-cdn.alpinelinux.org/alpine/v$(cat /etc/alpine-release | cut -d'.' -f1,2)/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache \
        cups \
        cups-filters \
        ghostscript \
        libjpeg-turbo \
        net-snmp \
        epson-inkjet-printer-escpr \
        gutenprint \
        gcompat \
        libstdc++ \
        dpkg \
        jq

# Build the open-source rastertokpsl filter for Kyocera GDI (KPSL) printers
# (FS-1040/1041, FS-1060DN/1061DN, FS-1020/1025/1120/1125MFP). Their PPDs
# reference /usr/lib/cups/filter/rastertokpsl; the official filter is
# proprietary and not available in the Alpine repositories, so compile the
# vendored Apache-2.0 re-implementation (sv99/rastertokpsl-re).
COPY rastertokpsl /tmp/rastertokpsl
RUN \
    apk add --no-cache --virtual .rastertokpsl-build \
        gcc \
        musl-dev \
        cups-dev && \
    gcc -O2 -o /usr/lib/cups/filter/rastertokpsl \
        /tmp/rastertokpsl/main.c \
        /tmp/rastertokpsl/rastertokpsl.c \
        /tmp/rastertokpsl/halfton.c \
        /tmp/rastertokpsl/libjbig/jbig.c \
        /tmp/rastertokpsl/libjbig/jbig_ar.c \
        /tmp/rastertokpsl/unicode/ConvertUTF.c \
        -I/tmp/rastertokpsl \
        -lcups -lm && \
    rm -rf /tmp/rastertokpsl && \
    apk del .rastertokpsl-build

# Build and install the Dymo CUPS drivers (LabelWriter/LabelManager). The
# Dymo PPDs (e.g. lw4xl.ppd for the LabelWriter 4XL) reference
# /usr/lib/cups/filter/raster2dymolw; the filter is proprietary and not
# available in the Alpine repositories, so compile the vendored GPLv2
# dymo-cups-drivers source and install it (filters raster2dymolw and
# raster2dymolm plus the official Dymo PPDs).
COPY dymo-cups-drivers /tmp/dymo-cups-drivers
RUN \
    apk add --no-cache --virtual .dymo-build \
        g++ \
        make \
        cups-dev && \
    cd /tmp/dymo-cups-drivers && \
    find . -exec touch -t 202001010000 {} + && \
    ./configure && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/dymo-cups-drivers && \
    apk del .dymo-build

# Copy data
COPY rootfs /

# Expose CUPS web interface port
EXPOSE 631

HEALTHCHECK \
    CMD lpstat -r || exit 1
