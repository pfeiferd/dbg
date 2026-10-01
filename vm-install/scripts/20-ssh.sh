#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "ssh": SSH-Daemon haerten und, wenn gewuenscht, auf einen anderen
# Port legen.
#
# Zwei Dinge sind hier wichtig und der Grund, warum das Skript mehr tut als
# eine Datei zu kopieren:
#
# 1) Ubuntu 24.04 und neuer startet sshd ueber eine Socket-Unit (ssh.socket).
#    Dann horcht systemd auf dem Port, nicht sshd - die Zeile "Port" in der
#    sshd-Konfiguration bleibt in diesem Fall ohne Wirkung. Der Port muss
#    zusaetzlich in der Socket-Unit gesetzt werden.
#
# 2) Die Passwort-Anmeldung abzuschalten, ohne dass ein Schluessel hinterlegt
#    ist, sperrt den Zugang zur VM dauerhaft. Bei SSH_DISABLE_PASSWORD_AUTH=auto
#    sieht das Skript deshalb erst nach, ob ueberhaupt ein Schluessel vorliegt.
# ---------------------------------------------------------------------------

step "SSH haerten"

apt_install openssh-server

# --- Liegt ein SSH-Schluessel vor? -----------------------------------------

count_authorized_keys() {
	local total=0 file n
	while IFS= read -r file; do
		[ -r "$file" ] || continue
		# grep -c schreibt die Zahl nach stdout und endet mit 1, wenn es
		# keinen Treffer gab - daher der Rueckfall auf 0.
		n="$(grep -cE '^[[:space:]]*(ssh-|ecdsa-|sk-)' "$file" 2>/dev/null)" || n=0
		total=$((total + n))
	done < <(
		printf '%s\n' /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys
		# Von cloud-init gesetzte Schluessel liegen gelegentlich nur hier.
		printf '%s\n' /etc/ssh/authorized_keys.d/* 2>/dev/null
	)
	printf '%s' "$total"
}

KEY_COUNT="$(count_authorized_keys)"
info "hinterlegte SSH-Schluessel: $KEY_COUNT"

# SSH_PASSWORD_AUTH_EFFECTIVE und SSH_ALLOW_USERS_DIRECTIVE liest
# placeholder_value() in scripts/lib.sh ein, wenn die Vorlage eingesetzt wird.
# shellcheck disable=SC2034
case "$SSH_DISABLE_PASSWORD_AUTH" in
	yes)
		SSH_PASSWORD_AUTH_EFFECTIVE=no
		[ "$KEY_COUNT" -gt 0 ] || warn "SSH_DISABLE_PASSWORD_AUTH=yes, aber es ist KEIN Schluessel hinterlegt. Nach dem Beenden der laufenden Sitzung ist kein SSH-Zugang mehr moeglich!"
		;;
	no)
		SSH_PASSWORD_AUTH_EFFECTIVE=yes
		;;
	auto)
		if [ "$KEY_COUNT" -gt 0 ]; then
			SSH_PASSWORD_AUTH_EFFECTIVE=no
			ok "Passwort-Anmeldung wird abgeschaltet (es sind Schluessel hinterlegt)"
		else
			SSH_PASSWORD_AUTH_EFFECTIVE=yes
			warn "Kein SSH-Schluessel gefunden - die Passwort-Anmeldung bleibt eingeschaltet."
			warn "Schluessel hinterlegen (ssh-copy-id), dann 'sudo ./install.sh --only ssh' erneut laufen lassen."
		fi
		;;
	*)
		fail "SSH_DISABLE_PASSWORD_AUTH muss yes, no oder auto sein (ist: $SSH_DISABLE_PASSWORD_AUTH)"
		;;
esac

# shellcheck disable=SC2034
if [ -n "$SSH_ALLOW_USERS" ]; then
	SSH_ALLOW_USERS_DIRECTIVE="AllowUsers $SSH_ALLOW_USERS"
else
	SSH_ALLOW_USERS_DIRECTIVE="# AllowUsers - keine Beschraenkung (SSH_ALLOW_USERS ist leer)"
fi


# --- Konfiguration ablegen -------------------------------------------------

render etc/ssh/sshd_config.d/10-dbg-hardening.conf /etc/ssh/sshd_config.d/10-dbg-hardening.conf

# Sicherstellen, dass die Hauptdatei das Verzeichnis ueberhaupt einliest.
if ! grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
	warn "/etc/ssh/sshd_config liest sshd_config.d nicht ein - ergaenze die Include-Zeile am Dateianfang."
	mkdir -p "$BACKUP_DIR"
	cp -p /etc/ssh/sshd_config "$BACKUP_DIR/etc_ssh_sshd_config"
	sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
fi

# Auf Cloud-Abbildern hebelt eine von cloud-init abgelegte Datei die eigenen
# Einstellungen gern wieder aus - sie wird vor der unseren eingelesen, und bei
# sshd gewinnt der erste Treffer.
for f in /etc/ssh/sshd_config.d/*.conf; do
	[ -e "$f" ] || continue
	case "$f" in */10-dbg-hardening.conf) continue ;; esac
	if grep -qE '^[[:space:]]*(PasswordAuthentication|PermitRootLogin|Port)' "$f"; then
		case "$(basename "$f")" in
			0*|1*)
				warn "$f setzt Port/PermitRootLogin/PasswordAuthentication und wird VOR unserer Datei gelesen - dort gewinnt der erste Treffer."
				info "    Inhalt pruefen mit: grep -nE 'Port|PermitRootLogin|PasswordAuthentication' $f"
				;;
			*)
				info "$f enthaelt eigene Angaben, wird aber nach 10-dbg-hardening.conf gelesen - unsere Werte gewinnen."
				;;
		esac
	fi
