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
# Alpine splits this: `gutenprint` is libraries/tools only; `gutenprint-cups`
# ships rastertogutenprint and the CUPS PPDs (Canon, HP, Brother, etc.).
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
        gutenprint-cups \
        avahi \
        dbus \
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

# Canon BJNP network backend (port 8611): build from Debian's published
# cups-bjnp 2.0.3 source. The checksum protects against unexpected changes.
RUN \
    apk add --no-cache --virtual .bjnp-build \
        build-base \
        cups-dev \
        curl \
        ca-certificates && \
    mkdir -p /tmp/cups-bjnp && \
    curl --fail --location --retry 3 \
      -o /tmp/cups-bjnp.tar.gz \
      https://deb.debian.org/debian/pool/main/c/cups-bjnp/cups-bjnp_2.0.3.orig.tar.gz && \
    echo "c914b2fd9d8e26ce22f2df6244d9defeec31ee9a5360f723eecb3b00f2168500  /tmp/cups-bjnp.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/cups-bjnp.tar.gz -C /tmp/cups-bjnp --strip-components=1 && \
    cd /tmp/cups-bjnp && \
    ./configure --prefix=/usr \
      --with-cupsbackenddir=/usr/lib/cups/backend \
      --disable-Werror && \
    make && \
    install -m 755 bjnp /usr/lib/cups/backend/bjnp && \
    test -x /usr/lib/cups/backend/bjnp && \
    cd / && \
    rm -rf /tmp/cups-bjnp /tmp/cups-bjnp.tar.gz && \
    apk del .bjnp-build

# Copy data
COPY rootfs /

# Expose CUPS web interface port
EXPOSE 631

HEALTHCHECK \
    CMD lpstat -r || exit 1
