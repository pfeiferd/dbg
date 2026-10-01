#!/bin/bash
# ---------------------------------------------------------------------------
# Installation der DBG-Website-VM
#
#   Grundlage: Ubuntu 24.04 LTS oder 26.04 LTS, frisch aufgesetzt.
#   Ergebnis:  ein gehaerteter Apache, der die generierte Site unter https
#              ausliefert. Offen sind nur SSH, 80 und 443.
#
# Aufruf auf der VM:
#
#     sudo ./install.sh                     alle Schritte
#     sudo ./install.sh --list              Schritte anzeigen
#     sudo ./install.sh --only tls,site     nur diese Schritte
#     sudo ./install.sh --skip base         alles ausser diesem Schritt
#     sudo ./install.sh --dry-run           nur zeigen, was laufen wuerde
#
# Jeder Schritt ist wiederholbar: ein zweiter Durchlauf aendert nur, was sich
# tatsaechlich unterscheidet, und sichert jede ersetzte Datei vorher weg.
#
# Angepasst wird ausschliesslich config/dbg-vm.conf. Einzelne Werte lassen
# sich auch von aussen ueberschreiben, ohne die Datei zu aendern:
#
#     sudo TLS_MODE=letsencrypt ./install.sh --only tls,site
#
# Die Konfigurationsvorlagen liegen unter files/ und spiegeln den Pfad auf der
# VM: files/etc/apache2/... landet unter /etc/apache2/...
# ---------------------------------------------------------------------------

set -euo pipefail

VM_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$VM_INSTALL_DIR/config/dbg-vm.conf}"

# shellcheck source=scripts/lib.sh
. "$VM_INSTALL_DIR/scripts/lib.sh"


# --- Schritte --------------------------------------------------------------
#
# Die Reihenfolge ist nicht beliebig:
#   ssh vor firewall   - die Firewall muss den neuen SSH-Port kennen
#   firewall vor f2ban - fail2ban setzt seine Sperren ueber ufw
#   apache vor tls     - der Nachweis von Let's Encrypt laeuft ueber Port 80
#   tls vor site       - Apache startet nicht ohne die Zertifikatsdateien
#   site vor deploy    - der Empfaenger prueft nach dem Ausliefern, ob die
#                        Site antwortet
#   verify zuletzt     - prueft nur

STEP_NAMES=(base       ssh        firewall      fail2ban      apache        tls        site        deploy       verify)
STEP_FILES=(10-base.sh 20-ssh.sh  30-firewall.sh 40-fail2ban.sh 50-apache.sh 60-tls.sh  70-site.sh  90-deploy.sh 80-verify.sh)
STEP_DESCS=(
	"Paketstand, Zeitzone, Sprachumgebung, automatische Sicherheitsaktualisierungen"
	"SSH-Daemon haerten, Port setzen"
	"ufw: nur SSH, 80 und 443 herein"
	"fail2ban: Fehlversuche bei SSH und Apache aussperren"
	"Apache installieren, Module, Grundhaertung, http-VirtualHost"
	"Zertifikat von Let's Encrypt (oder selbst ausgestellt)"
	"https-VirtualHost, DocumentRoot, Protokollfristen"
	"Zugang fuer GitHub Actions (Benutzer, Schluessel, Empfaenger)"
	"Abschlusspruefung - aendert nichts"
)


# --- Aufrufparameter -------------------------------------------------------

ONLY=""
SKIP=""
DRY_RUN=no

usage() {
	sed -n '2,/^# ---/p' "$VM_INSTALL_DIR/install.sh" | sed 's/^# \?//'
	exit "${1:-0}"
}

list_steps() {
	printf 'Schritte in dieser Reihenfolge:\n\n'
	local i
	for i in "${!STEP_NAMES[@]}"; do
		printf '  %-10s %-14s %s\n' "${STEP_NAMES[$i]}" "${STEP_FILES[$i]}" "${STEP_DESCS[$i]}"
	done
	printf '\nKonfiguration: %s\n' "$CONFIG_FILE"
	exit 0
}

