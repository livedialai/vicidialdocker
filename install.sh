#!/bin/bash
# install.sh — ViciDial Docker Post-Install: DB-Schema, ConfBridge, Konfiguration
set -e

GREEN="\033[0;32m"; CYAN="\033[0;36m"; RED="\033[0;31m"; NC="\033[0m"
log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

SERVER_IP="${SERVER_IP:-$(hostname -I | awk '{print $1}')}"
DB_PASS="${DB_PASS:-vicidial}"

if [ -z "$SERVER_IP" ]; then
    echo "Usage: export SERVER_IP=<deine-server-ip> && bash install.sh"
    exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║   ViciDial Docker — Installation             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
info "Server-IP: $SERVER_IP"

# ── 1. Warten auf MariaDB ─────────────────────────────
info "Warte auf MariaDB..."
for i in $(seq 1 30); do
    docker exec vicidial-db mysqladmin ping -h localhost --silent 2>/dev/null && break
    sleep 2
done
docker exec vicidial-db mysqladmin ping -h localhost --silent 2>/dev/null || err "MariaDB nicht erreichbar"
log "MariaDB bereit"

# ── 2. SVN-Checkout (falls nicht im Image) ────────────
if ! docker exec vicidial-apache test -f /usr/src/astguiclient/trunk/extras/MySQL_AST_CREATE_tables.sql 2>/dev/null; then
    info "Hole astguiclient aus SVN..."
    docker exec vicidial-apache mkdir -p /usr/src/astguiclient
    docker exec vicidial-apache svn checkout --non-interactive \
        --trust-server-cert-failures=unknown-ca,cn-mismatch \
        svn://svn.eflo.net/agc_2-X/trunk /usr/src/astguiclient/trunk 2>&1 | tail -1
fi
log "astguiclient-Quellen bereit"

# ── 3. DB-Schema einspielen ───────────────────────────
info "Installiere Datenbank-Schema..."
docker exec vicidial-db mysql -u root -p"$DB_PASS" -e "SET GLOBAL connect_timeout=60;" 2>/dev/null

docker exec vicidial-apache cat /usr/src/astguiclient/trunk/extras/MySQL_AST_CREATE_tables.sql | \
    docker exec -i vicidial-db mysql -u root -p"$DB_PASS" asterisk 2>&1 | tail -3
log "Tabellen erstellt"

# ── 4. Default-Konfiguration ─────────────────────────
info "Spiele Default-Konfiguration ein..."
docker exec vicidial-apache cat /usr/src/astguiclient/trunk/extras/first_server_install.sql | \
    docker exec -i vicidial-db mysql -u root -p"$DB_PASS" asterisk 2>&1 | tail -1
log "Default-Konfiguration installiert"

# ── 5. Asterisk-Version setzen ───────────────────────
docker exec vicidial-db mysql -u root -p"$DB_PASS" asterisk -e \
    "UPDATE servers SET asterisk_version='18.18.1-vici';" 2>&1

# ── 6. ConfBridge-Konferenzen ────────────────────────
info "Richte ConfBridge-Konferenzen ein..."
for i in $(seq 0 9); do
    docker exec vicidial-db mysql -u root -p"$DB_PASS" asterisk -e \
        "INSERT INTO vicidial_confbridges (confbridge_id, server_ip, confbridge_name, active)
         VALUES (960000$i, '$SERVER_IP', '', 0)
         ON DUPLICATE KEY UPDATE server_ip='$SERVER_IP';" 2>/dev/null
done
log "ConfBridge-Konferenzen (9600000-9600009)"

# ── 7. Conferencing Engine ───────────────────────────
docker exec vicidial-db mysql -u root -p"$DB_PASS" asterisk -e \
    "UPDATE servers SET confbridge_engine='CONFBRIDGE', AST_ver='confbridge';" 2>/dev/null
log "Conferencing Engine = CONFBRIDGE"

# ── 8. Keepalives für ConfBridge ─────────────────────
docker exec vicidial-db mysql -u root -p"$DB_PASS" asterisk -e \
    "UPDATE system_settings SET var_active_keepalives='12345689CE' WHERE var_active_keepalives IS NOT NULL;" 2>/dev/null || true
log "Keepalives konfiguriert"

# ── 9. Server-IP updaten ─────────────────────────────
if docker exec vicidial-apache test -f /usr/share/astguiclient/ADMIN_update_server_ip.pl 2>/dev/null; then
    info "Aktualisiere Server-IP in der DB..."
    docker exec vicidial-apache perl /usr/share/astguiclient/ADMIN_update_server_ip.pl \
        --old-server_ip=10.10.10.15 --server_ip="$SERVER_IP" --auto 2>&1 | tail -1
    log "Server-IP aktualisiert"
fi

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║     ViciDial Docker — Bereit!                ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  Admin:  http://$SERVER_IP/vicidial/admin.php"
echo "║  Agent:  http://$SERVER_IP/vicidial/agc/vicidial.php"
echo "║  Login:  6666 / 1234"
echo "║  Phone:  1001 / test"
echo "║  Conf:   ConfBridge (9600000–9600009)"
echo "╚══════════════════════════════════════════════╝"
echo ""
