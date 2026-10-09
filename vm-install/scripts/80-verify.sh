#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "verify": nachsehen, ob tatsaechlich alles laeuft.
#
# Aendert nichts. Dieser Schritt laesst sich jederzeit einzeln aufrufen:
#     sudo ./install.sh --only verify
# ---------------------------------------------------------------------------

step "Abschlusspruefung"

CHECKS_FAILED=0

check() {
	local label="$1"; shift
	if "$@" >/dev/null 2>&1; then
		ok "$label"
	else
		warn "$label  -- FEHLGESCHLAGEN: $*"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
	fi
}

# --- Dienste ---------------------------------------------------------------

info "Dienste:"
for svc in ssh apache2 fail2ban; do
	if systemctl is-active --quiet "$svc" || systemctl is-active --quiet "${svc}.socket"; then
		ok "  $svc laeuft"
	else
		warn "  $svc laeuft nicht"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
	fi
done

# Bei ufw sagt die systemd-Unit nichts darueber aus, ob tatsaechlich gefiltert
# wird - ufw fuehrt darueber selbst Buch.
if ufw status 2>/dev/null | grep -q '^Status: active'; then
	ok "  ufw filtert"
else
	warn "  ufw filtert NICHT - die Maschine ist ungefiltert erreichbar"
	CHECKS_FAILED=$((CHECKS_FAILED + 1))
fi

# --- Offene Ports ----------------------------------------------------------

info ""
info "Von aussen erreichbare Ports (sollten genau $SSH_PORT, 80 und 443 sein):"
ss -H -tlnp 2>/dev/null \
	| awk '{print $4}' \
	| grep -vE '^(127\.0\.0\.1|\[::1\])' \
	| sed 's/.*[:.]\([0-9]\+\)$/\1/' \
	| sort -un \
	| while read -r port; do
		case "$port" in
			"$SSH_PORT"|80|443) printf '    %s (erwartet)\n' "$port" ;;
			*)                  printf '    %s  <-- nicht erwartet, pruefen mit: ss -tlnp | grep ":%s"\n' "$port" "$port" ;;
		esac
	done

info ""
info "Firewall:"
ufw status verbose 2>/dev/null | sed 's/^/    /' || true

# --- fail2ban --------------------------------------------------------------

info ""
info "fail2ban:"
fail2ban-client status 2>/dev/null | sed 's/^/    /' || warn "fail2ban-client antwortet nicht"

# --- Apache ----------------------------------------------------------------

info ""
check "Apache-Konfiguration ist gueltig" apache2ctl configtest

info ""
info "Zustaendige VirtualHosts:"
# Bis zur Zeile "ServerRoot:" steht die Zuordnung Port -> vHost -> Datei.
# Auf Ubuntu 24.04 lautet eine Zeile "*:443  name (datei:zeile)"; das Wort
# "namevhost" erscheint nur, wenn mehrere Namen denselben Port teilen.
apache2ctl -S 2>/dev/null | sed -n '/VirtualHost configuration/,/^ServerRoot/p' \
	| grep -v '^ServerRoot' | sed 's/^/    /' || true

# --- Die Site selbst -------------------------------------------------------

info ""
info "Abruf ueber die Loopback-Schnittstelle (unabhaengig von DNS und Firewall):"

http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
	-H "Host: ${SITE_NAME}" "http://127.0.0.1/" 2>/dev/null)" || true
[ -n "$http_code" ] || http_code=000
case "$http_code" in
	301|302) ok "  http liefert $http_code (Weiterleitung auf https) - richtig" ;;
	*)       warn "  http liefert $http_code, erwartet war 301"; CHECKS_FAILED=$((CHECKS_FAILED + 1)) ;;
esac

# -k, weil bei TLS_MODE=selfsigned das Zertifikat erwartungsgemaess nicht
# geprueft werden kann; --resolve, damit der ServerName trotzdem passt.
https_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
	--resolve "${SITE_NAME}:443:127.0.0.1" "https://${SITE_NAME}/" 2>/dev/null)" || true
[ -n "$https_code" ] || https_code=000
case "$https_code" in
	200) ok "  https liefert 200" ;;
	*)   warn "  https liefert $https_code, erwartet war 200"; CHECKS_FAILED=$((CHECKS_FAILED + 1)) ;;
esac

# Weiterleitungsdomains: 301 auf die Hauptsite, mit passendem Zertifikat.
for name in $REDIRECT_DOMAINS; do
	redirect_out="$(curl -sk -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 \
		--resolve "${name}:443:127.0.0.1" "https://${name}/" 2>/dev/null)" || true
	case "$redirect_out" in
		"301 https://${SITE_NAME}/") ok "  https://${name}/ leitet weiter auf https://${SITE_NAME}/" ;;
		*) warn "  https://${name}/ liefert '${redirect_out:-000}', erwartet war 301 auf https://${SITE_NAME}/"
		   CHECKS_FAILED=$((CHECKS_FAILED + 1)) ;;
	esac
