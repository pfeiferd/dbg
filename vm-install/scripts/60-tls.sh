#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "tls": Zertifikat beschaffen.
#
# Drei Betriebsarten, gesteuert ueber TLS_MODE in config/dbg-vm.conf:
#
#   letsencrypt  echtes Zertifikat. Setzt voraus, dass der DNS-Eintrag von
#                SITE_NAME schon auf diese VM zeigt und Port 80 von aussen
#                erreichbar ist - Let's Encrypt prueft genau darueber, dass
#                wir die Domain tatsaechlich betreiben.
#   staging      dasselbe gegen die Testumgebung. Das Zertifikat ist im
#                Browser ungueltig, dafuer gibt es keine Rate Limits. Zum
#                Ausprobieren der Zustellung gedacht.
#   selfsigned   selbst ausgestelltes Zertifikat, ohne jede Anfrage nach
#                draussen. Damit laeuft die Site vollstaendig, solange der
#                DNS-Eintrag noch nicht umgestellt ist; der Browser warnt.
#
# Mit REDIRECT_DOMAINS gibt es ein zweites Zertifikat fuer die
# Weiterleitungsdomains (Name = erster Eintrag). Es wird nach dem der Site
# beschafft, ein Fehler dort laesst das Zertifikat der Site also unberuehrt.
#
# Die Nachweismethode ist webroot, nicht --apache: certbot fasst dann die
# Apache-Konfiguration nicht an. Was in sites-available steht, bleibt also
# genau das, was in files/ liegt - nachvollziehbar und wiederholbar.
# ---------------------------------------------------------------------------

step "Zertifikat beschaffen (TLS_MODE=$TLS_MODE)"

SELFSIGNED_DIR=/etc/ssl/dbg
SELFSIGNED_REDIRECT_DIR=/etc/ssl/dbg-redirect

# --- selbst ausgestelltes Zertifikat ---------------------------------------

# make_selfsigned <verzeichnis> <name> [weitere namen ...]
make_selfsigned() {
	local dir="$1" cn="$2"
	shift
	apt_install openssl

	mkdir -p "$dir"
	chmod 0700 "$dir"

	if [ -s "$dir/fullchain.pem" ] && [ -s "$dir/privkey.pem" ] \
		&& openssl x509 -in "$dir/fullchain.pem" -noout -checkend 604800 >/dev/null 2>&1; then
		info "selbst ausgestelltes Zertifikat fuer $cn ist vorhanden und noch mindestens eine Woche gueltig"
		return 0
	fi

	local alt="" name
	for name in "$@"; do
		alt="${alt:+$alt,}DNS:$name"
	done

	openssl req -x509 -newkey rsa:2048 -nodes -sha256 -days 825 \
		-keyout "$dir/privkey.pem" \
		-out    "$dir/fullchain.pem" \
		-subj   "/CN=${cn}" \
		-addext "subjectAltName=${alt}" \
		-addext "basicConstraints=CA:FALSE" \
		-addext "keyUsage=digitalSignature,keyEncipherment" \
		-addext "extendedKeyUsage=serverAuth" \
		2>/dev/null

	chmod 0600 "$dir/privkey.pem"
	chmod 0644 "$dir/fullchain.pem"

	ok "selbst ausgestelltes Zertifikat erzeugt: $dir/fullchain.pem ($*)"
	warn "Der Browser wird warnen. Fuer ein gueltiges Zertifikat TLS_MODE=letsencrypt setzen"
	warn "und erneut laufen lassen:  sudo ./install.sh --only tls,site"
}


# --- Let's Encrypt ---------------------------------------------------------