done


# --- Port in der Socket-Unit (Ubuntu 24.04+) -------------------------------

SSH_SOCKET_ACTIVATED=no
if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
	SSH_SOCKET_ACTIVATED=yes
fi

if [ "$SSH_SOCKET_ACTIVATED" = yes ]; then
	info "sshd wird ueber ssh.socket gestartet - Port zusaetzlich dort setzen"
	mkdir -p /etc/systemd/system/ssh.socket.d
	tmp="$(mktemp)"
	cat > "$tmp" <<-UNIT
		# Erzeugt von vm-install/scripts/20-ssh.sh
		#
		# Ab Ubuntu 24.04 wird sshd ueber eine Socket-Unit gestartet: systemd
		# nimmt die Verbindung an, nicht sshd. Die Zeile "Port" in
		# sshd_config.d bleibt deshalb wirkungslos; der Port muss hier stehen.
		#
		# Das leere ListenStream= loescht zuerst die Voreinstellungen. Danach
		# ZWEI Zeilen, eine je Adressfamilie - genau wie in der ausgelieferten
		# ssh.socket. Das ist kein Schoenheitsfehler: dort steht
		# "BindIPv6Only=ipv6-only", der IPv6-Socket nimmt also keine
		# IPv4-Verbindungen mit an. Ein einzelnes "ListenStream=${SSH_PORT}"
		# wuerde nur auf [::] horchen - jede Anmeldung ueber IPv4 bekaeme
		# "Connection refused", und die VM waere faktisch ausgesperrt.
		[Socket]
		ListenStream=
		ListenStream=0.0.0.0:${SSH_PORT}
		ListenStream=[::]:${SSH_PORT}
	UNIT
	install_file "$tmp" /etc/systemd/system/ssh.socket.d/10-dbg-port.conf
	rm -f "$tmp"
	systemctl daemon-reload
fi


# --- Pruefen, dann uebernehmen ---------------------------------------------

# sshd verlangt sein Verzeichnis zur Rechtetrennung, sonst scheitert schon die
# Pruefung. Normalerweise legt systemd-tmpfiles es beim Hochfahren an - laeuft
# die Installation vor dem ersten Start von ssh, ist es noch nicht da.
if [ ! -d /run/sshd ]; then
	mkdir -p /run/sshd
	chmod 0755 /run/sshd
	systemd-tmpfiles --create /usr/lib/tmpfiles.d/sshd.conf >/dev/null 2>&1 || true
fi

if ! sshd -t; then
	fail "Die SSH-Konfiguration ist fehlerhaft - es wird nichts neu gestartet, der Zugang bleibt wie er ist."
fi
ok "Konfiguration geprueft (sshd -t)"

# Vor dem Umschalten des Ports muss die Firewall ihn schon durchlassen,
# sonst ist die VM nach dem Neustart des Dienstes nicht mehr erreichbar.
# Deshalb laeuft Schritt "firewall" direkt nach diesem - und offene
# Verbindungen bleiben in beiden Faellen bestehen.
if [ "$SSH_SOCKET_ACTIVATED" = yes ]; then
	systemctl restart ssh.socket
	systemctl restart ssh 2>/dev/null || true
else
	systemctl restart ssh
fi

sleep 1

# Nicht "horcht irgendwo", sondern: kommt eine Verbindung zustande? Und zwar je
# Adressfamilie getrennt. Ein Socket, der nur auf [::] horcht, sieht in
# "ss -tlnp" richtig aus, weist IPv4-Anmeldungen aber ab.
ssh_reachable() {
	timeout 3 bash -c "exec 3<>/dev/tcp/$1/${SSH_PORT}" 2>/dev/null
}

if ssh_reachable 127.0.0.1; then
	ok "sshd nimmt Verbindungen auf Port $SSH_PORT an (IPv4)"
else
	warn "Port $SSH_PORT nimmt ueber IPv4 keine Verbindung an. Die laufende Sitzung NICHT beenden!"
	info "    systemctl status ssh ssh.socket"
	info "    ss -tlnp | grep ssh"
	info "    systemctl cat ssh.socket | grep ListenStream"
fi

# IPv6 nur pruefen, wenn die Maschine ueberhaupt eine IPv6-Adresse hat.
if ip -6 addr show scope global 2>/dev/null | grep -q inet6; then
	if ssh_reachable ::1; then
		ok "sshd nimmt Verbindungen auf Port $SSH_PORT an (IPv6)"
	else
		warn "Port $SSH_PORT nimmt ueber IPv6 keine Verbindung an, obwohl die Maschine IPv6 hat."
	fi
else
	info "keine globale IPv6-Adresse - IPv6 nicht geprueft"
fi

if [ "$SSH_PORT" != "22" ]; then
	info ""
	info "Nachher in einem ZWEITEN Terminal pruefen, solange diese Sitzung offen bleibt:"
	info "    ssh -p $SSH_PORT <benutzer>@${SITE_NAME}"
fi
