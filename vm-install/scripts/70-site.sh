#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "site": https-VirtualHost einschalten, Inhalt ablegen, Protokolle
# mit den richtigen Fristen versehen.
#
# Laeuft nach "tls", weil Apache mit einem SSLCertificateFile, das es nicht
# gibt, nicht startet.
# ---------------------------------------------------------------------------

step "Website einrichten"

# --- Wo liegt das Zertifikat? ----------------------------------------------

# Die hier gesetzten Werte liest placeholder_value() in scripts/lib.sh ein.
# shellcheck disable=SC2034
case "$TLS_MODE" in
	letsencrypt|staging)
		SSL_CERTIFICATE_FILE="/etc/letsencrypt/live/${SITE_NAME}/fullchain.pem"
		SSL_CERTIFICATE_KEY_FILE="/etc/letsencrypt/live/${SITE_NAME}/privkey.pem"
		# OCSP-Stapling verlangt eine Zertifikatskette, die der Browser
		# pruefen kann - bei einem selbst ausgestellten Zertifikat gaebe es
		# dafuer nur Warnungen im Fehlerprotokoll.
		SSL_STAPLING_DIRECTIVE="SSLUseStapling on"
		;;
	selfsigned)
		SSL_CERTIFICATE_FILE="/etc/ssl/dbg/fullchain.pem"
		SSL_CERTIFICATE_KEY_FILE="/etc/ssl/dbg/privkey.pem"
		SSL_STAPLING_DIRECTIVE="# SSLUseStapling - bei selbst ausgestelltem Zertifikat ohne Nutzen"
		;;
esac

for f in "$SSL_CERTIFICATE_FILE" "$SSL_CERTIFICATE_KEY_FILE"; do
	[ -s "$f" ] || fail "$f fehlt. Erst den Schritt 'tls' laufen lassen: sudo ./install.sh --only tls"
done
ok "Zertifikat: $SSL_CERTIFICATE_FILE"

# Zweites Zertifikat fuer die Weiterleitungsdomains (REDIRECT_DOMAINS).
# shellcheck disable=SC2034
if [ -n "$REDIRECT_DOMAINS" ]; then
	case "$TLS_MODE" in
		letsencrypt|staging)
			REDIRECT_CERTIFICATE_FILE="/etc/letsencrypt/live/${REDIRECT_NAME}/fullchain.pem"
			REDIRECT_CERTIFICATE_KEY_FILE="/etc/letsencrypt/live/${REDIRECT_NAME}/privkey.pem"
			;;
		selfsigned)
			REDIRECT_CERTIFICATE_FILE="/etc/ssl/dbg-redirect/fullchain.pem"
			REDIRECT_CERTIFICATE_KEY_FILE="/etc/ssl/dbg-redirect/privkey.pem"
			;;
	esac
	for f in "$REDIRECT_CERTIFICATE_FILE" "$REDIRECT_CERTIFICATE_KEY_FILE"; do
		[ -s "$f" ] || fail "$f fehlt. Erst den Schritt 'tls' laufen lassen: sudo ./install.sh --only tls"
	done
	ok "Zertifikat der Weiterleitung: $REDIRECT_CERTIFICATE_FILE"
fi

# HSTS steht schon in install.sh fest (es haengt allein an TLS_MODE und
# HSTS_MAX_AGE) und ist damit bereits in dbg-hardening.conf eingetragen - hier
# nur noch die Ausgabe, damit man sieht, was gilt.
case "$HSTS_HEADER_DIRECTIVE" in
	Header*) ok "HSTS: ${HSTS_HEADER_DIRECTIVE#*Strict-Transport-Security }" ;;
	*)       info "HSTS bleibt aus, solange kein gueltiges Zertifikat von Let's Encrypt vorliegt" ;;
esac


# --- DocumentRoot ----------------------------------------------------------

mkdir -p "$DOC_ROOT"

