#!/bin/bash
set -e

SERVER_IP="${SERVER_IP:-127.0.0.1}"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"

echo "=== ViciDial Apache-PHP Container ==="
echo "Server-IP: $SERVER_IP"
echo "DB: $DB_HOST:$DB_PORT"

# astguiclient.conf schreiben
sed -e "s/__SERVER_IP__/$SERVER_IP/g" \
    -e "s/__DB_HOST__/$DB_HOST/g" \
    -e "s/__DB_PORT__/$DB_PORT/g" \
    /etc/astguiclient.conf.tmpl > /etc/astguiclient.conf

# Falls astguiclient noch nicht installiert → aus SVN holen und installieren
if [ ! -f /usr/share/astguiclient/ADMIN_keepalive_ALL.pl ]; then
    echo "Installiere astguiclient aus SVN..."
    mkdir -p /usr/src/astguiclient
    cd /usr/src/astguiclient
    svn checkout --non-interactive --trust-server-cert-failures=unknown-ca,cn-mismatch \
        svn://svn.eflo.net/agc_2-X/trunk || {
        echo "WARN: SVN-Checkout fehlgeschlagen, überspringe ViciDial-Installation"
    }
    if [ -d /usr/src/astguiclient/trunk ]; then
        cd /usr/src/astguiclient/trunk
        perl install.pl --no-prompt --copy_sample_conf_files=Y || true
        perl install.pl --no-prompt || true
    fi
fi

# ── Warten auf MariaDB ─────────────────────────────────
echo "Warte auf MariaDB ($DB_HOST:$DB_PORT)..."
for i in $(seq 1 60); do
    if perl -MDBI -e "DBI->connect(dbi:mysql:asterisk::,cron,1234)" 2>/dev/null; then
        echo "MariaDB bereit"
        break
    fi
    sleep 2
done

# ── Server-IP in DB aktualisieren ──────────────────────
if [ "$SERVER_IP" != "127.0.0.1" ] && [ -f /usr/share/astguiclient/ADMIN_update_server_ip.pl ]; then
    echo "Aktualisiere Server-IP auf $SERVER_IP..."
    perl /usr/share/astguiclient/ADMIN_update_server_ip.pl \
        --old-server_ip=10.10.10.15 --server_ip="$SERVER_IP" --auto 2>&1 | tail -1
fi

# ── ConfBridge-Konferenzen (idempotent) ────────────────
echo "Prüfe ConfBridge-Konferenzen..."
CONF_COUNT=$(mysql -h "$DB_HOST" -u cron -p1234 asterisk -sN \
    -e "SELECT COUNT(*) FROM vicidial_confbridges" 2>/dev/null || echo "0")
if [ "$CONF_COUNT" = "0" ]; then
    echo "Lege ConfBridge-Konferenzen an (9600000–9600009)..."
    for i in $(seq 0 9); do
        mysql -h "$DB_HOST" -u cron -p1234 asterisk -sN -e \
            "INSERT INTO vicidial_confbridges (confbridge_id, server_ip, confbridge_name, active)
             VALUES (960000$i, , , 0)" 2>/dev/null
    done
    echo "ConfBridge-Konferenzen angelegt"
else
    echo "ConfBridge-Konferenzen vorhanden ($CONF_COUNT)"
fi

# ── ConfBridge Engine Flag ─────────────────────────────
mysql -h "$DB_HOST" -u cron -p1234 asterisk -sN -e \
    "UPDATE servers SET confbridge_engine=CONFBRIDGE, AST_ver=confbridge, asterisk_version=18.18.1-vici" 2>/dev/null || true

# ── Keepalives (nur setzen wenn nicht schon gesetzt) ───
KEEP=$(mysql -h "$DB_HOST" -u cron -p1234 asterisk -sN \
    -e "SELECT var_active_keepalives FROM system_settings LIMIT 1" 2>/dev/null || echo "")
if [ -n "$KEEP" ] && [ "$KEEP" != "12345689CE" ]; then
    mysql -h "$DB_HOST" -u cron -p1234 asterisk -sN -e \
        "UPDATE system_settings SET var_active_keepalives=12345689CE" 2>/dev/null || true
    echo "Keepalives auf 12345689CE gesetzt"
fi

echo "=== Konfiguration abgeschlossen, starte Apache ==="

# Apache starten
source /etc/apache2/envvars
exec apache2 -D FOREGROUND
