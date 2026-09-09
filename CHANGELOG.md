# Changelog

## [1.3.1] — 2026-09-09

- Fix missing Canon/HP/Brother CUPS PPDs: Alpine splits Gutenprint, so install
  `gutenprint-cups` (filters + PPDs) in addition to `gutenprint`
- Fix web UI "Cancel Job" returning Unauthorized: put Cancel-Job in a real
  Policy with AuthType None (top-level Limit is ignored; no admin user exists)
- Advertise shared printers via AirPrint/Bonjour: run Avahi (reflector mode)
  and enable CUPS DNS-SD browsing so Apple devices can discover the queues
- Allow IPv6 LAN clients (@LOCAL, fe80::/10, fd00::/8). Port 631 listens on
  v6 and macOS prefers AAAA for *.local, which otherwise 403s the web UI

## [1.2.1] — 2026-05-17

- Fix: remove hardcoded aarch64 default from BUILD_FROM ARG

## [1.2.0] — 2026-05-15

- Fix printer list not persisting across container restarts: replace file-level
  CUPS config symlinks with a directory-level symlink (/etc/cups → /share/cups/config)
  to prevent CUPS atomic file writes from breaking the symlink and writing to
  ephemeral storage

## [1.1.1] — 2026-05-15

- Fix build failure on Alpine 3.23 (HA OS 2026.5): remove unavailable packages hplip, foomatic-db, foomatic-db-ppds

## [1.1.0] — 2026-05-15

- Upgrade to CUPS 3.0
- Fix CUPS printer config persistence to HA shared directory (/share/cups)
- Fix build_from config with default BUILD_FROM arg for reliable Docker builds

## [1.0.0] — 2026-03-30

- Add Canon MF4412 (UFR II) printer driver support
- Install printer drivers (HP, Gutenprint, Foomatic) in container setup

## [0.9.0] — 2026-01-25

- Persist PPD documents across restarts

## [0.8.0] — 2025-05-08

- Move everything into a subfolder and add repository YAML
- Update docs for manual installation

## [0.7.0] — 2025-03-18

- Add Epson printer drivers
- Persist configuration and printer lists

## [0.6.0] — 2025-03-15

- Remove basic authentication
- Initial CUPS add-on release