done

# Ist der Inhalt schon da, oder noch die Platzhalterseite?
if [ -f "$DOC_ROOT/de/index.html" ]; then
	ok "  Inhalt ist ausgerollt ($DOC_ROOT/de/index.html vorhanden)"
	info "  Dateien unter $DOC_ROOT: $(find "$DOC_ROOT" -type f | wc -l), Groesse: $(du -sh "$DOC_ROOT" | cut -f1)"
else
	warn "  Noch kein Inhalt ausgerollt - ./deploy-site.sh ausfuehren."
fi

info ""
info "Antwortkopfzeilen:"
curl -sk -I --max-time 10 --resolve "${SITE_NAME}:443:127.0.0.1" "https://${SITE_NAME}/" 2>/dev/null \
	| grep -iE '^(HTTP/|strict-transport|content-security|x-content-type|x-frame|referrer-policy|permissions-policy|cache-control|content-type)' \
	| sed 's/^/    /' || true

# --- Vorschau --------------------------------------------------------------

if [ "${ENABLE_STAGING:-no}" = yes ]; then
	info ""
	info "Vorschau (Zweig staging):"
	info "  Adresse:     https://${SITE_NAME}${STAGING_URL_PATH}/"
	info "  Verzeichnis: $STAGING_DOC_ROOT"

	# Sie darf nicht unter dem DocumentRoot liegen - sonst raeumt die naechste
	# Auslieferung der oeffentlichen Site sie ab.
	case "${STAGING_DOC_ROOT%/}/" in
		"${DOC_ROOT%/}"/*)
			warn "  liegt UNTER $DOC_ROOT - die naechste Auslieferung der Site wuerde sie loeschen!"
			CHECKS_FAILED=$((CHECKS_FAILED + 1)) ;;
		*)  ok "  liegt neben $DOC_ROOT, nicht darunter" ;;
	esac

	staging_code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
		--resolve "${SITE_NAME}:443:127.0.0.1" "https://${SITE_NAME}${STAGING_URL_PATH}/" 2>/dev/null)" || true
	[ -n "$staging_code" ] || staging_code=000
	case "$staging_code" in
		200) ok "  antwortet mit 200" ;;
		401) ok "  antwortet mit 401 (Anmeldung verlangt) - so gewollt" ;;
		*)   warn "  antwortet mit $staging_code, erwartet war 200 oder 401"
		     CHECKS_FAILED=$((CHECKS_FAILED + 1)) ;;
	esac

	# noindex muss sitzen: ohne diesen Kopf wuerde die Vorschau in
	# Suchmaschinen auftauchen und der oeffentlichen Site Konkurrenz machen.
	if curl -sk -I --max-time 10 --resolve "${SITE_NAME}:443:127.0.0.1" \
		"https://${SITE_NAME}${STAGING_URL_PATH}/" 2>/dev/null \
		| grep -qi '^x-robots-tag:.*noindex'; then
		ok "  X-Robots-Tag: noindex ist gesetzt"
	else
		warn "  X-Robots-Tag: noindex FEHLT - die Vorschau koennte indexiert werden"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
	fi

	if [ -n "${STAGING_BASIC_AUTH_USERS:-}" ]; then
		info "  mit Anmeldung (STAGING_BASIC_AUTH_USERS ist gesetzt)"
	else
		info "  offen erreichbar - wer die Adresse kennt, sieht sie"
	fi
fi


# --- Protokollfristen gegen die Datenschutzerklaerung -----------------------
#
# Die Datenschutzerklaerung der Site sagt zu: vollstaendige Fassung 7 Tage,
# gekuerzte Fassung 6 Monate. Hier wird nachgesehen, ob die Regeln das auch
# hergeben - eine Zusage, die niemand nachprueft, ist keine.

info ""
info "Aufbewahrung der Protokolle:"

pruefe_frist() {
	local datei="$1" erwartet="$2" was="$3" ist
	if [ ! -f "$datei" ]; then
		warn "  $datei fehlt"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
		return
	fi
	ist="$(awk '/^[[:space:]]*rotate[[:space:]]+[0-9]+[[:space:]]*$/{print $2; exit}' "$datei")"
	if [ "$ist" = "$erwartet" ]; then
		ok "  $was: rotate $ist  ($datei)"
	else
		warn "  $was: rotate ${ist:-?} statt $erwartet  ($datei)"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
	fi
}

# Vollstaendige IP-Adresse -> 7 Tage. Betrifft die Zugriffsprotokolle UND das
# Fehlerprotokoll von Apache sowie /var/log/fail2ban.log (gesperrte Adressen).
pruefe_frist /etc/logrotate.d/apache2  7 "Apache, vollstaendig (7 Tage)"
pruefe_frist /etc/logrotate.d/fail2ban 7 "fail2ban, gesperrte Adressen (7 Tage)"

# Gekuerzte Adresse -> 6 Monatsarchive.
pruefe_frist /etc/logrotate.d/dbg      6 "Statistik, gekuerzt (6 Monate)"

if logrotate -d /etc/logrotate.conf 2>&1 | grep -q '^error:'; then
	warn "  logrotate meldet Fehler - pruefen mit: logrotate -d /etc/logrotate.conf"
	CHECKS_FAILED=$((CHECKS_FAILED + 1))
else
	ok "  logrotate laeuft ohne Fehler durch"
fi

# Schreibt der Server die gekuerzte Fassung ueberhaupt?
if [ -f /var/log/apache2-stats/access-anon.log ]; then
	if grep -qE '^([0-9]{1,3}\.){3}0 |^[0-9a-fA-F:]+:: |^unbekannt ' /var/log/apache2-stats/access-anon.log 2>/dev/null; then
		ok "  access-anon.log enthaelt nur gekuerzte Adressen"
	else
		info "  access-anon.log ist noch leer oder enthaelt keine Treffer zum Pruefen"
	fi
else
	info "  access-anon.log noch nicht angelegt (kommt beim ersten Zugriff)"
fi


# --- Zertifikat ------------------------------------------------------------

info ""
info "Zertifikat:"
if [ "$TLS_MODE" = selfsigned ]; then
	openssl x509 -in /etc/ssl/dbg/fullchain.pem -noout -subject -enddate 2>/dev/null | sed 's/^/    /' || true
	if [ -n "$REDIRECT_DOMAINS" ]; then
		openssl x509 -in /etc/ssl/dbg-redirect/fullchain.pem -noout -subject -enddate 2>/dev/null | sed 's/^/    /' || true
	fi
	warn "  selbst ausgestellt - fuer den Betrieb TLS_MODE=letsencrypt setzen"
else
	certbot certificates 2>/dev/null | grep -E 'Certificate Name|Domains|Expiry' | sed 's/^/    /' || true
	if systemctl list-timers --all 2>/dev/null | grep -q certbot; then
		ok "  certbot.timer ist eingerichtet (automatische Erneuerung)"
	else
		warn "  certbot.timer fehlt - die Erneuerung laeuft nicht automatisch"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
	fi
fi

# --- Auslieferung aus GitHub ------------------------------------------------

if [ "${ENABLE_GITHUB_DEPLOY:-yes}" = yes ]; then
	info ""
	info "Auslieferung aus GitHub Actions:"

	if id "$DEPLOY_USER" >/dev/null 2>&1; then
		ok "  Benutzer $DEPLOY_USER ist vorhanden"
	else
		warn "  Benutzer $DEPLOY_USER fehlt"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
	fi

	authorized="/var/lib/dbg-deploy/.ssh/authorized_keys"
	if grep -q 'command="sudo -n /usr/local/sbin/dbg-receive-site"' "$authorized" 2>/dev/null; then
		ok "  Schluessel ist auf den Empfaenger festgelegt (erzwungener Befehl)"
	else
		warn "  in $authorized fehlt der erzwungene Befehl"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
	fi

	check "  Empfaenger ist ausfuehrbar"      test -x /usr/local/sbin/dbg-receive-site
	check "  sudo-Regel ist gueltig"          visudo -cf /etc/sudoers.d/dbg-deploy

	# Der Empfaenger laeuft hier ohne SSH - "status" darf nichts veraendern.
	if SSH_ORIGINAL_COMMAND=status /usr/local/sbin/dbg-receive-site >/dev/null 2>&1; then
		ok "  Empfaenger antwortet auf 'status'"
	else
		warn "  Empfaenger antwortet nicht auf 'status'"
		CHECKS_FAILED=$((CHECKS_FAILED + 1))
	fi

	info "  Werte fuer die GitHub-Secrets:  sudo ./show-deploy-secrets.sh"
fi


# --- SSH -------------------------------------------------------------------

info ""
info "SSH:"
info "    Port:                   $(sshd -T 2>/dev/null | awk '/^port /{print $2}' | paste -sd, -)"
info "    PermitRootLogin:        $(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')"
info "    PasswordAuthentication: $(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')"

info ""
if [ "$CHECKS_FAILED" -eq 0 ]; then
	ok "Alle Pruefungen bestanden."
else
	warn "$CHECKS_FAILED Pruefung(en) fehlgeschlagen - siehe oben."
fi
