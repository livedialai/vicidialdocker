FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# PHP 7.4 via sury.org (ViciDial braucht zwingend PHP 7.4)
RUN apt-get update && apt-get install -y --no-install-recommends \
    lsb-release ca-certificates apt-transport-https gnupg2 curl wget \
    && curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" \
        > /etc/apt/sources.list.d/php.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        apache2 libapache2-mod-php7.4 \
        php7.4 php7.4-cli php7.4-gd php7.4-curl php7.4-mysql php7.4-ldap \
        php7.4-zip php7.4-mbstring php7.4-xml php7.4-xmlrpc php7.4-imap \
        php7.4-opcache php7.4-bcmath php7.4-intl php7.4-readline \
        subversion perl libdbi-perl libdbd-mysql-perl libnet-telnet-perl \
        libwww-perl libgd-perl libyaml-perl libterm-readline-gnu-perl \
        procps net-tools \
    && rm -rf /var/lib/apt/lists/*

# PHP-Einstellungen für ViciDial
RUN PHP_INI_CLI=/etc/php/7.4/cli/php.ini \
    PHP_INI_APACHE=/etc/php/7.4/apache2/php.ini \
    && for ini in $PHP_INI_CLI $PHP_INI_APACHE; do \
        sed -i 's/^error_reporting.*/error_reporting = E_ALL \& ~E_NOTICE/' $ini; \
        sed -i 's/^memory_limit.*/memory_limit = 448M/' $ini; \
        sed -i 's/^short_open_tag.*/short_open_tag = On/' $ini; \
        sed -i 's/^max_execution_time.*/max_execution_time = 3330/' $ini; \
        sed -i 's/^max_input_time.*/max_input_time = 3360/' $ini; \
        sed -i 's/^post_max_size.*/post_max_size = 448M/' $ini; \
        sed -i 's/^upload_max_filesize.*/upload_max_filesize = 442M/' $ini; \
        sed -i 's/^default_socket_timeout.*/default_socket_timeout = 3360/' $ini; \
        sed -i 's|^;date.timezone.*|date.timezone = America/New_York|' $ini; \
        grep -q 'max_input_vars' $ini || echo "max_input_vars = 50000" >> $ini; \
    done

# Apache: MPM prefork (zwingend für mod_php7.4)
RUN a2dismod mpm_event 2>/dev/null || true \
    && a2enmod mpm_prefork php7.4 rewrite ssl \
    && echo "ServerName localhost" >> /etc/apache2/apache2.conf

# ViciDial-Webverzeichnis
RUN mkdir -p /var/www/html /var/spool/asterisk/monitor /var/spool/asterisk/monitorDONE/MP3 \
    && chown -R www-data:www-data /var/spool/asterisk

# Recording-Alias
RUN cat >> /etc/apache2/apache2.conf <<'EOF'
Alias /RECORDINGS/MP3 "/var/spool/asterisk/monitorDONE/MP3/"
<Directory "/var/spool/asterisk/monitorDONE/MP3/">
    Options Indexes MultiViews
    AllowOverride None
    Require all granted
</Directory>
EOF

# Welcome-Seite → ViciDial
RUN echo '<META HTTP-EQUIV=REFRESH CONTENT="1; URL=/vicidial/welcome.php">Bitte warten...' \
    > /var/www/html/index.html

# astguiclient.conf (wird bei Start per ENV überschrieben)
COPY astguiclient.conf.tmpl /etc/astguiclient.conf.tmpl

# Entrypoint: astguiclient installieren + konfigurieren
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME /var/spool/asterisk
EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
