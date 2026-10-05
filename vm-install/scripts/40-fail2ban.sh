#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "fail2ban": wiederholte Fehlversuche automatisch aussperren.
#
# Die Regeln stehen in files/etc/fail2ban/jail.d/dbg.local. Sie muessen NACH
# der Firewall eingerichtet werden, weil die Sperren ueber ufw gesetzt werden.
# ---------------------------------------------------------------------------

step "fail2ban einrichten"

apt_install fail2ban

# ignoreip: die eigene Maschine immer, dazu was in der Konfiguration steht.
FAIL2BAN_IGNOREIP_EFFECTIVE="127.0.0.1/8 ::1"
if [ -n "$FAIL2BAN_IGNOREIP" ]; then
	FAIL2BAN_IGNOREIP_EFFECTIVE="$FAIL2BAN_IGNOREIP_EFFECTIVE $FAIL2BAN_IGNOREIP"
fi
info "nie gesperrt: $FAIL2BAN_IGNOREIP_EFFECTIVE"

render etc/fail2ban/jail.d/dbg.local /etc/fail2ban/jail.d/dbg.local

# Die Apache-Regeln lesen /var/log/apache2/*error.log. Ist Apache noch nicht
# installiert, fehlt das Verzeichnis und fail2ban startet nicht. Also anlegen -
# Schritt "apache" folgt gleich.
mkdir -p /var/log/apache2
touch /var/log/apache2/error.log /var/log/apache2/access.log

# Mitgelieferte Beispielkonfiguration, die in manchen Abbildern unter
# jail.d/ liegt und eigene sshd-Regeln setzt: sie wuerde unsere Werte je nach
# Dateinamen ueberschreiben.
if [ -e /etc/fail2ban/jail.d/defaults-debian.conf ]; then
	info "/etc/fail2ban/jail.d/defaults-debian.conf wird vor dbg.local gelesen - unsere Werte gewinnen (d > de)"
fi

# Erst pruefen, dann starten: ein Tippfehler in der Konfiguration soll nicht
# dazu fuehren, dass fail2ban gar nicht laeuft.
if fail2ban-client --test >/dev/null 2>&1; then
	ok "Konfiguration geprueft (fail2ban-client --test)"
else
	fail2ban-client --test || true
	fail "Die fail2ban-Konfiguration ist fehlerhaft - es wird nicht neu gestartet."
fi

# /var/log/fail2ban.log haelt die VOLLSTAENDIGEN Adressen gesperrter Zugriffe
# fest. Die Datenschutzerklaerung der Site sagt fuer Protokolle mit
# vollstaendiger IP-Adresse 7 Tage zu; Ubuntu liefert die Regel mit
# "weekly rotate 4" aus, also bis zu fuenf Wochen.
logrotate_set_retention /etc/logrotate.d/fail2ban 7

service_enable fail2ban
service_restart fail2ban

sleep 2
if service_is_active fail2ban; then
	ok "fail2ban laeuft"
	fail2ban-client status 2>/dev/null | sed 's/^/    /' || true
else
	warn "fail2ban laeuft nicht - nachsehen mit: journalctl -u fail2ban -n 50"
fi
