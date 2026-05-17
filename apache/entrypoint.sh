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

# Falls astguiclient noch nicht installiert → SVN
if [ ! -f /usr/share/astguiclient/ADMIN_keepalive_ALL.pl ]; then
    echo "Installiere astguiclient aus SVN..."
    mkdir -p /usr/src/astguiclient
    cd /usr/src/astguiclient
    svn checkout --non-interactive --trust-server-cert-failures=unknown-ca,cn-mismatch \
        svn://svn.eflo.net/agc_2-X/trunk || echo "WARN: SVN-Checkout fehlgeschlagen"
    if [ -d /usr/src/astguiclient/trunk ]; then
        cd /usr/src/astguiclient/trunk
        perl install.pl --no-prompt --copy_sample_conf_files=Y || true
        perl install.pl --no-prompt || true
    fi
fi

export SERVER_IP DB_HOST DB_PORT

# ── Warten auf MariaDB ─────────────────────────────────
echo "Warte auf MariaDB ($DB_HOST:$DB_PORT)..."
for i in $(seq 1 60); do
    if perl -MDBI -e '
        eval {
            my $dbh = DBI->connect(
                "dbi:mysql:asterisk:$ENV{DB_HOST}:$ENV{DB_PORT}",
                "cron", "1234",
                { PrintError => 0, RaiseError => 1, mysql_connect_timeout => 3 }
            );
            $dbh->disconnect;
        };
        exit($@ ? 1 : 0);
    ' 2>/dev/null; then
        echo "MariaDB bereit (Versuch $i)"
        break
    fi
    sleep 3
done

# ── Server-IP in DB aktualisieren ──────────────────────
if [ "$SERVER_IP" != "127.0.0.1" ] && [ -f /usr/share/astguiclient/ADMIN_update_server_ip.pl ]; then
    echo "Aktualisiere Server-IP auf $SERVER_IP..."
    timeout 30 perl /usr/share/astguiclient/ADMIN_update_server_ip.pl \
        --old-server_ip=10.10.10.15 --server_ip="$SERVER_IP" --auto 2>&1 | tail -3 || true
fi

# ── ConfBridge + Engine + Keepalives (resilient) ───────
echo "Prüfe ConfBridge-Konferenzen..."
perl -MDBI -e '
    my $dbh = DBI->connect(
        "dbi:mysql:asterisk:$ENV{DB_HOST}:$ENV{DB_PORT}",
        "cron", "1234",
        { PrintError => 0, RaiseError => 1, mysql_connect_timeout => 5 }
    );

    # ConfBridge conferences (idempotent)
    eval {
        my ($count) = $dbh->selectrow_array("SELECT COUNT(*) FROM vicidial_confbridges");
        if ($count == 0) {
            print "Lege ConfBridge-Konferenzen an...\n";
            for my $i (0..9) {
                my $id = 9600000 + $i;
                $dbh->do(qq{INSERT INTO vicidial_confbridges (confbridge_id, server_ip, confbridge_name, active)
                            VALUES ($id, "$ENV{SERVER_IP}", "", 0)});
            }
            print "ConfBridge-Konferenzen angelegt\n";
        } else {
            print "ConfBridge-Konferenzen: $count\n";
        }
    };
    if ($@) { print "ConfBridge: $@"; }

    # Conferencing engine (may fail on old schema — ignore)
    eval {
        $dbh->do(qq{UPDATE servers SET confbridge_engine="CONFBRIDGE", AST_ver="confbridge",
                    asterisk_version="18.18.1-vici"});
        print "Engine auf CONFBRIDGE gesetzt\n";
    };
    if ($@) { print "Engine-Update übersprungen (Schema-Fehler): $@"; }

    # Keepalives
    eval {
        my ($keep) = $dbh->selectrow_array("SELECT var_active_keepalives FROM system_settings LIMIT 1");
        if ($keep && $keep ne "12345689CE") {
            $dbh->do(q{UPDATE system_settings SET var_active_keepalives="12345689CE"});
            print "Keepalives: 12345689CE\n";
        }
    };

    $dbh->disconnect;
    print "DB-Konfiguration abgeschlossen\n";
' 2>&1 || true

echo "=== Apache startet ==="

source /etc/apache2/envvars
exec apache2 -D FOREGROUND
