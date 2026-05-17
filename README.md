# ViciDial Docker — Asterisk 18 + ConfBridge

**Fertiges ViciDial-Docker-Setup mit ConfBridge.** Ein `docker compose up -d` und du bist online — kein Kompilieren, kein SVN-Checkout, kein manuelles Patchen.

## 🚀 Quickstart

```bash
# 1. Repo klonen
git clone https://github.com/livedialai/vicidialdocker
cd vicidialdocker

# 2. IP setzen und starten
export SERVER_IP=DEINE_SERVER_IP
docker compose up -d

# 3. Install-Script ausführen (DB-Schema, ConfBridge, Konfiguration)
bash install.sh

# 4. Fertig
# Admin:  http://DEINE_IP/vicidial/admin.php  (6666 / 1234)
# Agent:  http://DEINE_IP/vicidial/agc/vicidial.php
```

## 📦 Docker Hub Images

Alle Images werden von Docker Hub gepullt — **kein lokales Bauen nötig**:

| Service  | Image                            |
|----------|----------------------------------|
| MariaDB  | `livedial/vicidial-db:latest`    |
| Asterisk | `livedial/vicidial-asterisk:latest` |
| Apache   | `livedial/vicidial-apache:latest` |

## 🏗 Architektur

```
docker compose up -d
├── vicidial-db        (MariaDB 10.x, Port 3306)
├── vicidial-asterisk  (Asterisk 18.18.1 + ViciDial-Patches, PJSIP, ConfBridge)
└── vicidial-apache    (Apache + PHP 7.4 + astguiclient, Port 80)
```

- **Asterisk 18.18.1** mit offiziellen ViciDial-Patches (amd_stats, sip_peer_status, iax_peer_status, timeout_reset)
- **ConfBridge** statt MeetMe/Dahdi — keine Kernel-Module nötig
- **PJSIP** als SIP-Stack (`chan_pjsip`)
- **Manager-API** auf Port 5038 für ViciDial-Screens

## ⚙️ Konfiguration

### Environment-Variablen

| Variable    | Default      | Beschreibung           |
|-------------|-------------|------------------------|
| `SERVER_IP` | `127.0.0.1` | Öffentliche Server-IP  |

### Ports

| Port         | Proto | Dienst        |
|-------------|-------|---------------|
| 80          | TCP   | Web-GUI       |
| 5060        | UDP   | SIP-Signaling |
| 10000-10100 | UDP   | RTP-Audio     |
| 5038        | TCP   | AMI (Manager) |

### Volumes

| Volume             | Inhalt                    |
|--------------------|---------------------------|
| `db-data`          | MariaDB-Daten             |
| `asterisk-sounds`  | Asterisk-Sounds           |
| `asterisk-monitor` | Aufnahmen (`/var/spool/asterisk/monitor`) |
| `asterisk-config`  | Asterisk-Konfiguration    |

## 🔧 install.sh

Das Install-Script führt folgende Schritte aus:

1. Warten auf MariaDB-Bereitschaft
2. SVN-Checkout von astguiclient (falls nicht im Image)
3. Datenbank-Schema einspielen (`MySQL_AST_CREATE_tables.sql`)
4. Default-Konfiguration (`first_server_install.sql`)
5. ConfBridge-Konferenzen anlegen (9600000–9600009)
6. Server-IP in der DB updaten

## 📝 Default Logins

| Rolle  | User | Passwort |
|--------|------|----------|
| Admin  | 6666 | 1234     |
| Phone  | 1001 | test     |

## 🖥️ Screens (Keepalives)

ViciDial braucht laufende Perl-Screens. Diese werden im Apache-Container gestartet:

```bash
# In den Apache-Container gehen
docker exec -it vicidial-apache bash

# Screen-Session starten (alle Keepalives)
screen -dmS astshell
# Dann die benötigten Scripts:
# AST_update.pl, AST_send_action_child.pl, AST_VDauto_dial.pl, etc.
```

Aktive Keepalives in DB setzen:
```sql
UPDATE system_settings SET var_active_keepalives=12345689CE;
```

## 🐛 Troubleshooting

### Container starten nicht?
```bash
docker compose logs -f
```

### SIP-Registrierung schlägt fehl?
```bash
docker exec vicidial-asterisk asterisk -rx "pjsip show endpoints"
docker exec vicidial-asterisk asterisk -rx "pjsip show registrations"
```

### Datenbank nicht erreichbar?
```bash
docker exec vicidial-db mysqladmin ping -h localhost
docker exec vicidial-apache perl -e 'use DBI; DBI->connect("dbi:mysql:asterisk:mariadb:3306","cron","1234") or die $DBI::errstr; print "OK\n"'
```

## 📂 Build (nur bei eigenen Änderungen nötig)

```bash
# Alle Images neu bauen
docker compose build

# Einzeln
docker compose build asterisk
docker compose build mariadb
docker compose build apache
```

Zum Pushen nach Docker Hub:
```bash
docker tag vicidial-docker-asterisk livedial/vicidial-asterisk:latest
docker push livedial/vicidial-asterisk:latest
```

## 📄 Lizenz

MIT — siehe Dockerfiles und ViciDial-Lizenz für astguiclient.
