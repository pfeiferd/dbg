#!/bin/bash
# ---------------------------------------------------------------------------
# Schritt "firewall": ufw einrichten - herein darf nur, was gebraucht wird.
#
# Offen sind genau drei Dinge:
#   SSH_PORT  Verwaltung
#   80/tcp    Nachweis fuer Let's Encrypt und Weiterleitung auf https
#   443/tcp   die Website
#
# ufw und nicht iptables-persistent wie in den dev-vm-Projekten: auf
# Ubuntu 24.04/26.04 arbeitet der Paketfilter im Kern mit nftables, und ufw
# ist die Oberflaeche, die Ubuntu dafuer mitbringt. fail2ban setzt seine
# Sperren ueber dieselbe Oberflaeche (banaction = ufw), damit sich nicht zwei
# Verwalter in dieselbe Regelkette schreiben.
# ---------------------------------------------------------------------------

step "Firewall einrichten"

apt_install ufw

# --- IPv6 ------------------------------------------------------------------

if [ "$FIREWALL_IPV6" = yes ]; then
	sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
	ok "ufw beruecksichtigt IPv6"
else
	sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
	warn "IPv6 ist in ufw abgeschaltet. Hat die VM eine IPv6-Adresse, ist sie darueber UNGEFILTERT erreichbar."
fi

# --- Grundhaltung: nichts herein, alles heraus -----------------------------
#
# Die Rueckmeldungen von ufw ("Rules updated", "Rules updated (v6)") stehen bei
# jedem einzelnen Aufruf und sagen nichts aus - sie wandern ins Protokoll.

run_logged "ufw default deny incoming"  ufw --force default deny incoming
run_logged "ufw default allow outgoing" ufw --force default allow outgoing
run_logged "ufw default deny routed"    ufw --force default deny routed
ok "Grundhaltung: herein nichts, heraus alles"

# --- Die drei benoetigten Ports --------------------------------------------

# "limit" statt "allow": mehr als sechs Verbindungsversuche in 30 Sekunden von
# derselben Adresse werden abgewiesen. Bremst das Abklopfen, bevor fail2ban
# ueberhaupt etwas zu tun bekommt.
run_logged "ufw limit ${SSH_PORT}/tcp" ufw limit "${SSH_PORT}/tcp" comment 'SSH (Verwaltung)'
ok "Port ${SSH_PORT}/tcp (ssh, mit Begrenzung der Verbindungsrate)"

run_logged "ufw allow 80/tcp"  ufw allow 80/tcp  comment 'http: ACME-Nachweis und Weiterleitung auf https'
run_logged "ufw allow 443/tcp" ufw allow 443/tcp comment 'https: Website'
ok "Ports 80/tcp und 443/tcp"

for extra in $FIREWALL_EXTRA_ALLOW; do
	run_logged "ufw allow $extra" ufw allow "$extra" comment 'FIREWALL_EXTRA_ALLOW aus dbg-vm.conf'
	warn "zusaetzlich geoeffnet: $extra - wieder schliessen mit: ufw delete allow $extra"
done

# --- Einschalten -----------------------------------------------------------
#
# Bestehende Verbindungen bleiben erhalten (die Regelkette laesst
# RELATED,ESTABLISHED durch), die laufende SSH-Sitzung bricht also nicht ab.

if ufw status 2>/dev/null | grep -q '^Status: active'; then
	run_logged "ufw reload" ufw reload || fail "ufw reload ist fehlgeschlagen - Einzelheiten in $INSTALL_LOG"
	ok "ufw war bereits aktiv, Regeln neu geladen"
elif run_logged "ufw enable" ufw --force enable; then
	ok "ufw eingeschaltet"
else
	# Nicht jeder Kern bringt das LOG-Ziel von iptables mit. Bei
	# virtualisierten Wurzelsystemen (LXC/OpenVZ, wie bei manchen guenstigen
	# Anbietern) scheitert ufw dann allein an seinen Protokollregeln - der
	# Paketfilter selbst wuerde arbeiten. Also ohne Protokollierung erneut
	# versuchen, statt die Maschine ungeschuetzt zu lassen.
	warn "ufw liess sich nicht einschalten. Zweiter Versuch ohne Protokollierung der Firewall."
	run_logged "ufw logging off" ufw logging off || true

	if run_logged "ufw enable (ohne logging)" ufw --force enable; then
		ok "ufw eingeschaltet, Protokollierung der Firewall ist aus"
		warn "Der Kern dieser Maschine kann die Protokollregeln von ufw nicht laden"
		warn "(meist ein virtualisiertes Wurzelsystem: LXC/OpenVZ statt echter VM)."
		warn "Der Paketfilter arbeitet, abgewiesene Pakete werden nur nicht protokolliert."
		warn "Wieder einschalten liesse sich das mit: ufw logging low"
	else
		printf '\n'
		warn "ufw bleibt ausgeschaltet - DIE MASCHINE IST UNGEFILTERT ERREICHBAR."
		info "    Einzelheiten:  $INSTALL_LOG"
		info "    Von Hand:      ufw --force enable  bzw.  ufw status verbose"
		fail "Abbruch: ohne Firewall sollte es nicht weitergehen."
	fi
fi

service_enable ufw

info ""
ufw status verbose | sed 's/^/    /'
