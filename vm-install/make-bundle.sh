#!/bin/bash
# ---------------------------------------------------------------------------
# Alles in ein Paket packen, das auf die VM kopiert wird.
#
# Laeuft auf dem ARBEITSRECHNER im dbg-Projekt, nicht auf der VM:
#
#     mvn package                 # erzeugt target/website/
#     vm-install/make-bundle.sh
#
# Ergebnis: dbg-vm-install.tar.gz mit den Installationsskripten, den
# Konfigurationsvorlagen UND dem generierten Site-Inhalt - damit auf der VM
# alles beisammen ist und nichts einzeln nachkopiert werden muss.
#
#     scp dbg-vm-install.tar.gz <benutzer>@<vm>:
#     ssh <benutzer>@<vm>
#     tar xzf dbg-vm-install.tar.gz
#     cd vm-install
#     sudo ./install.sh
#     sudo ./deploy-site.sh
# ---------------------------------------------------------------------------

set -euo pipefail

VM_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$VM_INSTALL_DIR/.." && pwd)"
SITE_SOURCE="${1:-$PROJECT_DIR/target/website}"
OUT="${OUT:-$PROJECT_DIR/dbg-vm-install.tar.gz}"

# shellcheck source=scripts/lib.sh
. "$VM_INSTALL_DIR/scripts/lib.sh"

step "Paket fuer die VM bauen"

if [ ! -f "$SITE_SOURCE/index.html" ]; then
	fail "In $SITE_SOURCE liegt keine index.html. Erst 'mvn package' im Projektverzeichnis ausfuehren (oder das Site-Verzeichnis als Parameter angeben)."
fi

info "Skripte:  $VM_INSTALL_DIR"
info "Inhalt:   $SITE_SOURCE"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/vm-install"

# Die Skripte und Vorlagen. site/ wird ausgelassen und gleich darauf mit dem
# frischen Inhalt gefuellt.
rsync -a \
	--exclude='site/' \
	--exclude='.DS_Store' \
	--exclude='._*' \
	"$VM_INSTALL_DIR/" "$STAGE/vm-install/"

# Der generierte Inhalt.
mkdir -p "$STAGE/vm-install/site"
rsync -a \
	--exclude='.DS_Store' \
	--exclude='._*' \
	"$SITE_SOURCE/" "$STAGE/vm-install/site/"

chmod 0755 "$STAGE/vm-install"/*.sh

# Ohne Zeitstempel und Besitzerangaben, damit zwei Laeufe mit gleichem Inhalt
# auch das gleiche Paket ergeben.
tar czf "$OUT" \
	--owner=0 --group=0 --numeric-owner \
	-C "$STAGE" vm-install

ok "$OUT  ($(du -h "$OUT" | cut -f1))"

cat <<ENDE

Weiter auf der VM:

    scp $(basename "$OUT") <benutzer>@<vm>:
    ssh <benutzer>@<vm>
    tar xzf $(basename "$OUT")
    cd vm-install
    nano config/dbg-vm.conf        # Domain, E-Mail, SSH-Port pruefen
    sudo ./install.sh
    sudo ./deploy-site.sh
ENDE
