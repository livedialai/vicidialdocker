FROM mariadb:10.11

ENV MARIADB_ROOT_PASSWORD=vicidial

# ViciDial DB-Init kopieren
COPY init/ /docker-entrypoint-initdb.d/

# MariaDB-Optimierungen für ViciDial
COPY my.cnf /etc/mysql/conf.d/60-vicidial.cnf
