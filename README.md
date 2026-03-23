# Home Assistant CUPS Print Server Add-on

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/arest/cups-addon)
[![Supports aarch64 Architecture](https://img.shields.io/badge/aarch64-yes-green.svg)](https://github.com/arest/cups-addon)
[![Supports amd64 Architecture](https://img.shields.io/badge/amd64-yes-green.svg)](https://github.com/arest/cups-addon)
[![Supports armhf Architecture](https://img.shields.io/badge/armhf-yes-green.svg)](https://github.com/arest/cups-addon)
[![Supports armv7 Architecture](https://img.shields.io/badge/armv7-yes-green.svg)](https://github.com/arest/cups-addon)
[![Supports i386 Architecture](https://img.shields.io/badge/i386-yes-green.svg)](https://github.com/arest/cups-addon)

This Home Assistant add-on provides a CUPS (Common Unix Printing System) print server, allowing you to manage and share printers over your local network. It's designed for Home Assistant users who want to integrate network printing capabilities directly into their smart home setup.

## Features

- **Network Printing**: Share printers across your local network using CUPS
- **Web Interface**: Access the CUPS administration panel at `http://<your-ha-ip>:631` to add and manage printers
- **Secure Administration**: Authenticated CUPS admin interface with add-on credentials
- **Printer Support**: Compatible with a wide range of network and USB printers
- **Lightweight**: Built on Alpine Linux for minimal resource usage
- **Data Persistence**: Printer settings and configurations persist across restarts and updates

## Installation

### From Home Assistant Add-on Store

1. Navigate to your Home Assistant instance.
2. Go to **Settings** → **Add-ons** → **Add-on Store**.
3. Click the 3-dot menu in the top right corner and select **Repositories**.
4. Add `https://github.com/arest/cups-addon` as a repository.
5. Find the "CUPS Print Server" add-on in the store and click it.
6. Click **Install**.

### Manual Installation

If you prefer to manually install:

1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/arest/cups-addon.git
   ```

2. Copy the repository to your Home Assistant add-ons directory:
   ```bash
   scp -r cups-addon/cups root@<your-ha-ip>:/addons/local/
   ```

3. In Home Assistant, go to **Settings** → **Add-ons** → **Add-on Store**.
4. Click the 3-dot menu (top right) → **Repositories**.
5. Add `local_addons` as a repository URL and click **Add**.
6. Refresh the add-on store to see "CUPS Print Server."
7. Install the add-on.

## Configuration

The add-on provides the following configuration options:

```yaml
admin_username: printadmin
admin_password: your_secure_password
force_regenerate_config: false
```

- **admin_username**: Username for the CUPS admin interface (required)
- **admin_password**: Password for the CUPS admin interface (required)
- **force_regenerate_config**: One-shot option to replace persisted `cupsd.conf` with the latest managed default (a backup is created)

Printing from LAN clients remains open, while CUPS administration requires the configured credentials.

## Updating cupsd.conf Safely

The add-on manages default `cupsd.conf` from a dedicated template file and tracks the applied template hash.

- If no config exists, it creates a managed default file.
- If a managed file is based on an older template hash (or managed version), it is automatically backed up and replaced.
- If your file is unmanaged (custom/legacy), it is left untouched.

To apply the latest managed defaults on an existing install, set `force_regenerate_config: true` for one restart. The old file is backed up as `cupsd.conf.bak.<timestamp>`.
After restart, set `force_regenerate_config` back to `false`.

## Networking Notes

This add-on uses host networking so mDNS/Bonjour announcements are visible on the LAN.
This is required for AirPrint discovery by iOS/macOS clients.

After configuring:

1. Start the add-on from the Info tab.
2. Check the Log tab to ensure it starts successfully.
3. Access the CUPS web interface at `http://<your-ha-ip>:631`.

## Usage

### Access the Web Interface

Visit `http://<your-ha-ip>:631` in your browser.

### Add a Printer

1. Go to the **Administration** tab.
2. Click **Add Printer** and follow the prompts.
3. Select the appropriate driver for your printer model.

### Print from Devices

Configure your computers or devices to use the printer at `<your-ha-ip>:631`.

## Supported Printer Types

This add-on supports various printer types:

- Network printers (via IPP, LPD, etc.)
- USB printers connected to your Home Assistant host
- Shared Windows printers (via Samba)
- AirPrint for Apple devices

## Troubleshooting

### Can't Access Web Interface

- Ensure the add-on is running (check logs).
- Verify port 631 isn't blocked by your firewall.
- Check that your network allows access to the Home Assistant device.

### Printer Not Detected

- Ensure the printer is network-accessible or connected via USB to the host.
- For USB printers, you may need to configure USB device pass-through to the add-on.
- Check CUPS logs in the add-on's Log tab.


### Printer Drivers
   https://www.openprinting.org/download/PPD/
   https://www.openprinting.org/drivers/

### Authentication Issues

- Verify you're using the correct username and password configured in the add-on settings.
- If you've forgotten your password, you can reset it by reconfiguring the add-on.

## Contributing

Contributions are welcome! Please:

1. Fork this repository.
2. Create a feature branch (`git checkout -b feature/your-feature`).
3. Commit your changes (`git commit -m "Add your feature"`).
4. Push to the branch (`git push origin feature/your-feature`).
5. Open a pull request.

## License

This project is licensed under the MIT License.

## Credits

- Built by [Andrea Restello](https://github.com/arest)
- Powered by [Home Assistant](https://www.home-assistant.io/) and [CUPS](https://www.cups.org/)

## Data Persistence

This add-on stores all CUPS data in the Home Assistant `/data` directory, ensuring:

- Printer configurations persist across add-on restarts
- Print jobs and settings are maintained through system reboots
- Add-on updates won't cause loss of printer configurations
- All CUPS data is included in Home Assistant backups

The following directories are maintained in the persistent storage:
- `/data/cups/config`: CUPS configuration files
- `/data/cups/cache`: CUPS cache data
- `/data/cups/logs`: CUPS log files
- `/data/cups/state`: CUPS state information