while [ $# -gt 0 ]; do
	case "$1" in
		--only)    ONLY="${2:?--only braucht eine Liste von Schritten}"; shift 2 ;;
		--only=*)  ONLY="${1#*=}"; shift ;;
		--skip)    SKIP="${2:?--skip braucht eine Liste von Schritten}"; shift 2 ;;
		--skip=*)  SKIP="${1#*=}"; shift ;;
		--config)  CONFIG_FILE="${2:?--config braucht einen Dateinamen}"; shift 2 ;;
		--config=*) CONFIG_FILE="${1#*=}"; shift ;;
		--dry-run) DRY_RUN=yes; shift ;;
		--list)    list_steps ;;
		-h|--help) usage 0 ;;
		*)         printf 'Unbekannter Parameter: %s\n\n' "$1" >&2; usage 1 ;;
	esac
done


# --- Konfiguration einlesen ------------------------------------------------

[ -r "$CONFIG_FILE" ] || { printf 'Konfigurationsdatei nicht lesbar: %s\n' "$CONFIG_FILE" >&2; exit 1; }

# Werte, die bereits in der Umgebung stehen, sollen gewinnen - deshalb werden
# sie vor dem Einlesen gemerkt und danach wieder gesetzt.
declare -A OVERRIDES=()
for var in SITE_NAME SITE_ALIASES ADMIN_EMAIL DOC_ROOT TLS_MODE HSTS_MAX_AGE \
	HSTS_PRELOAD SSH_PORT SSH_PERMIT_ROOT_LOGIN SSH_DISABLE_PASSWORD_AUTH \
	SSH_ALLOW_USERS FIREWALL_EXTRA_ALLOW FIREWALL_IPV6 FAIL2BAN_BANTIME \
	FAIL2BAN_FINDTIME FAIL2BAN_MAXRETRY FAIL2BAN_IGNOREIP TIMEZONE \
	SYSTEM_LOCALE ENABLE_UNATTENDED_UPGRADES RUN_FULL_UPGRADE ENABLE_CSP \
	CSP_IMG_HOSTS ENABLE_GITHUB_DEPLOY DEPLOY_USER DEPLOY_SSH_PUBKEY \
	ENABLE_STAGING STAGING_URL_PATH STAGING_DOC_ROOT STAGING_BASIC_AUTH_USERS; do
	if [ -n "${!var+x}" ]; then
		OVERRIDES[$var]="${!var}"
	fi
done

# set -a sorgt dafuer, dass alle Werte aus der Konfiguration auch an die
# Schrittskripte und an untergeordnete Programme weitergegeben werden.
set -a
# Der Pfad steht erst zur Laufzeit fest, shellcheck kann ihm nicht folgen.
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

for var in "${!OVERRIDES[@]}"; do
	declare -g "$var=${OVERRIDES[$var]}"
	# Die Fragezeichen-Schreibweise sagt shellcheck, dass hier absichtlich die
	# Variable mit DEM NAMEN aus $var exportiert wird, nicht "var" selbst.
	export "${var?}"
done


# --- Abgeleitete Werte -----------------------------------------------------
#
# Alle Platzhalter, die render() ersetzt, muessen gesetzt sein - auch wenn der
# Schritt, der sie fuellt, in diesem Durchlauf nicht laeuft.

: "${SITE_ALIASES:=}"
: "${SSH_ALLOW_USERS:=}"
: "${FIREWALL_EXTRA_ALLOW:=}"
: "${FAIL2BAN_IGNOREIP:=}"
: "${CSP_IMG_HOSTS:=}"
: "${ENABLE_STAGING:=yes}"
: "${STAGING_URL_PATH:=/staging}"
: "${STAGING_DOC_ROOT:=/var/www/dbg-staging}"
: "${STAGING_BASIC_AUTH_USERS:=}"
: "${ENABLE_GITHUB_DEPLOY:=yes}"
: "${DEPLOY_USER:=dbg-deploy}"
: "${DEPLOY_SSH_PUBKEY:=}"

