#!/usr/bin/with-contenv bash
set -euo pipefail

source /usr/lib/bashio/bashio.sh

ADMIN_USER="$(bashio::config 'admin_username')"
ADMIN_PASSWORD="$(bashio::config 'admin_password')"
FORCE_REGENERATE_CONFIG="$(bashio::config 'force_regenerate_config')"

CUPSD_CONF="/data/cups/config/cupsd.conf"
TEMPLATE_PATH="/etc/cups/cupsd.conf.template"

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

if [[ ! -f "${TEMPLATE_PATH}" ]]; then
  bashio::log.fatal "Managed CUPS template not found at ${TEMPLATE_PATH}"
  exit 1
fi

TEMPLATE_SHA256="$(sha256sum "${TEMPLATE_PATH}" | awk '{print $1}')"

MANAGED_CONFIG_VERSION="3"

write_managed_cupsd_conf() {
  {
    echo "# HA_ADDON_MANAGED_VERSION=${MANAGED_CONFIG_VERSION}"
    echo "# HA_ADDON_TEMPLATE_SHA256=${TEMPLATE_SHA256}"
    cat "${TEMPLATE_PATH}"
  } > "${CUPSD_CONF}"
}

backup_and_regenerate_cupsd_conf() {
  local ts
  ts="$(date +%Y%m%d%H%M%S)"
  cp "${CUPSD_CONF}" "${CUPSD_CONF}.bak.${ts}"
  write_managed_cupsd_conf
}

if [[ ! -f "${CUPSD_CONF}" ]]; then
  bashio::log.info "No persisted cupsd.conf found, creating managed default configuration"
  write_managed_cupsd_conf
else
  CURRENT_MANAGED_VERSION="$(grep -E '^# HA_ADDON_MANAGED_VERSION=' "${CUPSD_CONF}" | head -n1 | cut -d'=' -f2 || true)"
  CURRENT_TEMPLATE_SHA256="$(grep -E '^# HA_ADDON_TEMPLATE_SHA256=' "${CUPSD_CONF}" | head -n1 | cut -d'=' -f2 || true)"

  if [[ "${FORCE_REGENERATE_CONFIG}" == "true" ]]; then
    bashio::log.warning "force_regenerate_config=true: replacing existing cupsd.conf and writing backup"
    backup_and_regenerate_cupsd_conf
  elif [[ -n "${CURRENT_MANAGED_VERSION}" ]]; then
    if [[ "${CURRENT_MANAGED_VERSION}" != "${MANAGED_CONFIG_VERSION}" ]]; then
      bashio::log.info "Updating managed cupsd.conf from version ${CURRENT_MANAGED_VERSION} to ${MANAGED_CONFIG_VERSION}"
      backup_and_regenerate_cupsd_conf
    elif [[ "${CURRENT_TEMPLATE_SHA256}" != "${TEMPLATE_SHA256}" ]]; then
      bashio::log.info "Updating managed cupsd.conf because template content changed"
      backup_and_regenerate_cupsd_conf
    fi
  elif [[ -z "${CURRENT_MANAGED_VERSION}" ]]; then
    bashio::log.warning "Existing cupsd.conf is unmanaged; keeping it unchanged. Set force_regenerate_config=true to replace it with managed defaults"
  fi
fi

if ! id -u "${ADMIN_USER}" >/dev/null 2>&1; then
  adduser -D -H -s /sbin/nologin "${ADMIN_USER}"
fi

addgroup "${ADMIN_USER}" lpadmin >/dev/null 2>&1 || true
printf '%s:%s\n' "${ADMIN_USER}" "${ADMIN_PASSWORD}" | chpasswd

# Create a symlink from the default config location to our persistent location
ln -sf "${CUPSD_CONF}" /etc/cups/cupsd.conf
ln -sf /data/cups/config/printers.conf /etc/cups/printers.conf
ln -sf /data/cups/config/ppd /etc/cups/ppd
ln -sf /data/cups/config/ssl /etc/cups/ssl
