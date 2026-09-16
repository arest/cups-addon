#!/usr/bin/env bash
# Boot the built add-on image the way the Supervisor does and verify that CUPS
# actually comes up, that the printer driver artifacts we compile/patch into the
# image are present, and that the access policy still lets a LAN client reach the
# web UI (the regression fixed in 1.3.2).
#
# Usage: smoke_test.sh <image>
set -euo pipefail

IMAGE="${1:?usage: smoke_test.sh <image>}"

SUFFIX="$$-$(date +%s)"
NET="cups-smoke-net-${SUFFIX}"
SERVER="cups-smoke-server-${SUFFIX}"

pass=0
fail=0

ok() { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail=$((fail + 1)); }

expect_eq() { # description, actual, expected
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi
}

expect_contains() { # description, haystack, needle
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) bad "$1 (missing '$3')" ;;
  esac
}

expect_absent() { # description, haystack, needle
  case "$2" in
    *"$3"*) bad "$1 (unexpectedly found '$3')" ;;
    *) ok "$1" ;;
  esac
}

cleanup() {
  docker rm -f "$SERVER" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

server_exec() { docker exec "$SERVER" sh -c "$1"; }

echo "==> starting $IMAGE on an isolated bridge network"
docker network create "$NET" >/dev/null
docker run -d --name "$SERVER" --network "$NET" "$IMAGE" >/dev/null

# The Supervisor treats `init: false` services as up once s6 finishes the
# oneshot init; wait for cupsd to answer on its socket instead of guessing.
scheduler=""
for _ in $(seq 1 36); do
  scheduler="$(server_exec 'lpstat -r 2>/dev/null' || true)"
  case "$scheduler" in
    *"scheduler is running"*) break ;;
  esac
  sleep 5
done
expect_eq "cupsd scheduler is running" "$scheduler" "scheduler is running"

expect_eq "container is still running" \
  "$(docker inspect "$SERVER" --format '{{.State.Status}}')" "running"

if [ "$(server_exec 'curl -s -o /dev/null -w "%{http_code}" --max-time 20 http://127.0.0.1:631/' || echo 000)" = "200" ]; then
  ok "cupsd serves the web UI on port 631"
else
  bad "cupsd does not serve the web UI on port 631"
fi

# The declared HEALTHCHECK is what the Supervisor health-checks the add-on with,
# so prove it actually passes rather than trusting the CMD line.
health=""
for _ in $(seq 1 24); do
  health="$(docker inspect "$SERVER" --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' 2>/dev/null || true)"
  [ "$health" = "healthy" ] && break
  sleep 5
done
expect_eq "declared HEALTHCHECK reports healthy" "$health" "healthy"

# --- printer driver artifacts ------------------------------------------------
# Each of these is either compiled from vendored source or shipped as a PPD in
# rootfs/, so a broken COPY/build step shows up here rather than on a user's Pi.
missing=""
for filter in rastertokpsl raster2dymolw raster2dymolm rastertogutenprint.5.3 gstoraster; do
  server_exec "test -x /usr/lib/cups/filter/$filter" || missing="$missing $filter"
done
expect_eq "compiled CUPS filter binaries are present and executable" "$missing" ""

for ppd in \
  /usr/share/cups/model/lw4xl.ppd \
  /usr/share/cups/model/lw450.ppd \
  /usr/share/cups/model/kyocera/Kyocera_FS-1040GDI.ppd \
  /usr/share/cups/model/kyocera/Kyocera_FS-1060DNGDI.ppd
do
  server_exec "test -f $ppd" && ok "PPD present: $ppd" || bad "PPD missing: $ppd"
done

dymo_count="$(server_exec 'ls /usr/share/cups/model/*.ppd 2>/dev/null | wc -l' || echo 0)"
kyocera_count="$(server_exec 'ls /usr/share/cups/model/kyocera/*.ppd 2>/dev/null | wc -l' || echo 0)"
if [ "${dymo_count:-0}" -ge 20 ]; then
  ok "Dymo PPD set installed ($dymo_count)"
else
  bad "Dymo PPD set looks truncated (got $dymo_count, want >= 20)"
fi
if [ "${kyocera_count:-0}" -ge 6 ]; then
  ok "Kyocera PPD set installed ($kyocera_count)"
else
  bad "Kyocera PPD set looks truncated (got $kyocera_count, want >= 6)"
fi

# --- AirPrint / Avahi --------------------------------------------------------
# avahi-daemon is started with --daemonize, which always returns 0 even when the
# child then exits (e.g. because D-Bus was not actually usable yet), so poll for
# the process rather than sampling once.
avahi_procs=""
for _ in $(seq 1 12); do
  avahi_procs="$(server_exec 'pgrep -a avahi-daemon 2>/dev/null' || true)"
  [ -n "$avahi_procs" ] && break
  sleep 5
done
if [ -n "$avahi_procs" ]; then
  ok "avahi-daemon is running for AirPrint/Bonjour"
else
  bad "avahi-daemon is not running (no process matches 'avahi-daemon')"
fi
if server_exec '[ -S /run/avahi-daemon/socket ]'; then
  ok "avahi-daemon control socket exists"
else
  bad "avahi-daemon control socket is missing"
fi

# --- access policy -----------------------------------------------------------
# Assert the generated cupsd.conf keeps the LAN ranges from 1.3.2 open and does
# not silently degrade into an allow-all policy.
cupsd_conf="$(server_exec 'cat /share/cups/config/cupsd.conf' || true)"
if [ -z "$cupsd_conf" ]; then
  bad "could not read the generated cupsd.conf"
else
  expect_contains "ACL allows localhost" "$cupsd_conf" "Allow localhost"
  expect_contains "ACL allows @LOCAL interfaces" "$cupsd_conf" "Allow @LOCAL"
  expect_contains "ACL allows RFC1918 IPv4 ranges" "$cupsd_conf" "Allow 192.168.0.0/16"
  expect_contains "ACL allows IPv6 link-local" "$cupsd_conf" "Allow fe80::/10"
  expect_contains "ACL allows IPv6 unique-local" "$cupsd_conf" "Allow fd00::/8"
  expect_absent "ACL is not an allow-all policy" "$cupsd_conf" "Allow all"
  expect_contains "Cancel-Job is authorised in a Policy" \
    "$cupsd_conf" "Cancel-Job Cancel-Jobs"
fi

# --- reachability from a LAN client -----------------------------------------
# A second container on the same bridge is the closest stand-in for a LAN
# printer client. Requests must use the server IP: cupsd rejects requests whose
# Host header it does not recognise with 400.
server_ip="$(docker inspect "$SERVER" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')"
if [ -z "$server_ip" ]; then
  bad "could not determine the container IP address"
else
  for path in / /printers/ /admin; do
    code="$(docker run --rm --network "$NET" --entrypoint /bin/sh "$IMAGE" \
      -c "curl -s -o /dev/null -w '%{http_code}' --max-time 20 http://$server_ip:631$path" \
      2>/dev/null || echo "000")"
    expect_eq "LAN client GET $path" "$code" "200"
  done
fi

if [ "$fail" -ne 0 ]; then
  echo
  echo "==> diagnostics (container logs)"
  docker logs "$SERVER" 2>&1 | tail -60 || true
  echo
  echo "==> diagnostics (processes)"
  server_exec 'ps -ef 2>/dev/null || ps w 2>/dev/null || true'
  echo
  echo "==> diagnostics (runtime sockets)"
  server_exec 'ls -la /run/dbus /run/avahi-daemon 2>&1 || true'
fi

echo
echo "==> $pass passed, $fail failed"
[ "$fail" -eq 0 ]
