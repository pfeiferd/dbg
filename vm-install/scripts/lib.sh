#!/bin/bash
# ---------------------------------------------------------------------------
# Gemeinsame Hilfsfunktionen aller Installationsschritte.
# Wird von install.sh eingelesen, nicht direkt aufgerufen.
# ---------------------------------------------------------------------------

# --- Ausgabe ---------------------------------------------------------------

if [ -t 1 ]; then
	C_HEAD=$'\033[1;34m'; C_OK=$'\033[32m'; C_WARN=$'\033[33m'
	C_ERR=$'\033[31m';    C_OFF=$'\033[0m'
else
	C_HEAD=; C_OK=; C_WARN=; C_ERR=; C_OFF=
fi

step()  { printf '\n%s=== %s ===%s\n' "$C_HEAD" "$*" "$C_OFF"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  %s✓%s %s\n' "$C_OK" "$C_OFF" "$*"; }
warn()  { printf '  %s!%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; WARNINGS=$((WARNINGS + 1)); }
fail()  { printf '  %s✗ %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }

WARNINGS=${WARNINGS:-0}


# --- Vorbedingungen --------------------------------------------------------

require_root() {
	[ "$(id -u)" -eq 0 ] || fail "Dieses Skript muss als root laufen (sudo ./install.sh)."
}

# Prueft, dass wir auf einem Ubuntu LTS sind, und warnt bei etwas Unerwartetem.
check_ubuntu() {
	[ -r /etc/os-release ] || fail "/etc/os-release fehlt - kein Ubuntu?"
	# shellcheck disable=SC1091
	. /etc/os-release

	UBUNTU_VERSION="${VERSION_ID:-unbekannt}"
	UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-unbekannt}}"

	if [ "${ID:-}" != "ubuntu" ]; then
		warn "Erwartet wird Ubuntu, gefunden: ${PRETTY_NAME:-unbekannt}. Die Skripte koennen abweichen."
		return 0
	fi

	case "$UBUNTU_VERSION" in
		24.04|26.04)
			ok "Ubuntu $UBUNTU_VERSION LTS ($UBUNTU_CODENAME)" ;;
		22.04)
			warn "Ubuntu 22.04 LTS - laeuft, aber 24.04/26.04 LTS ist die Zielversion." ;;
		*)
			warn "Ubuntu $UBUNTU_VERSION ist keine getestete LTS-Version (getestet: 24.04, 26.04)." ;;
	esac
}


# --- Vorlagen aus files/ einsetzen ----------------------------------------
#
# Die Dateien unter files/ enthalten Platzhalter in spitzen Klammern, die hier
# durch die Werte aus config/dbg-vm.conf ersetzt werden. Dieselbe Schreibweise
# wie in den dev-vm-Projekten.

# Die vollstaendige Liste der Platzhalter. Nur diese Namen werden ersetzt, und
# nur sie gelten als Platzhalter - Text wie <script> oder <IfModule> in einer
# Konfigurationsdatei bleibt unberuehrt.
placeholder_names() {
	printf '%s\n' \
		site_name server_alias admin_email doc_root acme_webroot \
		ssh_port ssh_permit_root_login ssh_password_auth ssh_allow_users \
		ssl_certificate_file ssl_certificate_key_file ssl_stapling \
		hsts_header csp_img_hosts deploy_user \
		staging_url_path staging_doc_root \
		fail2ban_bantime fail2ban_findtime fail2ban_maxretry fail2ban_ignoreip
}

# Wert eines Platzhalters.
placeholder_value() {
	case "$1" in
		site_name)                printf '%s' "${SITE_NAME}" ;;
		server_alias)             printf '%s' "${SERVER_ALIAS_DIRECTIVE}" ;;
		admin_email)              printf '%s' "${ADMIN_EMAIL}" ;;
		doc_root)                 printf '%s' "${DOC_ROOT}" ;;
		acme_webroot)             printf '%s' "${ACME_WEBROOT}" ;;
		ssh_port)                 printf '%s' "${SSH_PORT}" ;;
		ssh_permit_root_login)    printf '%s' "${SSH_PERMIT_ROOT_LOGIN}" ;;
		ssh_password_auth)        printf '%s' "${SSH_PASSWORD_AUTH_EFFECTIVE}" ;;
		ssh_allow_users)          printf '%s' "${SSH_ALLOW_USERS_DIRECTIVE}" ;;
		ssl_certificate_file)     printf '%s' "${SSL_CERTIFICATE_FILE}" ;;
		ssl_certificate_key_file) printf '%s' "${SSL_CERTIFICATE_KEY_FILE}" ;;
		ssl_stapling)             printf '%s' "${SSL_STAPLING_DIRECTIVE}" ;;
		hsts_header)              printf '%s' "${HSTS_HEADER_DIRECTIVE}" ;;
		csp_img_hosts)            printf '%s' "${CSP_IMG_HOSTS}" ;;
		deploy_user)              printf '%s' "${DEPLOY_USER}" ;;
		staging_url_path)         printf '%s' "${STAGING_URL_PATH}" ;;
		staging_doc_root)         printf '%s' "${STAGING_DOC_ROOT}" ;;
		fail2ban_bantime)         printf '%s' "${FAIL2BAN_BANTIME}" ;;
		fail2ban_findtime)        printf '%s' "${FAIL2BAN_FINDTIME}" ;;
		fail2ban_maxretry)        printf '%s' "${FAIL2BAN_MAXRETRY}" ;;
		fail2ban_ignoreip)        printf '%s' "${FAIL2BAN_IGNOREIP_EFFECTIVE}" ;;
		*) fail "Unbekannter Platzhalter: <$1>" ;;
	esac
}

