#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "base": Grundausstattung des Systems
#
# Paketquellen auffrischen, Zeitzone und Sprachumgebung setzen, die Werkzeuge
# nachziehen, die die folgenden Schritte brauchen, und die automatischen
# Sicherheitsaktualisierungen einschalten.
# ---------------------------------------------------------------------------

step "Grundausstattung des Systems"

apt_update_once

if [ "$RUN_FULL_UPGRADE" = yes ]; then
	info "spiele vorhandene Aktualisierungen ein (dist-upgrade) - das kann dauern"
	run_logged "apt-get dist-upgrade" \
		env DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y -qq \
		|| fail "dist-upgrade ist fehlgeschlagen - Einzelheiten in $INSTALL_LOG"
	ok "System aktualisiert"
else
	info "dist-upgrade uebersprungen (RUN_FULL_UPGRADE=$RUN_FULL_UPGRADE)"
fi

# Werkzeuge, die die weiteren Schritte und der spaetere Betrieb brauchen.
# Absichtlich knapp gehalten: je weniger installiert ist, desto weniger kann
# angegriffen werden.
apt_install \
	ca-certificates \
	curl \
	rsync \
	unzip \
	zip \
	logrotate \
	locales \
	tzdata \
	iproute2 \
	net-tools


# --- Zeitzone --------------------------------------------------------------

if [ "$(timedatectl show --property=Timezone --value 2>/dev/null)" = "$TIMEZONE" ]; then
	info "Zeitzone ist bereits $TIMEZONE"
else
	timedatectl set-timezone "$TIMEZONE"
	ok "Zeitzone auf $TIMEZONE gesetzt"
fi

# Die Uhr muss stimmen, sonst schlaegt die Zertifikatspruefung fehl.
timedatectl set-ntp true 2>/dev/null || warn "Zeitabgleich (NTP) liess sich nicht einschalten - Uhrzeit bitte pruefen."


# --- Sprachumgebung -------------------------------------------------------

if locale -a 2>/dev/null | grep -qi "^${SYSTEM_LOCALE//-/}$\|^${SYSTEM_LOCALE/.UTF-8/.utf8}$"; then
	info "Sprachumgebung $SYSTEM_LOCALE ist bereits vorhanden"
else
	locale-gen "$SYSTEM_LOCALE"
	ok "Sprachumgebung $SYSTEM_LOCALE erzeugt"
fi

# LANG setzen, LC_ALL bewusst nicht - sonst laesst sich in einer Sitzung
# nichts mehr abweichend einstellen.
update-locale LANG="$SYSTEM_LOCALE"
ok "LANG=$SYSTEM_LOCALE"


# --- Netzwerk-Haertung -----------------------------------------------------

copy_file etc/sysctl.d/90-dbg-hardening.conf /etc/sysctl.d/90-dbg-hardening.conf
sysctl --quiet --system
ok "sysctl-Einstellungen aktiv"


# --- Automatische Sicherheitsaktualisierungen ------------------------------

if [ "$ENABLE_UNATTENDED_UPGRADES" = yes ]; then
	apt_install unattended-upgrades apt-listchanges
	render etc/apt/apt.conf.d/52-dbg-unattended-upgrades /etc/apt/apt.conf.d/52-dbg-unattended-upgrades
	service_enable unattended-upgrades
	systemctl restart unattended-upgrades 2>/dev/null || true
	ok "automatische Sicherheitsaktualisierungen eingeschaltet (Neustart falls noetig um 04:30)"
	info "Probelauf jederzeit mit: unattended-upgrade --dry-run --debug"
else
	info "automatische Aktualisierungen nicht eingeschaltet (ENABLE_UNATTENDED_UPGRADES=$ENABLE_UNATTENDED_UPGRADES)"
fi