# Nachweisverzeichnis fuer Let's Encrypt. Bewusst ausserhalb des DocumentRoot,
# damit ein Neuausrollen des Site-Inhalts die Nachweise nicht loescht.
ACME_WEBROOT="${ACME_WEBROOT:-/var/www/acme}"

# Die folgenden *_DIRECTIVE-Werte liest placeholder_value() in scripts/lib.sh.
# Da die Dateien einzeln geprueft werden, gelten sie dort als unbenutzt.
# shellcheck disable=SC2034
if [ -n "$SITE_ALIASES" ]; then
	SERVER_ALIAS_DIRECTIVE="ServerAlias $SITE_ALIASES"
else
	SERVER_ALIAS_DIRECTIVE="# ServerAlias - keine weiteren Namen (SITE_ALIASES ist leer)"
fi

# Werden in den jeweiligen Schritten gefuellt.
SSH_PASSWORD_AUTH_EFFECTIVE="${SSH_PASSWORD_AUTH_EFFECTIVE:-yes}"
SSH_ALLOW_USERS_DIRECTIVE="${SSH_ALLOW_USERS_DIRECTIVE:-# AllowUsers - keine Beschraenkung}"
SSL_CERTIFICATE_FILE="${SSL_CERTIFICATE_FILE:-}"
SSL_CERTIFICATE_KEY_FILE="${SSL_CERTIFICATE_KEY_FILE:-}"
SSL_STAPLING_DIRECTIVE="${SSL_STAPLING_DIRECTIVE:-}"
# HSTS nur mit einem Zertifikat, dem der Browser traut. Mit diesem Kopf darf
# der Browser die Site fuer die angegebene Dauer nur noch per https aufrufen -
# bei einem ungueltigen Zertifikat gaebe es dann keinen Weg mehr hinein, und
# zuruecknehmen laesst sich die Zusage nicht. Der Wert haengt allein an der
# Konfiguration, steht also schon hier fest - so schreibt jeder Schritt
# dieselbe Datei und ein zweiter Durchlauf aendert nichts.
# shellcheck disable=SC2034
if [ "$TLS_MODE" = letsencrypt ] && [ -n "${HSTS_MAX_AGE:-}" ] && [ "${HSTS_MAX_AGE}" != 0 ]; then
	_hsts="max-age=${HSTS_MAX_AGE}; includeSubDomains"
	[ "${HSTS_PRELOAD:-no}" = yes ] && _hsts="${_hsts}; preload"
	HSTS_HEADER_DIRECTIVE="Header always set Strict-Transport-Security \"${_hsts}\""
else
	HSTS_HEADER_DIRECTIVE="# Strict-Transport-Security - nicht gesetzt (TLS_MODE=$TLS_MODE)"
fi
FAIL2BAN_IGNOREIP_EFFECTIVE="${FAIL2BAN_IGNOREIP_EFFECTIVE:-127.0.0.1/8 ::1}"

# Hierhin wird jede Datei gesichert, die ersetzt wird.
BACKUP_DIR="/var/backups/dbg-vm-install/$(date +%Y%m%d-%H%M%S)"


# --- Konfiguration pruefen -------------------------------------------------

