#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "apache": Webserver installieren und die Grundkonfiguration ablegen.
#
# Am Ende dieses Schritts laeuft Apache mit dem http-VirtualHost. Der liefert
# das Nachweisverzeichnis fuer Let's Encrypt aus und leitet alles andere auf
# https um. Der https-VirtualHost kommt erst in Schritt "site" dazu - vorher
# gibt es noch kein Zertifikat, und Apache startet ohne Zertifikatsdateien
# nicht.
# ---------------------------------------------------------------------------

step "Apache installieren und grundkonfigurieren"

apt_install apache2 apache2-utils

# --- Module ----------------------------------------------------------------
#
# Bewusst knapp: alles, was die Site nicht braucht, bleibt aus. Kein PHP, kein
# CGI, kein proxy, kein mod_jk - die Site ist statisch.

for mod in ssl headers rewrite expires deflate mime setenvif reqtimeout http2; do
	if a2query -m "$mod" >/dev/null 2>&1; then
		info "Modul bereits aktiv: $mod"
	else
		a2enmod -q "$mod"
		ok "Modul eingeschaltet: $mod"
	fi
done

# brotli komprimiert besser als gzip und ist seit Ubuntu 22.04 dabei. Falls
# nicht vorhanden, bleibt es bei deflate - die Konfiguration ist in beiden
# Faellen gueltig (<IfModule mod_brotli.c>).
if apt_available libapache2-mod-brotli; then
	apt_install libapache2-mod-brotli
	a2enmod -q brotli 2>/dev/null && ok "Modul eingeschaltet: brotli" || info "Modul bereits aktiv: brotli"
else
	info "libapache2-mod-brotli ist nicht verfuegbar - es bleibt bei deflate"
fi

# http/2 braucht mpm_event; mpm_prefork waere nur fuer PHP als Modul noetig.
if a2query -M 2>/dev/null | grep -q event; then
	info "MPM: event (richtig fuer http/2)"
else
	info "wechsle auf mpm_event"
	a2dismod -q -f mpm_prefork mpm_worker 2>/dev/null || true
	a2enmod -q mpm_event
	ok "mpm_event eingeschaltet"
fi

# Module, die hier nur Angriffsfläche waeren.
for mod in status autoindex cgi userdir; do
	if a2query -m "$mod" >/dev/null 2>&1; then
		a2dismod -q -f "$mod" 2>/dev/null && ok "Modul abgeschaltet: $mod" || true
	fi
done


# --- Nachweisverzeichnis fuer Let's Encrypt --------------------------------

mkdir -p "$ACME_WEBROOT/.well-known/acme-challenge"
chown -R root:www-data "$ACME_WEBROOT"
chmod -R 0755 "$ACME_WEBROOT"
ok "Nachweisverzeichnis: $ACME_WEBROOT"


# --- Konfiguration ablegen -------------------------------------------------

render etc/apache2/conf-available/dbg-hardening.conf  /etc/apache2/conf-available/dbg-hardening.conf
copy_file etc/apache2/conf-available/dbg-ssl-params.conf /etc/apache2/conf-available/dbg-ssl-params.conf
# render, nicht copy_file: die Datei enthaelt <staging_url_path>.
render etc/apache2/conf-available/dbg-logging.conf /etc/apache2/conf-available/dbg-logging.conf

a2enconf -q dbg-hardening dbg-ssl-params dbg-logging
ok "dbg-hardening, dbg-ssl-params, dbg-logging eingeschaltet"

if [ "$ENABLE_CSP" = yes ]; then
	render etc/apache2/conf-available/dbg-csp.conf /etc/apache2/conf-available/dbg-csp.conf
	a2enconf -q dbg-csp
	ok "Content Security Policy eingeschaltet"
else
	a2disconf -q dbg-csp 2>/dev/null || true
	info "Content Security Policy nicht eingeschaltet (ENABLE_CSP=$ENABLE_CSP)"
fi

# Verzeichnis fuer das gekuerzte Zugriffsprotokoll. Eigenes Verzeichnis, damit
# die logrotate-Regel von Ubuntu fuer /var/log/apache2/*.log es nicht erfasst.
if [ -d /var/log/apache2-stats ]; then
	info "/var/log/apache2-stats ist vorhanden"
else
	mkdir -p /var/log/apache2-stats
	ok "/var/log/apache2-stats angelegt"
fi
chown root:adm /var/log/apache2-stats
chmod 0750 /var/log/apache2-stats


# --- VirtualHosts ----------------------------------------------------------

# Die mitgelieferte Platzhalterseite und ihr VirtualHost kommen weg: sonst
# beantwortet sie alle Anfragen, die keinen passenden ServerName treffen.
a2dissite -q 000-default 2>/dev/null && ok "000-default abgeschaltet" || true
a2dissite -q default-ssl 2>/dev/null || true
rm -f /var/www/html/index.html

render etc/apache2/sites-available/dbg-http.conf /etc/apache2/sites-available/dbg-http.conf
a2ensite -q dbg-http
ok "dbg-http eingeschaltet (Port 80)"


# --- Pruefen und starten ---------------------------------------------------

if ! apache_configtest; then
	fail "Die Apache-Konfiguration ist fehlerhaft - es wird nicht neu gestartet."
fi
ok "Konfiguration geprueft (apache2ctl configtest)"

service_enable apache2
service_restart apache2

sleep 1
if service_is_active apache2; then
	ok "Apache laeuft"
else
	warn "Apache laeuft nicht - nachsehen mit: journalctl -u apache2 -n 50"
fi
