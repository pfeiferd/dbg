#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "deploy": Zugang fuer GitHub Actions einrichten.
#
# Wie die Site von GitHub auf die VM kommt - und warum so:
#
#   Ein eigener Benutzer (DEPLOY_USER) mit einem eigenen SSH-Schluessel. In
#   seiner authorized_keys steht der Schluessel mit einem ERZWUNGENEN BEFEHL:
#   egal was der Aufrufer verlangt, es laeuft immer /usr/local/sbin/
#   dbg-receive-site. Dazu "restrict" - keine Shell, kein Terminal, keine
#   Weiterleitung von Ports.
#
#   Wer diesen Schluessel in die Hand bekaeme, koennte damit also nur eine
#   Site abliefern (oder "status"/"rollback" aufrufen), nichts weiter. Kein
#   zusaetzlicher Port, kein Passwort, kein FTP, kein Webhook, der auf einen
#   offenen Port wartet: es bleibt beim SSH-Port, der ohnehin schon offen ist.
#
#   Der private Schluessel liegt bei GitHub als Secret, nicht auf der VM.
# ---------------------------------------------------------------------------

step "Zugang fuer GitHub Actions einrichten"

if [ "${ENABLE_GITHUB_DEPLOY:-yes}" != yes ]; then
	info "uebersprungen (ENABLE_GITHUB_DEPLOY=${ENABLE_GITHUB_DEPLOY:-})"
	return 0 2>/dev/null || exit 0
fi

DEPLOY_HOME="/var/lib/dbg-deploy"
DEPLOY_WORK="/var/lib/dbg-site-deploy"
DEPLOY_KEY_OUT="/root/dbg-deploy-github"

apt_install rsync curl openssh-client


# --- Benutzer --------------------------------------------------------------

if id "$DEPLOY_USER" >/dev/null 2>&1; then
	info "Benutzer $DEPLOY_USER ist vorhanden"
else
	# --system: kein regulaeres Konto, keine Zaehlung bei den Anmeldungen.
	# Eine Shell braucht er trotzdem - sshd startet den erzwungenen Befehl
	# darueber. Mit /usr/sbin/nologin wuerde die Auslieferung scheitern.
	useradd --system --create-home --home-dir "$DEPLOY_HOME" \
		--shell /bin/bash --comment "Auslieferung der Site aus GitHub Actions" \
		"$DEPLOY_USER"
	ok "Benutzer $DEPLOY_USER angelegt (Heimatverzeichnis $DEPLOY_HOME)"
fi

# Kein Passwort - der Zugang geht ausschliesslich ueber den Schluessel.
passwd -l "$DEPLOY_USER" >/dev/null 2>&1 || true

# Heimatverzeichnis und .ssh gehoeren root, nicht dem Benutzer selbst. sshd
# nimmt das (StrictModes verlangt nur: Eigentuemer root oder der Benutzer, und
# fuer andere nicht schreibbar) - und der Auslieferungsbenutzer kann damit
# seinen eigenen Zugang nicht veraendern, also auch keinen weiteren Schluessel
# oder einen anderen erzwungenen Befehl eintragen.
mkdir -p "$DEPLOY_HOME/.ssh"
chown root:root "$DEPLOY_HOME" "$DEPLOY_HOME/.ssh"
chmod 0755 "$DEPLOY_HOME"
chmod 0755 "$DEPLOY_HOME/.ssh"

# Das Archiv wird hier ausgepackt und geprueft - nur fuer root zugaenglich.
mkdir -p "$DEPLOY_WORK"
chown root:root "$DEPLOY_WORK"
chmod 0700 "$DEPLOY_WORK"


# --- Empfaenger und sudo-Regel ---------------------------------------------

render usr/local/sbin/dbg-receive-site /usr/local/sbin/dbg-receive-site 0755
render etc/sudoers.d/dbg-deploy /etc/sudoers.d/dbg-deploy 0440

# Eine fehlerhafte sudoers-Datei macht sudo fuer ALLE unbenutzbar - deshalb
# pruefen und im Zweifel wieder entfernen.
if visudo -cf /etc/sudoers.d/dbg-deploy >/dev/null 2>&1; then
	ok "sudo-Regel geprueft (visudo -c)"
else
	rm -f /etc/sudoers.d/dbg-deploy
	fail "Die erzeugte sudoers-Datei ist fehlerhaft und wurde wieder entfernt."
