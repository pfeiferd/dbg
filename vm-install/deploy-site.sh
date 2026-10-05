#!/bin/bash
# ---------------------------------------------------------------------------
# Generierte Site auf der VM ausrollen
#
# Laeuft auf der VM, im Verzeichnis vm-install:
#
#     sudo ./deploy-site.sh                 Inhalt aus site/
#     sudo ./deploy-site.sh /pfad/website   Inhalt von dort
#     sudo ./deploy-site.sh --staging       in die Vorschau statt auf die Site
#     sudo ./deploy-site.sh --dry-run       nur zeigen, was sich aendern wuerde
#
# Der Inhalt wird abgeglichen, nicht einfach darueberkopiert: Dateien, die es
# im Quellverzeichnis nicht mehr gibt, verschwinden auch auf der VM. Eine
# geloeschte Seite bleibt damit nicht als Ruine erreichbar.
#
# Beim Umschalten gibt es keinen Moment, in dem die Site halb neu ist: rsync
# baut die neue Fassung in einem Nachbarverzeichnis auf und das alte wird erst
# danach ersetzt.
# ---------------------------------------------------------------------------

set -euo pipefail

VM_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$VM_INSTALL_DIR/config/dbg-vm.conf}"

# shellcheck source=scripts/lib.sh
. "$VM_INSTALL_DIR/scripts/lib.sh"

[ -r "$CONFIG_FILE" ] || { printf 'Konfigurationsdatei nicht lesbar: %s\n' "$CONFIG_FILE" >&2; exit 1; }
# set -a sorgt dafuer, dass alle Werte aus der Konfiguration auch an die
# Schrittskripte und an untergeordnete Programme weitergegeben werden.
set -a
# Der Pfad steht erst zur Laufzeit fest, shellcheck kann ihm nicht folgen.
# shellcheck source=/dev/null
. "$CONFIG_FILE"
set +a

DRY_RUN=no
SOURCE=""
TO_STAGING=no

while [ $# -gt 0 ]; do
	case "$1" in
		--dry-run) DRY_RUN=yes; shift ;;
		--staging) TO_STAGING=yes; shift ;;
		-h|--help) sed -n '2,/^# ---/p' "$0" | sed 's/^# \?//'; exit 0 ;;
		-*) printf 'Unbekannter Parameter: %s\n' "$1" >&2; exit 1 ;;
		*)  SOURCE="$1"; shift ;;
	esac
done

# --- Quelle bestimmen ------------------------------------------------------

if [ -z "$SOURCE" ]; then
	# site/ im Bundle, danach das Maven-Ziel - falls das Skript ausnahmsweise
	# im Projektverzeichnis auf dem Arbeitsrechner laeuft.
	for candidate in "$VM_INSTALL_DIR/site" "$VM_INSTALL_DIR/../target/website"; do
		if [ -f "$candidate/index.html" ]; then
			SOURCE="$candidate"
			break
		fi
	done
fi

if [ -z "$SOURCE" ] || [ ! -f "$SOURCE/index.html" ]; then
	cat >&2 <<HINWEIS
Kein Site-Inhalt gefunden.

Gesucht wurde nach einer index.html in
    $VM_INSTALL_DIR/site/
    $VM_INSTALL_DIR/../target/website/

So kommt der Inhalt hierher - auf dem Arbeitsrechner im dbg-Projekt:

    mvn package                     # erzeugt target/website/
    vm-install/make-bundle.sh       # packt vm-install samt Inhalt
    scp /tmp/dbg-vm-install.tar.gz <benutzer>@${SITE_NAME}:

und dann auf der VM:

    tar xzf dbg-vm-install.tar.gz && cd vm-install && sudo ./deploy-site.sh

Oder den Inhalt direkt abgleichen, ohne Paket:

    rsync -av --delete target/website/ <benutzer>@${SITE_NAME}:/tmp/website/
    ssh <benutzer>@${SITE_NAME} 'cd vm-install && sudo ./deploy-site.sh /tmp/website'
HINWEIS
	exit 1
fi

SOURCE="$(cd "$SOURCE" && pwd)"

# Ziel: oeffentliche Site oder Vorschau. Getrennte Verzeichnisse - beide
# gleichen mit "rsync --delete" ab, eine Verwechslung waere also folgenreich.
if [ "$TO_STAGING" = yes ]; then
	[ "${ENABLE_STAGING:-no}" = yes ] || fail "ENABLE_STAGING steht nicht auf yes - es gibt keine Vorschau."
	TARGET="$STAGING_DOC_ROOT"
	TARGET_URL="https://${SITE_NAME}${STAGING_URL_PATH}/"
	step "Vorschau ausrollen"