# render <quelldatei-unter-files> <zieldatei> [modus]
render() {
	local src="$VM_INSTALL_DIR/files/$1" dst="$2" mode="${3:-0644}" tmp name value escaped

	[ -r "$src" ] || fail "Vorlage fehlt: $src"

	tmp="$(mktemp)"
	cp "$src" "$tmp"

	while read -r name; do
		value="$(placeholder_value "$name")"
		# Im Ersetzungstext von sed haben "\", "&" und das Trennzeichen eine
		# eigene Bedeutung - also entschaerfen, in genau dieser Reihenfolge.
		escaped="${value//\\/\\\\}"
		escaped="${escaped//&/\\&}"
		escaped="${escaped//|/\\|}"

		# "|" als Trennzeichen statt "/": in Pfaden und Apache-Anweisungen
		# kommt "/" dauernd vor, "|" so gut wie nie.
		sed -i "s|<${name}>|${escaped}|g" "$tmp"
	done < <(placeholder_names)

	# Jetzt darf keiner der bekannten Platzhalter mehr darinstehen.
	local leftover=""
	while read -r name; do
		if grep -q "<${name}>" "$tmp"; then
			leftover="$leftover <$name>"
		fi
	done < <(placeholder_names)

	if [ -n "$leftover" ]; then
		rm -f "$tmp"
		fail "In $src sind Platzhalter uebrig geblieben:$leftover"
	fi

	install_file "$tmp" "$dst" "$mode"
	rm -f "$tmp"
}

