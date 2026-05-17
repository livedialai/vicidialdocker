#!/bin/bash
# build.sh — ViciDial Docker mit Asterisk 18 + ConfBridge bauen und starten
set -e

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()   { echo -e "${GREEN}[✓]${NC} $1"; }
info()  { echo -e "${CYAN}[i]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║    ViciDial Docker — Asterisk 18 + ConfBridge          ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Server-IP ermitteln
SERVER_IP=$(hostname -I | awk '{print $1}')
info "Server-IP: $SERVER_IP"
export SERVER_IP

# ── 1. Images bauen ──────────────────────────────────────
info "Baue Docker-Images..."
echo "  → asterisk (Asterisk 18.18.1 + ViciDial-Patches + ConfBridge)..."
docker compose build asterisk 2>&1 | tail -3
log "Asterisk-Image gebaut"

echo "  → mariadb..."
docker compose build mariadb 2>&1 | tail -3
log "MariaDB-Image gebaut"

echo "  → apache (PHP 7.4 + astguiclient)..."
docker compose build apache 2>&1 | tail -3
log "Apache-Image gebaut"

# ── 2. Container starten ─────────────────────────────────
info "Starte Container..."
docker compose up -d

# Warte auf DB
info "Warte auf MariaDB..."
for i in $(seq 1 30); do
    docker exec vicidial-db mysqladmin ping -h localhost &>/dev/null && break
    sleep 2
done
log "MariaDB bereit"

# ── 3. ViciDial Schema + Daten ───────────────────────────
info "Installiere ViciDial-Datenbank..."
# SVN-Checkout (falls nicht im Apache-Container)
if ! docker exec vicidial-apache test -f /usr/src/astguiclient/trunk/extras/MySQL_AST_CREATE_tables.sql 2>/dev/null; then
    docker exec vicidial-apache mkdir -p /usr/src/astguiclient
    docker exec vicidial-apache svn checkout --non-interactive --trust-server-cert-failures=unknown-ca,cn-mismatch \
        svn://svn.eflo.net/agc_2-X/trunk /usr/src/astguiclient/trunk 2>&1 | tail -1
fi

# Schema einspielen
docker exec -i vicidial-db mysql -u root -pvicidial asterisk <<'SQL'
use asterisk;
SET GLOBAL connect_timeout=60;
SQL

docker exec vicidial-apache cat /usr/src/astguiclient/trunk/extras/MySQL_AST_CREATE_tables.sql | \
    docker exec -i vicidial-db mysql -u root -pvicidial asterisk 2>&1 | tail -3

docker exec vicidial-apache cat /usr/src/astguiclient/trunk/extras/first_server_install.sql | \
    docker exec -i vicidial-db mysql -u root -pvicidial asterisk 2>&1 | tail -3

docker exec vicidial-db mysql -u root -pvicidial asterisk -e \
    "UPDATE servers SET asterisk_version='18.18.1-vici';" 2>&1

log "Datenbank-Schema installiert"

# ── 4. ConfBridge-Integration ────────────────────────────
info "Konfiguriere ConfBridge..."

# confbridge_conferences in DB
docker exec -i vicidial-db mysql -u root -pvicidial asterisk <<SQL
INSERT INTO vicidial_confbridges (confbridge_id, server_ip, confbridge_name, active) VALUES
(9600000, '$SERVER_IP', '', 0),
(9600001, '$SERVER_IP', '', 0),
(9600002, '$SERVER_IP', '', 0),
(9600003, '$SERVER_IP', '', 0),
(9600004, '$SERVER_IP', '', 0),
(9600005, '$SERVER_IP', '', 0),
(9600006, '$SERVER_IP', '', 0),
(9600007, '$SERVER_IP', '', 0),
(9600008, '$SERVER_IP', '', 0),
(9600009, '$SERVER_IP', '', 0)
ON DUPLICATE KEY UPDATE server_ip='$SERVER_IP';
SQL

# Conferencing Engine auf CONFBRIDGE
docker exec vicidial-db mysql -u root -pvicidial asterisk -e \
    "UPDATE servers SET confbridge_engine='CONFBRIDGE', AST_ver='confbridge';" 2>&1

# VARactive_keepalives → C für ConfBridge-Screen
docker exec vicidial-db mysql -u root -pvicidial asterisk -e \
    "UPDATE system_settings SET var_active_keepalives='12345689CE' WHERE var_active_keepalives IS NOT NULL;" 2>&1 || true

log "ConfBridge-Konfiguration abgeschlossen"

# ── 5. Server-IP updaten ─────────────────────────────────
if docker exec vicidial-apache test -f /usr/share/astguiclient/ADMIN_update_server_ip.pl 2>/dev/null; then
    docker exec vicidial-apache perl /usr/share/astguiclient/ADMIN_update_server_ip.pl \
        --old-server_ip=10.10.10.15 --server_ip=$SERVER_IP --auto 2>&1 | tail -1
fi

# ── Fertig ────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║     ViciDial Docker bereit!                            ║"
echo "╠════════════════════════════════════════════════════════╣"
echo "║  URL:      http://$SERVER_IP/vicidial/welcome.php"
echo "║  Admin:    http://$SERVER_IP/vicidial/admin.php"
echo "║  Agent:    http://$SERVER_IP/vicidial/agc/vicidial.php"
echo "║  Login:    6666 / 1234"
echo "║  Conf:     ConfBridge (kein DAHDI nötig)"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
