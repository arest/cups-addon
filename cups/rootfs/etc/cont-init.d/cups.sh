#!/usr/bin/with-contenv bash
set -euo pipefail

source /usr/lib/bashio/bashio.sh

ADMIN_USER="$(bashio::config 'admin_username')"
ADMIN_PASSWORD="$(bashio::config 'admin_password')"

if [[ -z "${ADMIN_USER}" ]]; then
  bashio::log.fatal "Configuration admin_username must not be empty"
  exit 1
fi

if [[ -z "${ADMIN_PASSWORD}" ]]; then
  bashio::log.fatal "Configuration admin_password must not be empty"
  exit 1
fi

if [[ "${ADMIN_PASSWORD}" == "change_me_now" ]]; then
  bashio::log.fatal "Set a strong admin_password in add-on configuration before starting"
  exit 1
fi

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

# Write default configuration only on first run to avoid clobbering user changes.
if [[ ! -f /data/cups/config/cupsd.conf ]]; then
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

# Admin access requires authentication
<Location /admin>
  AuthType Basic
  Require user @SYSTEM
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

<Location /admin/conf>
  AuthType Basic
  Require user @SYSTEM
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

<Location /admin/log>
  AuthType Basic
  Require user @SYSTEM
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

# Job listing remains LAN-accessible
<Location /jobs>
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Location>

# Printing remains LAN-accessible
<Limit Send-Document Send-URI Create-Job>
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Limit>

# Admin-level operations require authenticated system user
<Limit CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Move-Job>
  AuthType Basic
  Require user @SYSTEM
  Order allow,deny
  Allow localhost
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
  Allow 192.168.0.0/16
</Limit>

# Enable web interface
WebInterface Yes

# Default settings
DefaultAuthType Basic
JobSheets none,none
PreserveJobHistory No
EOL
fi

if ! id -u "${ADMIN_USER}" >/dev/null 2>&1; then
  adduser -D -H -s /sbin/nologin "${ADMIN_USER}"
fi

addgroup "${ADMIN_USER}" lpadmin >/dev/null 2>&1 || true
printf '%s:%s\n' "${ADMIN_USER}" "${ADMIN_PASSWORD}" | chpasswd

# Create a symlink from the default config location to our persistent location
ln -sf /data/cups/config/cupsd.conf /etc/cups/cupsd.conf
ln -sf /data/cups/config/printers.conf /etc/cups/printers.conf
ln -sf /data/cups/config/ppd /etc/cups/ppd
ln -sf /data/cups/config/ssl /etc/cups/ssl
