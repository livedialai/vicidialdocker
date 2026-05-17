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

# Apache starten
source /etc/apache2/envvars
exec apache2 -D FOREGROUND