# Eigentuemer root, Gruppe www-data, fuer www-data nur lesbar: der Webserver
# kann damit ausliefern, aber nichts veraendern. Ein Fehler im Webserver kann
# dann keine Dateien der Site ueberschreiben.
chown -R root:www-data "$DOC_ROOT"
find "$DOC_ROOT" -type d -exec chmod 0755 {} +
find "$DOC_ROOT" -type f -exec chmod 0644 {} + 2>/dev/null || true
ok "DocumentRoot: $DOC_ROOT (root:www-data, fuer den Webserver nur lesbar)"

# Platzhalterseite, solange noch kein Inhalt ausgerollt ist. Wird beim ersten
# deploy-site.sh von der echten index.html ersetzt.
if [ ! -e "$DOC_ROOT/index.html" ]; then
	cat > "$DOC_ROOT/index.html" <<-'PLATZ'
		<!doctype html>
		<html lang="de">
		<head><meta charset="utf-8"><title>Noch kein Inhalt</title></head>
		<body>
		<h1>Die Website ist noch nicht ausgerollt.</h1>
		<p>Der Server laeuft. Der Inhalt kommt mit
		<code>vm-install/deploy-site.sh</code> hierher.</p>
		</body>
		</html>
	PLATZ
	chown root:www-data "$DOC_ROOT/index.html"
	chmod 0644 "$DOC_ROOT/index.html"
	info "Platzhalterseite angelegt (noch kein Inhalt vorhanden)"
fi


# --- Protokollfristen ------------------------------------------------------

copy_file etc/logrotate.d/dbg /etc/logrotate.d/dbg

# Die mitgelieferte Regel fuer /var/log/apache2/*.log steht auf "daily" und
# "rotate 14" - und erfasst damit auch das Fehlerprotokoll, in dem ebenfalls
# vollstaendige IP-Adressen stehen. Die Datenschutzerklaerung nennt 7 Tage.
logrotate_set_retention /etc/logrotate.d/apache2 7

if logrotate -d /etc/logrotate.d/dbg >/dev/null 2>&1; then
	ok "logrotate-Regeln geprueft"
else
	warn "logrotate meldet ein Problem - pruefen mit: logrotate -d /etc/logrotate.d/dbg"
fi


# --- Vorschau (Zweig "staging") --------------------------------------------
#
# Eigenes Verzeichnis NEBEN dem DocumentRoot, per Alias eingehaengt. Laege es
# darunter, wuerde die naechste Auslieferung der oeffentlichen Site es
# abraeumen - beide gleichen mit "rsync --delete" ab.

if [ "${ENABLE_STAGING:-no}" = yes ]; then
	mkdir -p "$STAGING_DOC_ROOT"
	chown -R root:www-data "$STAGING_DOC_ROOT"
	find "$STAGING_DOC_ROOT" -type d -exec chmod 0755 {} +
	find "$STAGING_DOC_ROOT" -type f -exec chmod 0644 {} + 2>/dev/null || true

	if [ ! -e "$STAGING_DOC_ROOT/index.html" ]; then
		cat > "$STAGING_DOC_ROOT/index.html" <<-PLATZ
			<!doctype html>
			<html lang="de">
			<head><meta charset="utf-8"><title>Vorschau - noch kein Inhalt</title></head>
			<body>
			<h1>Vorschau</h1>
			<p>Hier erscheint der Stand des Zweigs <code>staging</code>, sobald dort
			etwas eingecheckt wird. Dies ist NICHT die oeffentliche Site.</p>
			</body>
			</html>
		PLATZ
		chown root:www-data "$STAGING_DOC_ROOT/index.html"
		chmod 0644 "$STAGING_DOC_ROOT/index.html"
	fi

	render etc/apache2/conf-available/dbg-staging.conf /etc/apache2/conf-available/dbg-staging.conf
	a2enconf -q dbg-staging
	ok "Vorschau unter ${STAGING_URL_PATH}/ -> $STAGING_DOC_ROOT"

	# Anmeldung nur, wenn Benutzer eingetragen sind.
	if [ -n "${STAGING_BASIC_AUTH_USERS:-}" ]; then
		apt_install apache2-utils

		htpasswd_file=/etc/apache2/dbg-staging.htpasswd
		tmp_htpasswd="$(mktemp)"

		while IFS=: read -r auth_user auth_password; do
			[ -n "$auth_user" ] && [ -n "$auth_password" ] || continue
			htpasswd -b "$tmp_htpasswd" "$auth_user" "$auth_password" >/dev/null 2>&1
		done <<-EOF
			${STAGING_BASIC_AUTH_USERS}
		EOF

		if [ -s "$tmp_htpasswd" ]; then
			install_file "$tmp_htpasswd" "$htpasswd_file" 0640
			chown root:www-data "$htpasswd_file"
			render etc/apache2/conf-available/dbg-staging-auth.conf /etc/apache2/conf-available/dbg-staging-auth.conf
			a2enmod -q auth_basic authn_file authz_user 2>/dev/null || true
			a2enconf -q dbg-staging-auth
			ok "Vorschau ist mit Anmeldung geschuetzt ($(wc -l < "$htpasswd_file") Benutzer)"
		else
			warn "STAGING_BASIC_AUTH_USERS ist gesetzt, enthaelt aber kein brauchbares benutzer:passwort-Paar."
		fi
		rm -f "$tmp_htpasswd"
	else
		a2disconf -q dbg-staging-auth 2>/dev/null || true
		info "Vorschau ist offen erreichbar (STAGING_BASIC_AUTH_USERS ist leer)"
		info "    Suchmaschinen halten sich der Kopf X-Robots-Tag: noindex fern;"
		info "    der Pfad steht bewusst in keiner robots.txt."
	fi
