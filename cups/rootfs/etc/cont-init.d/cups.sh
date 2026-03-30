#!/usr/bin/with-contenv bash

# Create CUPS data directories for persistence
mkdir -p /data/cups/cache
mkdir -p /data/cups/logs
mkdir -p /data/cups/state
mkdir -p /data/cups/config
mkdir -p /data/cups/config/ppd
mkdir -p /data/cups/config/ssl

# Set proper permissions
chown -R root:lp /data/cups
chmod -R 775 /data/cups

# Create CUPS configuration directory if it doesn't exist
mkdir -p /etc/cups

# Basic CUPS configuration without admin authentication
cat > /data/cups/config/cupsd.conf << EOL
# Listen on all interfaces
Listen 0.0.0.0:631

# Allow access from local network
<Location />
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

# Admin access (no authentication)
<Location /admin>
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

# Job management permissions
<Location /jobs>
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

<Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Current-Job Suspend-Current-Job Resume-Job Cancel-My-Jobs Close-Job CUPS-Move-Job CUPS-Get-Document>
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Limit>

# Enable web interface
WebInterface Yes

# Default settings
DefaultAuthType None
JobSheets none,none
PreserveJobHistory No
EOL

# Create a symlink from the default config location to our persistent location
ln -sf /data/cups/config/cupsd.conf /etc/cups/cupsd.conf
ln -sf /data/cups/config/printers.conf /etc/cups/printers.conf
ln -sf /data/cups/config/ppd /etc/cups/ppd
ln -sf /data/cups/config/ssl /etc/cups/ssl

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