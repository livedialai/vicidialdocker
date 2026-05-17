# ViciDial ConfBridge Patches — Manuelle Anpassungen nach Installation
# Diese Patches müssen nach dem SVN-Checkout angewendet werden

## 1. non_agent_api.php — Monitoring-Fix (Line ~3295)
# vicidial_conferences → vicidial_confbridges
# sed -i 's/vicidial_conferences/vicidial_confbridges/g' /var/www/html/vicidial/non_agent_api.php

## 2. extensions.conf Bugfix: 08600X → 09600X
# (Bereits in extensions-vicidial.conf enthalten)

## 3. Crontab: AST_conf_update.pl → AST_conf_update_screen.pl
# Alten Cron-Eintrag auskommentieren:
# sed -i 's|^\* \* \* \* \* /usr/share/astguiclient/AST_conf_update.pl|### &|' /root/crontab-file
# Screen-Session in Keepalives: VARactive_keepalives muss 'C' enthalten

## 4. Admin → Servers → Conferencing Engine = CONFBRIDGE
# (Per DB: UPDATE servers SET confbridge_engine='CONFBRIDGE';)

## 5. manager.conf: [confcron]-Block hinzufügen
# (Bereits in Dockerfile enthalten)