# install_file <quelldatei> <zieldatei> [modus]
# Legt die Datei ab, sichert eine vorhandene abweichende Version weg und sagt,
# ob sich etwas geaendert hat. Mehrfaches Ausfuehren ist damit unschaedlich.
install_file() {
	local src="$1" dst="$2" mode="${3:-0644}"

	mkdir -p "$(dirname "$dst")"

	if [ -e "$dst" ] && cmp -s "$src" "$dst"; then
		# Inhalt gleich - die Rechte trotzdem durchsetzen, damit sie nach
		# jedem Lauf stimmen und nicht von einer frueheren Fassung abhaengen.
		chmod "$mode" "$dst"
		info "$dst (unveraendert)"
	else
		if [ -e "$dst" ]; then
			local backup
			backup="$BACKUP_DIR/$(printf '%s' "${dst#/}" | tr '/' '_')"
			mkdir -p "$BACKUP_DIR"
			cp -p "$dst" "$backup"
			info "vorherige Version gesichert: $backup"
		fi
		cp "$src" "$dst"
		chmod "$mode" "$dst"
		ok "$dst"
	fi
}

# Datei aus files/ ohne Platzhalter-Ersetzung ablegen.
# copy_file <pfad-unter-files> <zieldatei> [modus]
#
# Bricht ab, wenn die Datei doch einen Platzhalter enthaelt. Ohne diese Pruefung
# landet im schlimmsten Fall ein "<staging_url_path>" unersetzt in einer
# Apache-Regel - die Konfiguration ist dann gueltig, tut aber nicht, was sie
# soll, und niemand merkt es. Genau das ist beim Testen passiert.
copy_file() {
	local src="$VM_INSTALL_DIR/files/$1" name leftover=""

	[ -r "$src" ] || fail "Vorlage fehlt: $src"

	while read -r name; do
		grep -q "<${name}>" "$src" && leftover="$leftover <$name>"
	done < <(placeholder_names)

	if [ -n "$leftover" ]; then
		fail "$src enthaelt Platzhalter ($leftover) - hier muss render() statt copy_file() benutzt werden."
	fi

	install_file "$src" "$2" "${3:-0644}"
}


# --- Protokoll -------------------------------------------------------------
#
# Die Ausgabe von apt und dpkg ist so umfangreich, dass Hinweise darin
# untergehen. Sie wandert deshalb in eine Datei; auf dem Bildschirm erscheint
# sie nur, wenn etwas schiefgeht.

INSTALL_LOG="${INSTALL_LOG:-/var/log/dbg-vm-install.log}"

log_start() {
	mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null || INSTALL_LOG=/tmp/dbg-vm-install.log
	{
		printf '\n'
		printf '=== %s  install.sh %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${*:-}"
	} >> "$INSTALL_LOG" 2>/dev/null || true
}

# run_logged <beschreibung> <befehl...>
# Fuehrt den Befehl aus und schreibt seine Ausgabe in das Protokoll. Scheitert
# er, werden die letzten Zeilen gezeigt.
run_logged() {
	local label="$1"; shift

	printf '\n--- %s\n--- %s\n' "$(date '+%H:%M:%S')" "$*" >> "$INSTALL_LOG" 2>/dev/null || true

	# Den Rueckgabewert direkt am Befehl einsammeln. Ihn nach einem "if" aus $?
	# zu lesen, geht schief: ein if ohne else liefert selbst 0, der Wert des
	# Befehls ist dann schon verloren - und ein Fehlschlag saehe wie ein
	# Erfolg aus.
	local rc=0
	"$@" >> "$INSTALL_LOG" 2>&1 || rc=$?

	[ "$rc" -eq 0 ] && return 0

	printf '  %s✗ %s fehlgeschlagen (Rueckgabewert %s)%s\n' "$C_ERR" "$label" "$rc" "$C_OFF" >&2
	printf '  letzte Zeilen aus %s:\n' "$INSTALL_LOG" >&2
	tail -n 25 "$INSTALL_LOG" 2>/dev/null | sed 's/^/      /' >&2
	return $rc
}


# --- Pakete ----------------------------------------------------------------

APT_UPDATED=no

apt_update_once() {
	if [ "$APT_UPDATED" != yes ]; then
		info "Paketlisten auffrischen (apt-get update)"
		run_logged "apt-get update" env DEBIAN_FRONTEND=noninteractive apt-get update -qq \
			|| fail "apt-get update ist fehlgeschlagen. Netzwerkverbindung und Paketquellen pruefen."
		APT_UPDATED=yes
	fi
}

# apt_install <paket> ...
apt_install() {
	local missing=()
	local pkg
	for pkg in "$@"; do
		dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed" || missing+=("$pkg")
	done

	if [ ${#missing[@]} -eq 0 ]; then
		info "bereits installiert: $*"
		return 0
	fi

	apt_update_once
	info "installiere: ${missing[*]}"
	run_logged "apt-get install ${missing[*]}" \
		env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${missing[@]}" \
		|| fail "Paketinstallation fehlgeschlagen: ${missing[*]}"
}

# Ist das Paket verfuegbar? (Fuer optionale Module wie brotli.)
apt_available() {
	apt_update_once
	apt-cache show "$1" >/dev/null 2>&1
}


# --- Dienste ---------------------------------------------------------------

service_restart() {
	info "starte $1 neu"
	systemctl restart "$1"
}

service_enable() {
	systemctl enable --quiet "$1" 2>/dev/null || systemctl enable "$1"
}

service_is_active() {
	systemctl is-active --quiet "$1"
}


# --- Apache ----------------------------------------------------------------

# Konfiguration pruefen. Die Ausgabe von apache2ctl landet auf stderr, deshalb
# wird sie erst eingesammelt und dann ausgegeben - sonst verdeckt der
# Rueckgabewert von sed den von apache2ctl.
apache_configtest() {
	local out rc
	out="$(apache2ctl configtest 2>&1)"; rc=$?
	printf '%s\n' "$out" | sed 's/^/    /'
	return $rc
}


# --- logrotate --------------------------------------------------------------

# logrotate_set_retention <regeldatei> <tage>
#
# Setzt eine vorhandene logrotate-Regel auf taegliches Drehen und <tage>
# Archive. Die mitgelieferten Regeln werden angepasst statt ergaenzt: zwei
# Regeln fuer dieselbe Datei beantwortet logrotate mit "duplicate log entry"
# und bricht ab.
#
# Hintergrund: die Datenschutzerklaerung der Site sagt fuer Protokolle mit
# vollstaendiger IP-Adresse 7 Tage zu. Das betrifft die Zugriffs- und
# Fehlerprotokolle von Apache und ebenso /var/log/fail2ban.log, in dem die
# Adressen gesperrter Zugriffe stehen.
logrotate_set_retention() {
	local file="$1" days="$2"

	if [ ! -f "$file" ]; then
		info "$file ist nicht vorhanden - nichts anzupassen"
		return 0
	fi

	if grep -qE "^[[:space:]]*rotate[[:space:]]+${days}[[:space:]]*\$" "$file" \
		&& grep -qE '^[[:space:]]*daily[[:space:]]*$' "$file"; then
		info "$file steht schon auf taeglich / $days Archive"
		return 0
	fi

	mkdir -p "$BACKUP_DIR"
	cp -p "$file" "$BACKUP_DIR/$(printf '%s' "${file#/}" | tr '/' '_')"

	sed -i \
		-e "s/^\([[:space:]]*\)rotate[[:space:]]\+[0-9]\+/\1rotate ${days}/" \
		-e 's/^\([[:space:]]*\)weekly[[:space:]]*$/\1daily/' \
		-e 's/^\([[:space:]]*\)monthly[[:space:]]*$/\1daily/' \
		"$file"

	# Stand dort gar keine Frequenz, eine ergaenzen.
	grep -qE '^[[:space:]]*daily[[:space:]]*$' "$file" \
		|| sed -i '0,/{/s/{/{\n\tdaily/' "$file"

	ok "$file auf taeglich / $days Archive gesetzt"
}