# request_letsencrypt <zertifikatsname> <name> [weitere namen ...]
request_letsencrypt() {
	local cert_name="$1"
	shift
	# certbot aus den Ubuntu-Paketquellen, nicht als snap: dann braucht die
	# VM kein snapd, und die Erneuerung haengt am regulaeren Paketstand.
	# Der Timer certbot.timer kommt mit dem Paket und laeuft zweimal taeglich.
	apt_install certbot

	[ -n "$ADMIN_EMAIL" ] || fail "ADMIN_EMAIL ist leer - Let's Encrypt braucht eine Kontaktadresse."

	# Vorab pruefen, ob der Nachweisweg ueberhaupt offen ist. Ohne das endet
	# certbot mit einer Fehlermeldung, die schwerer zu deuten ist.
	local probe="$ACME_WEBROOT/.well-known/acme-challenge/dbg-install-probe"
	mkdir -p "$(dirname "$probe")"
	echo "dbg-install-probe" > "$probe"

	# Let's Encrypt prueft JEDEN Namen des Zertifikats - einer, der nicht
	# auf diese VM zeigt, laesst die ganze Anfrage scheitern. Deshalb alle
	# vorab pruefen.
	local name url domain_args=""
	for name in "$@"; do
		url="http://${name}/.well-known/acme-challenge/dbg-install-probe"
		if curl -fsS --max-time 15 "$url" 2>/dev/null | grep -q dbg-install-probe; then
			ok "Nachweisweg erreichbar: $url"
		else
			rm -f "$probe"
			warn "$url ist von hier aus nicht erreichbar."
			warn "Moegliche Ursachen: der DNS-Eintrag von ${name} zeigt noch nicht auf diese VM,"
			warn "oder Port 80 ist von aussen gesperrt (Sicherheitsgruppe/Router des Anbieters)."
			fail "Abbruch, damit kein Fehlversuch auf das Rate Limit von Let's Encrypt geht. Pruefen mit: dig +short ${name}  -  den Namen aus der Konfiguration nehmen oder vorlaeufig TLS_MODE=selfsigned setzen."
		fi
		domain_args="$domain_args -d $name"
	done
	rm -f "$probe"

	local staging_arg=""
	if [ "$TLS_MODE" = staging ]; then
		staging_arg="--staging"
		warn "Testumgebung (--staging): das Zertifikat ist im Browser UNGUELTIG."
	fi

	# --keep-until-expiring macht den Aufruf wiederholbar: ein noch lange
	# gueltiges Zertifikat wird nicht unnoetig neu ausgestellt.
	# --cert-name haelt den Ablageort fest (/etc/letsencrypt/live/<name>/),
	# auch wenn sich die Liste der Namen spaeter aendert - darauf verweist
	# die Apache-Konfiguration.
	# shellcheck disable=SC2086
	certbot certonly \
		--cert-name "$cert_name" \
		--webroot --webroot-path "$ACME_WEBROOT" \
		$domain_args \
		$staging_arg \
		--agree-tos \
		--email "$ADMIN_EMAIL" \
		--non-interactive \
		--keep-until-expiring \
		--no-eff-email \
		|| fail "certbot ist fehlgeschlagen - Einzelheiten in /var/log/letsencrypt/letsencrypt.log"

	ok "Zertifikat liegt in /etc/letsencrypt/live/${cert_name}/ ($*)"
}

# Erneuerung einrichten - einmal fuer alle Zertifikate.
setup_renewal() {

	# Nach der Erneuerung muss Apache das neue Zertifikat einlesen. certbot
	# ruft dafuer alles auf, was in renewal-hooks/deploy/ liegt.
	local hook=/etc/letsencrypt/renewal-hooks/deploy/10-reload-apache.sh
	mkdir -p "$(dirname "$hook")"
	local tmp; tmp="$(mktemp)"
	cat > "$tmp" <<-'HOOK'
		#!/bin/bash
		# Erzeugt von vm-install/scripts/60-tls.sh
		#
		# Wird von certbot nach jeder erfolgreichen Erneuerung aufgerufen.
		# Apache liest Zertifikate nur beim Start ein, ein erneuertes
		# Zertifikat wird also erst mit diesem reload wirksam.
		set -e
		if apache2ctl configtest >/dev/null 2>&1; then
			systemctl reload apache2
		else
			echo "Apache-Konfiguration ist fehlerhaft - kein reload." >&2
			exit 1
		fi
	HOOK
	install_file "$tmp" "$hook" 0755
	rm -f "$tmp"

	service_enable certbot.timer 2>/dev/null || true
	systemctl start certbot.timer 2>/dev/null || true

	if systemctl is-enabled certbot.timer >/dev/null 2>&1; then
		ok "automatische Erneuerung aktiv (certbot.timer, zweimal taeglich)"
		info "Probelauf: certbot renew --dry-run"
	else
		warn "certbot.timer ist nicht aktiv - die Erneuerung muesste von Hand angestossen werden."
	fi
}


# --- Betriebsart auswaehlen ------------------------------------------------

# shellcheck disable=SC2086
case "$TLS_MODE" in
	letsencrypt|staging)
		request_letsencrypt "$SITE_NAME" "$SITE_NAME" $SITE_ALIASES
		if [ -n "$REDIRECT_DOMAINS" ]; then
			request_letsencrypt "$REDIRECT_NAME" $REDIRECT_DOMAINS
		fi
		setup_renewal
		;;
	selfsigned)
		make_selfsigned "$SELFSIGNED_DIR" "$SITE_NAME" $SITE_ALIASES
		if [ -n "$REDIRECT_DOMAINS" ]; then
			make_selfsigned "$SELFSIGNED_REDIRECT_DIR" $REDIRECT_DOMAINS
		fi
		;;
	*)
		fail "TLS_MODE muss letsencrypt, staging oder selfsigned sein (ist: $TLS_MODE)"
		;;
esac
