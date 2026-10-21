#!/usr/bin/with-contenv bash

# ─────────────────────────────────────────────────────────────
# Create CUPS data directories in the persistent HA share
# ─────────────────────────────────────────────────────────────
mkdir -p /share/cups/cache
mkdir -p /share/cups/logs
mkdir -p /share/cups/state
mkdir -p /share/cups/config
mkdir -p /share/cups/config/ppd
mkdir -p /share/cups/config/ssl

# Set proper permissions
chown -R root:lp /share/cups
chmod -R 775 /share/cups

# ─────────────────────────────────────────────────────────────
# Configure CUPS admin authentication from the app options
# ─────────────────────────────────────────────────────────────
ADMIN_USER=$(jq -r '.admin_username // empty' /data/options.json 2>/dev/null || true)
ADMIN_PASSWORD=$(jq -r '.admin_password // empty' /data/options.json 2>/dev/null || true)

AUTH_LOCATION=""
AUTH_POLICY="AuthType None"

if [ -n "$ADMIN_USER" ] && [ -n "$ADMIN_PASSWORD" ]; then
    case "$ADMIN_USER" in
        *:*|*[[:space:]]*|*/*)
            echo "Warning: invalid admin_username '${ADMIN_USER}'; admin authentication disabled."
            ;;
        *)
            AUTH_READY=1
            if ! id "$ADMIN_USER" >/dev/null 2>&1; then
                if ! adduser -D -H -s /sbin/nologin -G lpadmin "$ADMIN_USER"; then
                    echo "Warning: could not create admin user '${ADMIN_USER}'; admin authentication disabled."
                    AUTH_READY=0
                fi
            else
                # Existing users must still be members of CUPS' admin group.
                addgroup "$ADMIN_USER" lpadmin >/dev/null 2>&1 || true
            fi

            admin_groups=$(id -nG "$ADMIN_USER" 2>/dev/null || true)
            case " ${admin_groups} " in
                *" lpadmin "*) ;;
                *)
                    if [ "$AUTH_READY" -eq 1 ]; then
                        echo "Warning: '${ADMIN_USER}' is not in the lpadmin group; admin authentication disabled."
                    fi
                    AUTH_READY=0
                    ;;
            esac

            if [ "$AUTH_READY" -eq 1 ]; then
                if printf '%s:%s\n' "$ADMIN_USER" "$ADMIN_PASSWORD" | chpasswd; then
                    AUTH_LOCATION=$'  AuthType Basic\n  Require user @SYSTEM'
                    AUTH_POLICY=$'    AuthType Basic\n    Require user @SYSTEM'
                    echo "Admin authentication enabled for user '${ADMIN_USER}'."
                else
                    echo "Warning: could not set the password for '${ADMIN_USER}'; admin authentication disabled."
                fi
            fi
            ;;
    esac
else
    echo "Admin authentication disabled (admin_username/admin_password empty)."
fi

# Migrate legacy data from /data/cups to /share/cups if present
if [ -d /data/cups/config ] && [ ! -f /share/cups/config/.migrated ]; then
    echo "Migrating CUPS data from /data/cups to /share/cups..."
    cp -r /data/cups/config/printers.conf /share/cups/config/ 2>/dev/null || true
    cp -r /data/cups/config/ppd/* /share/cups/config/ppd/ 2>/dev/null || true
    cp -r /data/cups/config/ssl/* /share/cups/config/ssl/ 2>/dev/null || true
    cp -r /data/cups/config/cupsd.conf /share/cups/config/ 2>/dev/null || true
    cp -r /data/cups/cache/* /share/cups/cache/ 2>/dev/null || true
    cp -r /data/cups/logs/* /share/cups/logs/ 2>/dev/null || true
    cp -r /data/cups/state/* /share/cups/state/ 2>/dev/null || true
    touch /share/cups/config/.migrated
    echo "Migration complete."
fi

# ─────────────────────────────────────────────────────────────
# Install cupsd.conf, preserving user customisations
#
# Only the block between the managed markers is owned by the
# add-on. It is regenerated on every start so changes to the
# app options (for example the admin credentials) take effect.
# Directives added outside the markers (for example
# "ServerAlias *" from the CUPS web UI) are kept as-is.
# ─────────────────────────────────────────────────────────────
CUPSD_CONF="/share/cups/config/cupsd.conf"
MANAGED_BEGIN="# >>> CUPS ADD-ON MANAGED CONFIG (regenerated on start; add custom settings outside) >>>"
MANAGED_END="# <<< CUPS ADD-ON MANAGED CONFIG <<<"

render_managed_config() {
    printf '%s\n' "$MANAGED_BEGIN"
    cat << EOL
# Listen on all interfaces (Port covers TCP+UDP for IPP/AirPrint)
Port 631
Listen /run/cups/cups.sock

WebInterface Yes
DefaultAuthType None
DefaultEncryption Never
SystemGroup lpadmin
Browsing Yes
BrowseLocalProtocols dnssd
DefaultShared Yes
JobSheets none,none
PreserveJobHistory No

# @LOCAL plus explicit v6 prefixes: Port 631 listens on IPv6 and Apple
# clients resolve *.local to AAAA first.
<Location />
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
  Allow fe80::/10
  Allow fd00::/8
</Location>

<Location /admin>
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
  Allow fe80::/10
  Allow fd00::/8
${AUTH_LOCATION}
</Location>

<Location /admin/conf>
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
  Allow fe80::/10
  Allow fd00::/8
${AUTH_LOCATION}
</Location>

<Location /jobs>
  Order allow,deny
  Allow localhost
  Allow @LOCAL
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
  Allow fe80::/10
  Allow fd00::/8
</Location>

# Top-level <Limit> is ignored by cupsd; job ops must live in a Policy.
# Cancel-Job (the web UI "Cancel Job" button) is not Cancel-My-Jobs.
# The baked-in default policy requires @OWNER/@SYSTEM, so job cancels are
# explicitly kept anonymous while printer administration uses the configured
# admin account (when one is set).
<Policy default>
  JobPrivateAccess all
  JobPrivateValues none
  SubscriptionPrivateAccess all
  SubscriptionPrivateValues none

  <Limit Create-Job Print-Job Print-URI Validate-Job>
    Order allow,deny
    Allow localhost
    Allow @LOCAL
    Allow 10.0.0.0/8
    Allow 172.16.0.0/12
    Allow 192.168.0.0/16
    Allow fe80::/10
    Allow fd00::/8
  </Limit>

  <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Job Cancel-Jobs Cancel-Current-Job Cancel-My-Jobs Suspend-Current-Job Resume-Job Close-Job CUPS-Move-Job CUPS-Get-Document>
    AuthType None
    Order allow,deny
    Allow localhost
    Allow @LOCAL
    Allow 10.0.0.0/8
    Allow 172.16.0.0/12
    Allow 192.168.0.0/16
    Allow fe80::/10
    Allow fd00::/8
  </Limit>

  # Printer/class administration requires the configured admin account when
  # one is set; the job operations above stay available anonymously.
  <Limit Pause-Printer Resume-Printer Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs CUPS-Accept-Jobs CUPS-Reject-Jobs Promote-Job CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Get-Devices>
${AUTH_POLICY}
    Order allow,deny
    Allow localhost
    Allow @LOCAL
    Allow 10.0.0.0/8
    Allow 172.16.0.0/12
    Allow 192.168.0.0/16
    Allow fe80::/10
    Allow fd00::/8
  </Limit>

  <Limit All>
    AuthType None
    Order allow,deny
    Allow localhost
    Allow @LOCAL
    Allow 10.0.0.0/8
    Allow 172.16.0.0/12
    Allow 192.168.0.0/16
    Allow fe80::/10
    Allow fd00::/8
  </Limit>
</Policy>
EOL
    printf '%s\n' "$MANAGED_END"
}

update_managed_block() {
    awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" -v managed="$CUPSD_CONF.new" '
        $0 == begin {
            while ((getline line < managed) > 0) print line
            close(managed)
            in_managed = 1
            next
        }
        $0 == end { in_managed = 0; next }
        !in_managed { print }
    ' "$CUPSD_CONF" > "$CUPSD_CONF.tmp"
}

render_managed_config > "$CUPSD_CONF.new"

if [ ! -s "$CUPSD_CONF" ]; then
    mv "$CUPSD_CONF.new" "$CUPSD_CONF"
    echo "Created cupsd.conf with the managed configuration block."
elif grep -qF -- "$MANAGED_BEGIN" "$CUPSD_CONF" &&
     grep -qF -- "$MANAGED_END" "$CUPSD_CONF"; then
    update_managed_block
    mv "$CUPSD_CONF.tmp" "$CUPSD_CONF"
    rm -f "$CUPSD_CONF.new"
    echo "Updated the managed cupsd.conf block; custom settings preserved."
else
    # Older versions rewrote cupsd.conf on every start. Migrate only when the
    # file is still byte-for-byte what we generated; otherwise treat any
    # difference as a user customisation and leave the file untouched.
    awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" \
        '$0 != begin && $0 != end' "$CUPSD_CONF.new" > "$CUPSD_CONF.legacy"
    if cmp -s "$CUPSD_CONF" "$CUPSD_CONF.legacy"; then
        mv "$CUPSD_CONF.new" "$CUPSD_CONF"
        echo "Migrated cupsd.conf to the managed configuration block."
    else
        rm -f "$CUPSD_CONF.new"
        echo "Preserving existing cupsd.conf with custom changes (no managed markers)."
        echo "To let the add-on manage it again, back it up and remove it before restarting."
    fi
    rm -f "$CUPSD_CONF.legacy"
fi

# ─────────────────────────────────────────────────────────────
# Replace /etc/cups with a directory-level symlink so that
# CUPS atomic file writes (write .N, rename .O, rename .N)
# operate inside the persistent storage instead of replacing
# individual file symlinks with ephemeral real files.
#
# Background: CUPS saves printers.conf atomically — it writes
# printers.conf.N, renames printers.conf→printers.conf.O, then
# renames printers.conf.N→printers.conf. With file-level
# symlinks the first rename() replaces the symlink itself with
# a real file in the container's ephemeral layer, so all
# subsequent writes bypass the persistent share. After a
# container restart the real file is gone and the old
# (empty/stale) printers.conf in /share/cups/ is used again.
#
# A directory symlink avoids this because rename() only touches
# files inside the resolved target directory, leaving /etc/cups
# as a symlink intact.
# ─────────────────────────────────────────────────────────────

if [ -d /etc/cups ] && [ ! -L /etc/cups ]; then
    echo "Replacing /etc/cups directory with symlink to /share/cups/config..."

    # Copy any default config files from the package-installed
    # /etc/cups/ (e.g. cups-files.conf) that don't yet exist in
    # the persistent storage.
    for item in /etc/cups/*; do
        [ -e "$item" ] || continue
        base="$(basename "$item")"
        # Skip files/dirs we manage ourselves or that may be
        # stale from a previous file-level symlink approach.
        case "$base" in
            cupsd.conf|printers.conf|printers.conf.O|ppd|ssl)
                continue
                ;;
        esac
        if [ ! -e "/share/cups/config/$base" ]; then
            cp -r "$item" "/share/cups/config/$base"
            echo "  Copied default $base to persistent storage."
        fi
    done

    # Safeguard: make sure printers.conf exists in the
    # persistent location before we switch over.
    touch /share/cups/config/printers.conf

    rm -rf /etc/cups
    ln -sf /share/cups/config /etc/cups
    echo "/etc/cups → /share/cups/config"
else
    # Already a symlink or does not exist — just ensure it.
    rm -rf /etc/cups
    ln -sf /share/cups/config /etc/cups
fi

# Verify printers.conf exists in the persistent location
if [ ! -f /share/cups/config/printers.conf ]; then
    touch /share/cups/config/printers.conf
fi

# Install user-supplied printer driver .deb (e.g. Canon UFR II for MF4412)
DRIVER_DEB=$(jq -r '.printer_driver_deb // empty' /data/options.json 2>/dev/null)
if [ -n "$DRIVER_DEB" ]; then
    DRIVER_PATH="/share/${DRIVER_DEB}"
    if [ -f "$DRIVER_PATH" ]; then
        echo "Installing printer driver from ${DRIVER_PATH}..."
        EXTRACT_DIR=$(mktemp -d)
        dpkg -x "$DRIVER_PATH" "$EXTRACT_DIR"
        # Copy CUPS filters
        if [ -d "${EXTRACT_DIR}/usr/lib/cups/filter" ]; then
            cp -r "${EXTRACT_DIR}/usr/lib/cups/filter/." /usr/lib/cups/filter/
            chmod 755 /usr/lib/cups/filter/*
        fi
        # Copy shared libraries
        if [ -d "${EXTRACT_DIR}/usr/lib" ]; then
            find "${EXTRACT_DIR}/usr/lib" -name "*.so*" -exec cp {} /usr/lib/ \;
        fi
        # Copy PPD files
        if [ -d "${EXTRACT_DIR}/usr/share/cups/model" ]; then
            cp -r "${EXTRACT_DIR}/usr/share/cups/model/." /usr/share/cups/model/
        fi
        rm -rf "$EXTRACT_DIR"
        echo "Printer driver installed."
    else
        echo "Warning: printer_driver_deb set to '${DRIVER_DEB}' but /share/${DRIVER_DEB} was not found."
    fi
fi

# Verify printer drivers are available
echo "Available printer drivers:"
lpinfo -m 2>/dev/null | head -20 || echo "CUPS not yet running; drivers will be listed after start."

# D-Bus + Avahi so cupsd can advertise shared queues as AirPrint (_ipp._tcp).
# This init script blocks on cupsd -f, so daemons must start here rather than
# as sibling s6 services.
echo "Starting D-Bus and Avahi for AirPrint..."
mkdir -p /run/dbus /run/avahi-daemon
dbus-uuidgen --ensure >/dev/null 2>&1 || true
if [ ! -S /run/dbus/system_bus_socket ]; then
    dbus-daemon --system || echo "Warning: dbus-daemon failed to start"
fi
for _ in $(seq 1 25); do
    [ -S /run/dbus/system_bus_socket ] && break
    sleep 0.2
done
if [ ! -S /run/avahi-daemon/socket ]; then
    if avahi-daemon --daemonize --no-drop-root --no-rlimits; then
        echo "Avahi started."
    else
        echo "Warning: avahi-daemon failed; AirPrint discovery may not work."
    fi
fi
for _ in $(seq 1 25); do
    [ -S /run/avahi-daemon/socket ] && break
    sleep 0.2
done

# Start CUPS service
/usr/sbin/cupsd -f