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
# Write a fresh cupsd.conf (this is static config we own)
# ─────────────────────────────────────────────────────────────
cat > /share/cups/config/cupsd.conf << 'EOL'
# Listen on all interfaces
Listen 0.0.0.0:631

WebInterface Yes
DefaultAuthType None
DefaultEncryption Never
JobSheets none,none
PreserveJobHistory No

# Allow access from local network
<Location />
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

<Location /admin>
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

<Location /admin/conf>
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

<Location /jobs>
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

# Top-level <Limit> is ignored by cupsd; job ops must live in a Policy.
# Cancel-Job (the web UI "Cancel Job" button) is not Cancel-My-Jobs.
# The baked-in default policy requires @OWNER/@SYSTEM, but this image
# never creates an admin user, so cancels always returned Unauthorized.
<Policy default>
  JobPrivateAccess all
  JobPrivateValues none
  SubscriptionPrivateAccess all
  SubscriptionPrivateValues none

  <Limit Create-Job Print-Job Print-URI Validate-Job>
    Order allow,deny
    Allow localhost
    Allow 10.0.0.0/8
    Allow 172.16.0.0/12
    Allow 192.168.0.0/16
  </Limit>

  <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Job Cancel-Jobs Cancel-Current-Job Cancel-My-Jobs Suspend-Current-Job Resume-Job Close-Job CUPS-Move-Job CUPS-Get-Document Pause-Printer Resume-Printer Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs CUPS-Accept-Jobs CUPS-Reject-Jobs Promote-Job CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Get-Devices>
    AuthType None
    Order allow,deny
    Allow localhost
    Allow 10.0.0.0/8
    Allow 172.16.0.0/12
    Allow 192.168.0.0/16
  </Limit>

  <Limit All>
    AuthType None
    Order allow,deny
    Allow localhost
    Allow 10.0.0.0/8
    Allow 172.16.0.0/12
    Allow 192.168.0.0/16
  </Limit>
</Policy>
EOL

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

# Start CUPS service
/usr/sbin/cupsd -f