validate_config() {
	local problems=0

	[ -n "${SITE_NAME:-}" ]   || { printf 'SITE_NAME ist nicht gesetzt.\n' >&2; problems=1; }
	[ -n "${ADMIN_EMAIL:-}" ] || { printf 'ADMIN_EMAIL ist nicht gesetzt.\n' >&2; problems=1; }
	[ -n "${DOC_ROOT:-}" ]    || { printf 'DOC_ROOT ist nicht gesetzt.\n' >&2; problems=1; }

	case "${TLS_MODE:-}" in
		letsencrypt|staging|selfsigned) ;;
		*) printf 'TLS_MODE muss letsencrypt, staging oder selfsigned sein (ist: %s).\n' "${TLS_MODE:-}" >&2; problems=1 ;;
	esac

	case "${SSH_PORT:-}" in
		''|*[!0-9]*) printf 'SSH_PORT muss eine Zahl sein (ist: %s).\n' "${SSH_PORT:-}" >&2; problems=1 ;;
		*) if [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
			printf 'SSH_PORT liegt ausserhalb 1-65535 (ist: %s).\n' "$SSH_PORT" >&2; problems=1
		   fi
		   case "$SSH_PORT" in
			80|443) printf 'SSH_PORT darf nicht 80 oder 443 sein - die braucht der Webserver.\n' >&2; problems=1 ;;
		   esac ;;
	esac

	case "$DOC_ROOT" in
		/*) ;;
		*) printf 'DOC_ROOT muss ein absoluter Pfad sein (ist: %s).\n' "$DOC_ROOT" >&2; problems=1 ;;
	esac

	if [ "${ENABLE_STAGING:-no}" = yes ]; then
		case "$STAGING_URL_PATH" in
			/*/) printf 'STAGING_URL_PATH darf nicht auf "/" enden (ist: %s).\n' "$STAGING_URL_PATH" >&2; problems=1 ;;
			/?*) ;;
			*)   printf 'STAGING_URL_PATH muss mit "/" beginnen (ist: %s).\n' "$STAGING_URL_PATH" >&2; problems=1 ;;
		esac

		case "$STAGING_DOC_ROOT" in
			/*) ;;
			*)  printf 'STAGING_DOC_ROOT muss ein absoluter Pfad sein (ist: %s).\n' "$STAGING_DOC_ROOT" >&2; problems=1 ;;
		esac

		# Der haeufigste Fehler, und ein boeser: liegt die Vorschau unter dem
		# DocumentRoot, loescht sie die naechste Auslieferung der
		# oeffentlichen Site ("rsync --delete").
		case "${STAGING_DOC_ROOT%/}/" in
			"${DOC_ROOT%/}"/*)
				printf 'STAGING_DOC_ROOT (%s) liegt unter DOC_ROOT (%s).\n' "$STAGING_DOC_ROOT" "$DOC_ROOT" >&2
				printf 'Die naechste Auslieferung der oeffentlichen Site wuerde die Vorschau loeschen.\n' >&2
				printf 'Bitte ein Verzeichnis DANEBEN waehlen, z.B. %s-staging.\n' "${DOC_ROOT%/}" >&2
				problems=1 ;;
		esac

		if [ "${STAGING_DOC_ROOT%/}" = "${DOC_ROOT%/}" ]; then
			printf 'STAGING_DOC_ROOT und DOC_ROOT duerfen nicht dasselbe Verzeichnis sein.\n' >&2
			problems=1
		fi
	fi

	[ "$problems" -eq 0 ] || { printf '\nBitte %s korrigieren.\n' "$CONFIG_FILE" >&2; exit 1; }
}


# --- Auswahl der Schritte --------------------------------------------------

step_known() {
	local name="$1" s
	for s in "${STEP_NAMES[@]}"; do [ "$s" = "$name" ] && return 0; done
	return 1
}

for name in ${ONLY//,/ } ${SKIP//,/ }; do
	step_known "$name" || { printf 'Unbekannter Schritt: %s\n\n' "$name" >&2; list_steps; }
done

selected() {
	local name="$1" s
	if [ -n "$ONLY" ]; then
		for s in ${ONLY//,/ }; do [ "$s" = "$name" ] && return 0; done
		return 1
	fi
	for s in ${SKIP//,/ }; do [ "$s" = "$name" ] && return 1; done
	return 0
}


# --- Los gehts -------------------------------------------------------------

printf '%s' "$C_HEAD"
cat <<'KOPF'
 ___  ___  ___
| . \| . >| . |   Deutsche Borreliose-Gesellschaft e.V.
| | || . \| | |   Installation der Website-VM
|___/|___/|___|
KOPF
printf '%s\n' "$C_OFF"

validate_config

info "Konfiguration:   $CONFIG_FILE"
info "Site:            $SITE_NAME${SITE_ALIASES:+  (auch: $SITE_ALIASES)}"
info "DocumentRoot:    $DOC_ROOT"
info "Zertifikat:      $TLS_MODE"
if [ "${ENABLE_STAGING:-no}" = yes ]; then
	info "Vorschau:        ${STAGING_URL_PATH}/  ->  $STAGING_DOC_ROOT${STAGING_BASIC_AUTH_USERS:+  (mit Anmeldung)}"
fi
info "SSH-Port:        $SSH_PORT"
if [ "${ENABLE_GITHUB_DEPLOY:-yes}" = yes ]; then
	info "GitHub-Zugang:   Benutzer $DEPLOY_USER (ueber Port $SSH_PORT)"
fi
info "Sicherungen in:  $BACKUP_DIR"
info "Protokoll:       ${INSTALL_LOG}  (ausfuehrliche Paketausgaben)"

if [ "$DRY_RUN" = yes ]; then
	printf '\n%sProbelauf - es wird nichts geaendert.%s\n' "$C_WARN" "$C_OFF"
	for i in "${!STEP_NAMES[@]}"; do
		if selected "${STEP_NAMES[$i]}"; then
			printf '  wuerde laufen:    %-10s %s\n' "${STEP_NAMES[$i]}" "${STEP_DESCS[$i]}"
		else
			printf '  uebersprungen:    %-10s\n' "${STEP_NAMES[$i]}"
		fi
	done
	exit 0
fi

require_root
log_start "$*"
step "System pruefen"
check_ubuntu

mkdir -p "$BACKUP_DIR"

START_TIME=$SECONDS

for i in "${!STEP_NAMES[@]}"; do
	name="${STEP_NAMES[$i]}"
	file="$VM_INSTALL_DIR/scripts/${STEP_FILES[$i]}"

	if ! selected "$name"; then
		continue
	fi

	[ -r "$file" ] || fail "Schrittdatei fehlt: $file"

	# shellcheck disable=SC1090
	. "$file"
done

# Sicherungsverzeichnis wieder wegraeumen, wenn nichts gesichert wurde.
rmdir "$BACKUP_DIR" 2>/dev/null && BACKUP_DIR="(nichts zu sichern)" || true

step "Fertig"
info "Dauer: $((SECONDS - START_TIME)) Sekunden"

if [ "$WARNINGS" -gt 0 ]; then
	warn "$WARNINGS Hinweis(e) oben beachten."
fi

cat <<ENDE

Naechste Schritte
-----------------

1) Inhalt ausrollen (von diesem Verzeichnis aus, auf der VM):

       sudo ./deploy-site.sh

   Er wird aus site/ genommen. Liegt dort nichts, zeigt das Skript, wie der
   Inhalt dorthin kommt.

2) Aufrufen:  https://${SITE_NAME}/
ENDE

if [ "$TLS_MODE" != letsencrypt ]; then
	cat <<ENDE

3) Sobald der DNS-Eintrag von ${SITE_NAME} auf diese VM zeigt, auf ein
   gueltiges Zertifikat umstellen: in config/dbg-vm.conf
   TLS_MODE="letsencrypt" setzen und

       sudo ./install.sh --only tls,site
ENDE
fi

if [ "$SSH_PORT" != 22 ]; then
	cat <<ENDE

WICHTIG: Der SSH-Port ist jetzt ${SSH_PORT}. Diese Sitzung offen halten und in
einem zweiten Terminal pruefen, dass die Anmeldung funktioniert:

       ssh -p ${SSH_PORT} \$USER@${SITE_NAME}
ENDE
fi

printf '\n'