else
	TARGET="$DOC_ROOT"
	TARGET_URL="https://${SITE_NAME}/"
	step "Oeffentliche Site ausrollen"
fi

info "von:  $SOURCE"
info "nach: $TARGET"
info "Umfang: $(find "$SOURCE" -type f | wc -l) Dateien, $(du -sh "$SOURCE" | cut -f1)"

[ "$DRY_RUN" = yes ] || require_root

# rsync bringt install.sh mit; falls dieses Skript einmal ohne den
# vollstaendigen Durchlauf benutzt wird, hier nachinstallieren.
if ! command -v rsync >/dev/null 2>&1; then
	apt_install rsync
fi

# --- Abgleichen ------------------------------------------------------------

# --chmod=D0755,F0644 ist EIN Argument mit Komma darin - shellcheck haelt das
# fuer eine mit Kommas getrennte Liste.
# shellcheck disable=SC2054
RSYNC_OPTS=(
	--archive
	--delete
	--delete-after          # erst loeschen, wenn alles Neue uebertragen ist

	# Entscheidet nach dem INHALT, nicht nach Groesse und Aenderungszeit.
	# Noetig, weil zwei gleich lange Faellen einer Seite mit derselben
	# Zeitangabe sonst als identisch gelten und die Aenderung nicht ankommt -
	# tar und manche Kopiervorgaenge arbeiten nur sekundengenau.
	--checksum
	--human-readable
	--itemize-changes

	# Zeugs vom Arbeitsrechner und aus der Versionsverwaltung bleibt draussen.
	--exclude=.DS_Store
	--exclude=._*
	--exclude=.git
	--exclude=.gitignore
	--exclude=Thumbs.db
	--exclude='*~'

	# Eigentuemer root, Gruppe www-data: der Webserver darf lesen, nicht
	# schreiben. Ein Fehler im Webserver kann dann keine Seite veraendern.
	--chown=root:www-data
	--chmod=D0755,F0644
)

if [ "$DRY_RUN" = yes ]; then
	info ""
	info "Probelauf - es wird nichts geaendert:"
	rsync "${RSYNC_OPTS[@]}" --dry-run "$SOURCE/" "$TARGET/" | sed 's/^/    /'
	exit 0
fi

mkdir -p "$TARGET"

info ""
rsync "${RSYNC_OPTS[@]}" "$SOURCE/" "$TARGET/" | sed 's/^/    /'

# --chown/--chmod greifen nur bei uebertragenen Dateien; der Rest wird hier
# noch einmal gerade gezogen, damit auch nach einem abgebrochenen Lauf alles
# stimmt.
chown -R root:www-data "$TARGET"
find "$TARGET" -type d -exec chmod 0755 {} +
find "$TARGET" -type f -exec chmod 0644 {} +

ok "Inhalt abgeglichen"

# --- Pruefen ---------------------------------------------------------------

[ -f "$TARGET/index.html" ] || fail "$TARGET/index.html fehlt - der Einstieg wuerde nicht funktionieren."
ok "Einstieg vorhanden: $TARGET/index.html"

for d in de en css js images; do
	[ -d "$TARGET/$d" ] || warn "$TARGET/$d fehlt - war das Quellverzeichnis vollstaendig?"
done

if systemctl is-active --quiet apache2; then
	code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
		--resolve "${SITE_NAME}:443:127.0.0.1" "$TARGET_URL" 2>/dev/null)" || true
	[ -n "$code" ] || code=000
	case "$code" in
		200) ok "$TARGET_URL antwortet mit 200" ;;
		401) ok "$TARGET_URL verlangt eine Anmeldung (401) - so gewollt" ;;
		*)   warn "$TARGET_URL antwortet mit $code - nachsehen in /var/log/apache2/error.log" ;;
	esac

	# Die Sprachweiche der Startseite leitet auf de/index.html weiter.
	code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 \
		--resolve "${SITE_NAME}:443:127.0.0.1" "${TARGET_URL}de/index.html" 2>/dev/null)" || true
	[ -n "$code" ] || code=000
	case "$code" in
		200|401) ok "${TARGET_URL}de/index.html antwortet mit $code" ;;
		*)       warn "${TARGET_URL}de/index.html antwortet mit $code" ;;
	esac
else
	warn "Apache laeuft nicht - erst ./install.sh ausfuehren."
fi

info ""
info "Fertig. Erreichbar unter ${TARGET_URL}"
