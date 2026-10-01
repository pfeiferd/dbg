#!/bin/bash
# ---------------------------------------------------------------------------
# Zeigt die Werte, die bei GitHub als Secrets einzutragen sind.
#
# Auf der VM aufrufen:
#
#     sudo ./show-deploy-secrets.sh
#
# Einzutragen unter:  Repository > Settings > Secrets and variables >
#                     Actions > New repository secret
#
# ACHTUNG: Der private Schluessel wird dabei auf dem Bildschirm ausgegeben.
# Nicht in einer mitgeschnittenen Sitzung aufrufen und das Terminalfenster
# danach schliessen.
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

: "${DEPLOY_USER:=dbg-deploy}"
DEPLOY_KEY_OUT=/root/dbg-deploy-github

require_root

step "GitHub-Secrets fuer die Auslieferung"

# Die oeffentliche Adresse dieser VM - fuer VM_HOST. Der Name ist besser als
# die IP-Adresse, solange er auf diese Maschine zeigt.
public_ip="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"

cat <<KOPF

Diese fuenf Secrets im GitHub-Repository anlegen
(Settings > Secrets and variables > Actions > New repository secret):

KOPF

printf '  %-18s %s\n' "VM_HOST" "$SITE_NAME"
[ -n "$public_ip" ] && printf '  %-18s (oeffentliche Adresse dieser VM: %s)\n' "" "$public_ip"
printf '  %-18s %s\n' "VM_PORT" "$SSH_PORT"
printf '  %-18s %s\n' "VM_USER" "$DEPLOY_USER"

printf '\n  %-18s siehe unten (mehrzeilig, vollstaendig einfuegen)\n' "VM_KNOWN_HOSTS"
printf '  %-18s siehe unten (mehrzeilig, vollstaendig einfuegen)\n' "VM_SSH_KEY"

# --- known_hosts -----------------------------------------------------------

printf '\n'
step "VM_KNOWN_HOSTS"
cat <<'ERKL'
Der Fingerabdruck dieser VM. Damit prueft der Build, dass er wirklich mit
dieser Maschine spricht - und nicht mit irgendeiner, die sich dazwischen
gedraengt hat. Ohne diesen Wert bliebe nur "StrictHostKeyChecking=no", und
damit waere der Schluessel bei einem umgeleiteten Namen preisgegeben.

ERKL

# ACHTUNG: die Werte stehen ohne Einrueckung da - fuehrende Leerzeichen wuerden
# mitkopiert und den Schluessel unbrauchbar machen. Alles ZWISCHEN den
# Markierungszeilen einfuegen, die Markierungen selbst nicht.
if command -v ssh-keyscan >/dev/null 2>&1; then
	printf -- '----- ab hier kopieren -----\n'
	# Von der VM selbst abgefragt: hier ist der Schluessel garantiert echt. Der
	# Name wird eingesetzt, weil der Build die VM unter ihrem Namen anspricht,
	# nicht unter 127.0.0.1.
	if [ "$SSH_PORT" = 22 ]; then
		ssh-keyscan -t ssh-ed25519,ecdsa-sha2-nistp256,rsa 127.0.0.1 2>/dev/null \
			| sed "s|^127\.0\.0\.1|${SITE_NAME}|" || true
	else
		# Bei einem anderen Port verlangt known_hosts die Form [name]:port.
		ssh-keyscan -p "$SSH_PORT" -t ssh-ed25519,ecdsa-sha2-nistp256,rsa 127.0.0.1 2>/dev/null \
			| sed "s|^\[127\.0\.0\.1\]:${SSH_PORT}|[${SITE_NAME}]:${SSH_PORT}|" || true
	fi
	printf -- '----- bis hier kopieren -----\n'
else
	warn "ssh-keyscan ist nicht vorhanden (Paket openssh-client)."
fi

# --- privater Schluessel ---------------------------------------------------

printf '\n'
step "VM_SSH_KEY"

if [ -s "$DEPLOY_KEY_OUT" ]; then
	cat <<ERKL
Der private Schluessel, mit dem der Build sich anmeldet. Vollstaendig
einfuegen, mit der Zeile "-----BEGIN..." und der Zeile "-----END...", und
OHNE fuehrende Leerzeichen - sonst ist er unbrauchbar.

Danach auf der VM loeschen - GitHub hat ihn dann, hier wird er nicht gebraucht:
    shred -u $DEPLOY_KEY_OUT

ERKL
	printf -- '----- ab hier kopieren -----\n'
	cat "$DEPLOY_KEY_OUT"
	printf -- '----- bis hier kopieren -----\n'
elif [ -n "${DEPLOY_SSH_PUBKEY:-}" ]; then
	cat <<ERKL
In der Konfiguration ist ein oeffentlicher Schluessel eingetragen
(DEPLOY_SSH_PUBKEY), das Schluesselpaar ist also auf einem anderen Rechner
entstanden. Der private Teil liegt dort - diese VM hat ihn nie gesehen, was
genau richtig ist.

ERKL
else
	warn "Weder /root/dbg-deploy-github noch DEPLOY_SSH_PUBKEY gefunden."
	info "Erst den Schritt 'deploy' laufen lassen:  sudo ./install.sh --only deploy"
fi

# --- Gegenprobe ------------------------------------------------------------

printf '\n'
step "Gegenprobe"

authorized="/var/lib/dbg-deploy/.ssh/authorized_keys"
if [ -s "$authorized" ]; then
	ok "$authorized ist vorhanden"
	if grep -q 'command="sudo -n /usr/local/sbin/dbg-receive-site"' "$authorized"; then
		ok "der Schluessel ist auf den Empfaenger festgelegt (erzwungener Befehl)"
	else
		warn "im Schluesseleintrag fehlt der erzwungene Befehl - 'sudo ./install.sh --only deploy' erneut laufen lassen"
	fi
else
	warn "$authorized fehlt - 'sudo ./install.sh --only deploy' laufen lassen"
fi

[ -x /usr/local/sbin/dbg-receive-site ] \
	&& ok "/usr/local/sbin/dbg-receive-site ist vorhanden" \
	|| warn "/usr/local/sbin/dbg-receive-site fehlt"

visudo -cf /etc/sudoers.d/dbg-deploy >/dev/null 2>&1 \
	&& ok "/etc/sudoers.d/dbg-deploy ist gueltig" \
	|| warn "/etc/sudoers.d/dbg-deploy fehlt oder ist fehlerhaft"

cat <<ENDE

Danach von Hand ausprobieren (vom eigenen Rechner, mit dem privaten
Schluessel) - das geht auch ohne GitHub:

    ssh -i dbg-deploy -p ${SSH_PORT} ${DEPLOY_USER}@${SITE_NAME} status

Das muss den Zustand der Site zeigen. Kommt stattdessen eine Shell, ist der
erzwungene Befehl nicht aktiv - dann nicht weitermachen.

ENDE
