# ViciDial Docker — Asterisk 18 + ConfBridge

**Fertiges ViciDial-Docker-Setup mit ConfBridge.** Ein Befehl, alles fertig:

```bash
export SERVER_IP=DEINE_SERVER_IP
docker compose up -d
```

Kein Kompilieren, kein SVN-Checkout, kein manuelles Patchen, kein install.sh.  
Das DB-Schema ist im Image gebacken, ConfBridge wird automatisch beim ersten Start konfiguriert.

## 🚀 Quickstart

```bash
# 1. Repo klonen
git clone https://github.com/livedialai/vicidialdocker
cd vicidialdocker

# 2. IP setzen und starten
export SERVER_IP=DEINE_SERVER_IP
docker compose up -d

# 3. Warten (30-60 Sekunden beim ersten Start — Apache richtet DB + ConfBridge ein)
docker compose logs -f apache

# 4. Fertig
# Admin:  http://DEINE_IP:3300/vicidial/admin.php  (6666 / 1234)
# Agent:  http://DEINE_IP:3300/vicidial/agc/vicidial.php
```

## 📦 Docker Hub Images

| Service  | Image                            |
|----------|----------------------------------|
| MariaDB  | `livedial/vicidial-db:latest`    |
| Asterisk | `livedial/vicidial-asterisk:latest` |
| Apache   | `livedial/vicidial-apache:latest` |

**DB-Schema ist im MariaDB-Image gebacken** — kein manueller SQL-Import nötig.  
**ConfBridge + Server-IP** werden vom Apache-Entrypoint automatisch eingerichtet.

## 🏗 Was passiert beim ersten `docker compose up -d`?

1. **MariaDB startet** → führt automatisch die Init-SQLs aus (DB `asterisk`, User `cron`/`custom`, 344 Tabellen, Default-Konfiguration)
2. **Asterisk startet** → PJSIP + ConfBridge bereit
3. **Apache startet** → Entrypoint:
   - Wartet auf MariaDB
   - Führt `ADMIN_update_server_ip.pl` aus (setzt deine `$SERVER_IP`)
   - Legt ConfBridge-Konferenzen an (9600000–9600009)
   - Setzt ConfBridge-Engine-Flag
   - Konfiguriert Keepalives

## 🏗 Architektur

```
docker compose up -d
├── vicidial-db        (MariaDB 10.11, Port 3306)
├── vicidial-asterisk  (Asterisk 18.18.1 + ViciDial-Patches, PJSIP, ConfBridge)
└── vicidial-apache    (Apache + PHP 7.4 + astguiclient, Port 3300)
```

- **Asterisk 18.18.1** mit ViciDial-Patches
- **ConfBridge** — keine Kernel-Module nötig
- **PJSIP** als SIP-Stack
- **Manager-API** auf Port 5038

## ⚙️ Konfiguration

### Environment

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

### Persistente Volumes

| Volume             | Inhalt                    |
|--------------------|---------------------------|
| `db-data`          | MariaDB-Daten (Schema + Konfiguration) |
| `asterisk-sounds`  | Asterisk-Sounds           |
| `asterisk-monitor` | Aufnahmen                 |
| `asterisk-config`  | Asterisk-Konfiguration    |

**Daten sind persistent** — `docker compose down && docker compose up -d` behält alles.

## 📝 Default Logins

| Rolle  | User | Passwort |
|--------|------|----------|
| Admin  | 6666 | 1234     |
| Phone  | 1001 | test     |

## 🔧 Manuelle Installation (nur bei eigenen Images ohne gebakene DB)

Falls du die Images selbst baust und das Schema nicht im Image ist, gibt es `install.sh`:

```bash
export SERVER_IP=DEINE_IP
bash install.sh
```

## 🖥️ Screens (Keepalives)

```bash
docker exec -it vicidial-apache bash
# Dann die ViciDial-Perl-Screens starten
```

## 🐛 Troubleshooting

```bash
docker compose logs -f                    # Alle Logs
docker exec vicidial-asterisk asterisk -rx "pjsip show endpoints"
docker exec vicidial-db mysql -u root -pvicidial asterisk -e "SELECT COUNT(*) FROM phones"
```

## 📂 Build (nur bei eigenen Änderungen)

```bash
docker build -t livedial/vicidial-db:latest ./mariadb
docker build -t livedial/vicidial-asterisk:latest ./asterisk
docker build -t livedial/vicidial-apache:latest ./apache
docker push livedial/vicidial-db:latest
docker push livedial/vicidial-asterisk:latest
docker push livedial/vicidial-apache:latest
```