else
	a2disconf -q dbg-staging 2>/dev/null || true
	a2disconf -q dbg-staging-auth 2>/dev/null || true
	info "Vorschau nicht eingeschaltet (ENABLE_STAGING=${ENABLE_STAGING:-})"
fi


# --- https-VirtualHost ----------------------------------------------------

render etc/apache2/sites-available/dbg-ssl.conf /etc/apache2/sites-available/dbg-ssl.conf
a2ensite -q dbg-ssl
ok "dbg-ssl eingeschaltet (Port 443)"

# Weiterleitungsdomains: eigener https-vHost mit eigenem Zertifikat.
# Der Dateiname steht alphabetisch NACH dbg-ssl.conf ("w" > "s") - so bleibt dbg-ssl der erste vHost
# fuer *:443 und damit der, den Apache fuer unbekannte Namen nimmt.
if [ -n "$REDIRECT_DOMAINS" ]; then
	render etc/apache2/sites-available/dbg-weiterleitung.conf /etc/apache2/sites-available/dbg-weiterleitung.conf
	a2ensite -q dbg-weiterleitung
	ok "dbg-weiterleitung eingeschaltet: $REDIRECT_DOMAINS -> https://$SITE_NAME/"
else
	a2dissite -q dbg-weiterleitung 2>/dev/null || true
	info "Keine Weiterleitungsdomains (REDIRECT_DOMAINS ist leer)"
fi

if ! apache_configtest; then
	fail "Die Apache-Konfiguration ist fehlerhaft - es wird nicht neu gestartet."
fi
ok "Konfiguration geprueft (apache2ctl configtest)"

service_restart apache2

sleep 1
service_is_active apache2 || warn "Apache laeuft nicht - nachsehen mit: journalctl -u apache2 -n 50"

# Nur ein Name darf fuer *:443 zustaendig sein. Bleibt eine Sicherungskopie in
# sites-enabled/ liegen, waehlt Apache unter Umstaenden die falsche Datei aus -
# genau dieser Fehler ist in den dev-vm-Projekten schon einmal aufgetreten.
# In der Uebersicht von apache2ctl -S steht je Zeile "*:443  name (datei:zeile)".
# Mehr als eine Zeile fuer *:443 mit unserem Namen heisst: zwei Dateien streiten
# sich um denselben vHost.
dup="$(apache2ctl -S 2>/dev/null | grep -c "^\*:443.*${SITE_NAME}" || true)"
if [ "${dup:-0}" -gt 1 ]; then
	warn "Fuer *:443 und ${SITE_NAME} gibt es $dup Eintraege - eine davon gewinnt, womoeglich die falsche."
	warn "Nachsehen mit: apache2ctl -S   und in /etc/apache2/sites-enabled/ aufraeumen."
fi