fi

touch /var/log/dbg-deploy.log
chmod 0640 /var/log/dbg-deploy.log
chown root:adm /var/log/dbg-deploy.log


# --- Schluessel ------------------------------------------------------------

if [ -n "${DEPLOY_SSH_PUBKEY:-}" ]; then
	case "$DEPLOY_SSH_PUBKEY" in
		ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-*\ *|sk-ssh-*\ *)
			PUBKEY="$DEPLOY_SSH_PUBKEY" ;;
		*)
			fail "DEPLOY_SSH_PUBKEY sieht nicht wie ein oeffentlicher SSH-Schluessel aus (erwartet wird z.B. 'ssh-ed25519 AAAA...')." ;;
	esac
	info "oeffentlicher Schluessel aus der Konfiguration uebernommen"

elif [ -s "$DEPLOY_KEY_OUT.pub" ]; then
	PUBKEY="$(cat "$DEPLOY_KEY_OUT.pub")"
	info "Schluesselpaar aus einem frueheren Lauf wiederverwendet ($DEPLOY_KEY_OUT)"

else
	# Keiner angegeben, keiner vorhanden: eines erzeugen. Der private Teil
	# landet unter /root und ist von dort in das GitHub-Secret zu kopieren -
	# danach kann er auf der VM geloescht werden.
	ssh-keygen -t ed25519 -N '' -C "github-actions@${SITE_NAME}" -f "$DEPLOY_KEY_OUT" >/dev/null
	chmod 0600 "$DEPLOY_KEY_OUT"
	chmod 0644 "$DEPLOY_KEY_OUT.pub"
	PUBKEY="$(cat "$DEPLOY_KEY_OUT.pub")"
	ok "Schluesselpaar erzeugt: $DEPLOY_KEY_OUT"
	NEW_KEY=yes
fi

# Der erzwungene Befehl ist der eigentliche Schutz: der Schluessel kann nichts
# anderes starten. "restrict" nimmt zusaetzlich Terminal, Portweiterleitung,
# Agentenweiterleitung und X11 weg.
AUTHORIZED_LINE="restrict,command=\"sudo -n /usr/local/sbin/dbg-receive-site\" $PUBKEY"

tmp="$(mktemp)"
{
	printf '# Auslieferung der Site aus GitHub Actions.\n'
	printf '# Erzeugt von vm-install/scripts/90-deploy.sh - nicht von Hand aendern.\n'
	printf '#\n'
	printf '# Der erzwungene Befehl (command="...") laesst diesem Schluessel nur eine\n'
	printf '# einzige Moeglichkeit: ein Site-Archiv abliefern. Keine Shell, kein\n'
	printf '# Dateizugriff, keine Portweiterleitung.\n'
	printf '%s\n' "$AUTHORIZED_LINE"
} > "$tmp"

install_file "$tmp" "$DEPLOY_HOME/.ssh/authorized_keys" 0644
rm -f "$tmp"
chown root:root "$DEPLOY_HOME/.ssh/authorized_keys"
ok "Schluessel eingetragen, auf den Empfaenger festgelegt"


# --- Darf der Benutzer ueberhaupt per ssh herein? --------------------------

if [ -n "${SSH_ALLOW_USERS:-}" ]; then
	case " $SSH_ALLOW_USERS " in
		*" $DEPLOY_USER "*)
			ok "$DEPLOY_USER steht in SSH_ALLOW_USERS" ;;
		*)
			warn "SSH_ALLOW_USERS ist gesetzt, enthaelt aber $DEPLOY_USER nicht - die Auslieferung wuerde abgewiesen."
			warn "In config/dbg-vm.conf ergaenzen und 'sudo ./install.sh --only ssh' erneut laufen lassen." ;;
	esac
fi

# --- Was bei GitHub einzutragen ist ----------------------------------------

info ""
info "Die Werte fuer die GitHub-Secrets zeigt:"
info "    sudo ./show-deploy-secrets.sh"

if [ "${NEW_KEY:-no}" = yes ]; then
	warn "Ein neues Schluesselpaar wurde erzeugt. Der private Teil liegt in"
	warn "$DEPLOY_KEY_OUT - ihn in das GitHub-Secret VM_SSH_KEY kopieren und"
	warn "danach auf der VM loeschen:  shred -u $DEPLOY_KEY_OUT"
fi
