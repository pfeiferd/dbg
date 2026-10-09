# vm-install – die DBG-Website-VM aufsetzen und beliefern

Installiert auf einer frischen **Ubuntu 24.04 LTS** oder **26.04 LTS** alles, was
die generierte Site braucht: einen gehärteten Apache mit https, fail2ban und
eine Firewall, die nur SSH, 80 und 443 durchlässt. Dazu den Zugang, über den
GitHub Actions die fertige Site nach einem Build auf `main` hierher schiebt.

Aufbau wie in den `dev-vm`-Projekten: ein Treiberskript, darunter einzelne
Schritte, und daneben die Konfigurationsdateien als Vorlagen mit Platzhaltern
in spitzen Klammern. Alles andere ist auf diese Site zugeschnitten – kein
Tomcat, keine Datenbank, kein mod_jk, kein Backup (ausdrücklich nicht
gewünscht; der Inhalt entsteht jederzeit neu aus `content/`).

## Der Weg der Inhalte

```
       ┌──────────── Zweig "staging" ───────────┐
Checkin│                                        │ Build auf GitHub
       └──▶ https://<site>/staging/  ───────────┘   eigenes Verzeichnis,
            Vorschau, noindex                       öffentliche Site unberührt

                        │ zufrieden? staging ──▶ main mergen
                        ▼
       ┌──────────── Zweig "main" ──────────────┐
 Merge │                                        │ Build auf GitHub
       └──▶ https://<site>/  ───────────────────┘   die öffentliche Site
```

* **`staging`** – jeder Checkin landet unter `/staging/` auf derselben VM:
  gleicher Apache, gleiches Zertifikat, gleiche Kopfzeilen. Die Vorschau
  verhält sich damit genau wie das Original.
* **`main`** – ein Merge dorthin liefert auf die öffentliche Site aus.
* **Pull Requests** werden nur gebaut, nicht ausgeliefert.

Beide bekommen **dasselbe Archiv**, Bit für Bit. Was in der Vorschau abgenommen
wird, geht unverändert live – es wird nicht nachträglich eine Datei angefasst.

Die Abläufe liegen in `../.github/`:

| Datei | wann | was |
|-------|------|-----|
| `workflows/build.yml` | wird aufgerufen | baut die Site, legt `site.tar.gz` ab |
| `workflows/staging.yml` | Checkin auf `staging`, Pull Request | Vorschau nach `/staging/` |
| `workflows/live.yml` | Checkin/Merge auf `main` | die öffentliche Site |
| `actions/deploy-to-vm/` | von beiden benutzt | der Weg über ssh zur VM |

## Erstmalige Einrichtung

### 1. VM aufsetzen

Auf dem Arbeitsrechner, im Projektverzeichnis `dbg`:

```bash
mvn package                  # erzeugt target/website/
vm-install/make-bundle.sh    # packt Skripte + Inhalt in dbg-vm-install.tar.gz
scp dbg-vm-install.tar.gz <benutzer>@<vm>:
```

Auf der VM:

```bash
tar xzf dbg-vm-install.tar.gz
cd vm-install
nano config/dbg-vm.conf      # Domain, E-Mail, SSH-Port prüfen
sudo ./install.sh
sudo ./deploy-site.sh        # einmal von Hand, damit sofort etwas steht
```

### 2. GitHub einrichten

Auf der VM die Werte anzeigen lassen:

```bash
sudo ./show-deploy-secrets.sh
```

Diese fünf **Secrets** im Repository anlegen (Settings → Secrets and variables
→ Actions → New repository secret):

| Secret | Inhalt |
|--------|--------|
| `VM_HOST` | Name oder IP-Adresse der VM |
| `VM_PORT` | SSH-Port (`SSH_PORT` aus `dbg-vm.conf`) |
| `VM_USER` | Auslieferungsbenutzer, Vorgabe `dbg-deploy` |
| `VM_SSH_KEY` | privater Schlüssel, vollständig mit BEGIN/END-Zeile |
| `VM_KNOWN_HOSTS` | Fingerabdruck der VM, aus `ssh-keyscan` |

Dieselben Secrets gelten für `staging.yml` und `live.yml` – es ist derselbe
Zugang, nur ein anderes Ziel.

Dazu zwei **Variablen** (gleiche Seite, Reiter *Variables*) – nur für die
Verknüpfungen, die GitHub an den Auslieferungen anzeigt:

| Variable | Inhalt |
|----------|--------|
| `SITE_URL` | `https://www.borreliose-gesellschaft.de/` |
| `STAGING_URL` | `https://www.borreliose-gesellschaft.de/staging/` |

Und, falls das Repository `site-gen` privat ist, ein Secret `ENGINE_TOKEN` mit
Leserecht („Contents: read").

Außerdem einmalig:

* den Zweig `staging` anlegen: `git switch -c staging && git push -u origin staging`
* `main` schützen, damit nichts versehentlich live geht: Settings → Branches →
  Rule für `main`, *Require a pull request before merging*
* GitHub Pages wird **nicht** mehr gebraucht: Settings → Pages → Source auf
  *None*, falls es vorher eingeschaltet war

### 3. Ausprobieren, bevor man sich darauf verlässt

Vom eigenen Rechner, mit dem privaten Schlüssel – das geht ohne GitHub:

```bash
ssh -i dbg-deploy -p <port> dbg-deploy@<vm> status
```

Das muss den Zustand der Site zeigen. **Kommt stattdessen eine Shell, ist der
erzwungene Befehl nicht aktiv – dann nicht weitermachen.**

## Wie die Auslieferung funktioniert – und warum ohne extra Port

```
tar czf - -C site . | ssh dbg-deploy@<vm>
```

In der `authorized_keys` des Auslieferungsbenutzers steht der Schlüssel mit
einem **erzwungenen Befehl**:

```
restrict,command="sudo -n /usr/local/sbin/dbg-receive-site" ssh-ed25519 AAAA...
```

Egal was der Aufrufer verlangt – es läuft immer nur dieses eine Programm. Es
nimmt das Archiv auf der Standardeingabe entgegen, prüft es und schaltet die
Site um. `restrict` nimmt zusätzlich Terminal, Port- und Agentenweiterleitung
weg. Wer diesen Schlüssel in die Hand bekäme, könnte damit also eine Site
abliefern – und sonst nichts.

Daraus folgt die Antwort auf die Frage nach Port und Passwort: **es braucht
beides nicht.** Kein FTP, kein SFTP-Konto, kein Webhook, der auf einem offenen
Port wartet, kein zusätzlicher Dienst. Es läuft über den SSH-Port, der für die
Verwaltung ohnehin offen ist, und über ein Schlüsselpaar statt eines Passworts.
Der private Schlüssel liegt als Secret bei GitHub; auf der VM liegt nur der
öffentliche.

Diese Befehle kann der Schlüssel auslösen, und nur diese:

```bash
ssh -p <port> dbg-deploy@<vm>                    # Archiv -> öffentliche Site
ssh -p <port> dbg-deploy@<vm> deploy-staging     # Archiv -> Vorschau
ssh -p <port> dbg-deploy@<vm> status             # Zustand beider Ziele
ssh -p <port> dbg-deploy@<vm> rollback           # Site eine Fassung zurück
ssh -p <port> dbg-deploy@<vm> rollback-staging   # Vorschau eine Fassung zurück
```

Alles andere wird abgewiesen – auch der Versuch, eine Shell oder einen Befehl
unterzuschieben.

`rollback` schaltet auf die Fassung davor zurück; jedes Ziel hebt dafür eine
Fassung auf, getrennt voneinander. Kein Backup im eigentlichen Sinn (die Site
ist jederzeit neu zu bauen), sondern ein kurzer Weg zurück, wenn ein Build etwas
kaputt gemacht hat. Ein weiterer Aufruf kehrt es wieder um.

## Die Vorschau unter /staging/

Eigenes Verzeichnis, per `Alias` eingehängt:

| | |
|--|--|
| Adresse | `https://<SITE_NAME>/staging/` (`STAGING_URL_PATH`) |
| Verzeichnis | `/var/www/dbg-staging` (`STAGING_DOC_ROOT`) |
| Apache | `files/etc/apache2/conf-available/dbg-staging.conf` |

Drei Entscheidungen daran sind nicht beliebig:

**Das Verzeichnis liegt neben dem DocumentRoot, nicht darunter.** Beide
Auslieferungen gleichen mit `rsync --delete` ab. Läge die Vorschau unter
`/var/www/dbg/staging`, würde die nächste Auslieferung der öffentlichen Site sie
als „nicht mehr vorhanden" ansehen und löschen. `install.sh` bricht deshalb ab,
wenn `STAGING_DOC_ROOT` unter `DOC_ROOT` liegt, und `--only verify` prüft es
noch einmal.

**Ein Pfad, keine Unterdomain.** Eine Unterdomain `staging.…` bräuchte einen
DNS-Eintrag und ein eigenes Zertifikat – und Let's Encrypt trägt jeden
ausgestellten Namen in die **Certificate-Transparency-Logs** ein, die öffentlich
durchsuchbar sind (crt.sh). Der Name wäre also binnen Minuten bekannt. Ein Pfad
unter dem bestehenden Zertifikat taucht dort nicht auf.

**`noindex` als Kopfzeile, nicht über robots.txt.** Ein `Disallow: /staging/` in
der robots.txt würde den Pfad gerade verraten – die Datei ist öffentlich lesbar.
Stattdessen schickt Apache für diesen Pfad

```
X-Robots-Tag: noindex, nofollow, noarchive, nosnippet
```

Das wirkt auch für PDFs und Bilder (ein `<meta>` im HTML nicht) und löst
gleichzeitig das Problem mit doppelten Inhalten: ohne diesen Kopf würden
Vorschau und öffentliche Site mit fast demselben Text bei der Bewertung
gegeneinander arbeiten. Zusätzlich bekommt der Pfad `Cache-Control: no-store`,
damit man nach einem Checkin nicht den alten Stand sieht.

Die Vorschau ist **offen erreichbar** – wer die Adresse kennt, sieht sie. Das ist
so gewollt. Wenn doch eine Anmeldung davor soll, in `config/dbg-vm.conf`:

```bash
STAGING_BASIC_AUTH_USERS="vorstand:geheim1
redaktion:geheim2"
```

und `sudo ./install.sh --only site`. Später einen Benutzer nachtragen:
`sudo htpasswd /etc/apache2/dbg-staging.htpasswd <name>`.

Von Hand lässt sich die Vorschau auch direkt befüllen:

```bash
sudo ./deploy-site.sh --staging /tmp/website
```



### Was der Empfänger prüft, bevor er umschaltet

Ein halb gebautes Archiv darf die laufende Site nicht ersetzen. Abgewiesen wird
es, wenn

* es kein lesbares `tar.gz` ist,
* es größer als 300 MB ist (mehr wird gar nicht erst gelesen),
* es absolute Pfade oder `../` enthält,
* weniger als 20 Einträge drin sind,
* `index.html` oder `de/index.html` fehlt,
* eines der Verzeichnisse `de/`, `css/`, `js/`, `images/` fehlt.

In jedem dieser Fälle bleibt die bisherige Site unverändert stehen und der
Build schlägt fehl. Dieselben Bedingungen prüft `build.yml` schon auf dem
Runner – dort merkt man es früher, auf der VM ist es die Absicherung.

Umgeschaltet wird mit `rsync --delete`: was im Archiv fehlt, verschwindet auch
auf der VM. Eine gelöschte Seite bleibt nicht als Ruine erreichbar.

Protokoll der Auslieferungen: `/var/log/dbg-deploy.log`, zusätzlich im Journal
(`journalctl -t dbg-receive-site`).

## Was wo liegt

```
vm-install/
  install.sh                 Treiber: ruft die Schritte in der richtigen
                             Reihenfolge auf. Das ist das "config skript".
  deploy-site.sh             Inhalt von Hand ausrollen (wiederholbar)
  show-deploy-secrets.sh     zeigt die Werte für die GitHub-Secrets
  make-bundle.sh             auf dem Arbeitsrechner: alles in ein tar.gz

  config/
    dbg-vm.conf              die EINZIGE Datei, die angepasst werden muss

  scripts/
    lib.sh                   gemeinsame Hilfsfunktionen
    10-base.sh               Paketstand, Zeitzone, Sprache, Auto-Updates
    20-ssh.sh                SSH härten, Port setzen
    30-firewall.sh           ufw: nur SSH, 80, 443
    40-fail2ban.sh           Fehlversuche aussperren
    50-apache.sh             Apache, Module, Grundhärtung, http-vHost
    60-tls.sh                Zertifikat (Let's Encrypt oder selbst signiert)
    70-site.sh               https-vHost, DocumentRoot, Protokollfristen
    90-deploy.sh             Zugang für GitHub Actions
    80-verify.sh             Abschlussprüfung, ändert nichts

  files/                     Konfigurationsvorlagen, Pfade wie auf der VM
    etc/ssh/sshd_config.d/10-dbg-hardening.conf
    etc/sysctl.d/90-dbg-hardening.conf
    etc/apt/apt.conf.d/52-dbg-unattended-upgrades
    etc/apache2/conf-available/dbg-hardening.conf     Header, Timeouts, Caching
    etc/apache2/conf-available/dbg-ssl-params.conf    TLS-Verfahren
    etc/apache2/conf-available/dbg-csp.conf           Content Security Policy
    etc/apache2/conf-available/dbg-logging.conf       gekürzte IP-Adressen
    etc/apache2/conf-available/dbg-staging.conf       Vorschau unter /staging/
    etc/apache2/conf-available/dbg-staging-auth.conf  deren Anmeldung (optional)
    etc/apache2/sites-available/dbg-http.conf         Port 80 → https
    etc/apache2/sites-available/dbg-ssl.conf          die Site
    etc/apache2/sites-available/dbg-weiterleitung.conf  Weiterleitung (REDIRECT_DOMAINS)
    etc/fail2ban/jail.d/dbg.local
    etc/logrotate.d/dbg
    etc/sudoers.d/dbg-deploy                          eine Zeile, ein Programm
    usr/local/sbin/dbg-receive-site                   der Empfänger

  site/                      hierher kopiert make-bundle.sh target/website/
```

In den Vorlagen stehen Platzhalter wie `<site_name>`, `<admin_email>` oder
`<ssh_port>`; `install.sh` setzt die Werte aus `config/dbg-vm.conf` ein und
bricht ab, falls einer übrig bleibt. Jede Datei landet unter demselben Pfad wie
unter `files/` – wer auf der VM nachsehen will, wo etwas herkommt, findet es an
der gleichen Stelle.

## install.sh

```bash
sudo ./install.sh                     alle Schritte
sudo ./install.sh --list              Schritte anzeigen
sudo ./install.sh --dry-run           nur zeigen, was laufen würde
sudo ./install.sh --only tls,site     nur diese Schritte
sudo ./install.sh --skip base         alles außer diesem Schritt
```

Einzelne Werte lassen sich überschreiben, ohne die Konfiguration zu ändern:

```bash
sudo TLS_MODE=letsencrypt ./install.sh --only tls,site
```

**Jeder Durchlauf ist wiederholbar.** Ein zweiter Lauf schreibt keine einzige
Datei neu – nur was sich tatsächlich unterscheidet, wird angefasst, und eine
ersetzte Datei wird vorher nach `/var/backups/dbg-vm-install/<zeitstempel>/`
gesichert. Vor jedem Neustart eines Dienstes wird dessen Konfiguration geprüft
(`sshd -t`, `apache2ctl configtest`, `fail2ban-client --test`, `visudo -c`) –
ein Tippfehler legt also keinen laufenden Dienst lahm.

Die ausführlichen Paketausgaben stehen in `/var/log/dbg-vm-install.log`; auf dem
Bildschirm erscheinen sie nur, wenn etwas schiefgeht.

Die Reihenfolge der Schritte ist nicht beliebig:

| vor | nach | Grund |
|-----|------|-------|
| `ssh` | `firewall` | die Firewall muss den neuen SSH-Port kennen |
| `firewall` | `fail2ban` | fail2ban setzt seine Sperren über ufw |
| `apache` | `tls` | Let's Encrypt prüft über Port 80 |
| `tls` | `site` | Apache startet nicht ohne Zertifikatsdateien |
| `site` | `deploy` | der Empfänger prüft nach dem Ausliefern, ob die Site antwortet |

## Zertifikat: erst selbst signiert, später Let's Encrypt

`TLS_MODE` in `config/dbg-vm.conf` steht anfangs auf `selfsigned`. Damit läuft
die VM vollständig, **bevor** der DNS-Eintrag umgestellt ist – der Browser
warnt, aber alles andere ist fertig und lässt sich prüfen. Sobald
`<SITE_NAME>` auf die VM zeigt:

```bash
sudo TLS_MODE=letsencrypt ./install.sh --only tls,site
```

Danach `TLS_MODE="letsencrypt"` auch in der Konfiguration eintragen, damit der
nächste Durchlauf dabei bleibt.

Vor dem Anfragen prüft `60-tls.sh` selbst, ob der Nachweispfad
`http://<SITE_NAME>/.well-known/acme-challenge/…` von außen erreichbar ist, und
bricht sonst ab – ein Fehlversuch würde auf das Rate Limit von Let's Encrypt
gehen. Mit `TLS_MODE=staging` lässt sich das ohne Rate Limit ausprobieren.

Beschafft wird das Zertifikat über die **webroot**-Methode, nicht über
`--apache`: certbot fasst die Apache-Konfiguration damit nicht an, und was in
`sites-available/` steht, bleibt genau das, was unter `files/` liegt. Die
Erneuerung übernimmt `certbot.timer`; ein Haken unter
`/etc/letsencrypt/renewal-hooks/deploy/` lädt Apache danach neu, weil Apache
Zertifikate nur beim Start einliest.

**HSTS** wird erst mit `TLS_MODE=letsencrypt` gesetzt. Mit diesem Kopf darf der
Browser die Site für die angegebene Dauer nur noch per https aufrufen – bei
einem ungültigen Zertifikat gäbe es dann keinen Weg mehr hinein, und
zurücknehmen lässt sich die Zusage nicht.

## Weitere Domains, die weiterleiten (`REDIRECT_DOMAINS`)

Domains wie `deubo.de` zeigen nicht die Site, sondern leiten dauerhaft (301) auf
`https://<SITE_NAME>/` weiter, der Pfad bleibt dabei erhalten. Sie stehen in
`config/dbg-vm.conf`:

```bash
REDIRECT_DOMAINS="deubo.de www.deubo.de"
```

Dafür gibt es ein **eigenes Zertifikat** (`/etc/letsencrypt/live/<erster Name>/`)
und einen eigenen https-vHost (`files/etc/apache2/sites-available/dbg-weiterleitung.conf`).
Das Zertifikat der Site hängt damit nicht an diesen Namen: Fehlt bei einem
davon der DNS-Eintrag, bleibt die Site unberührt. Über http beantwortet sie
`dbg-http.conf` mit – Nachweispfad für Let's Encrypt inklusive.

- Jeder Name braucht einen DNS-Eintrag (A, ggf. AAAA) auf die VM. `60-tls.sh`
  prüft vor der Anfrage jeden einzeln und bricht sonst ab.
- Nachträglich hinzufügen: Namen eintragen, dann
  `sudo ./install.sh --only apache,tls,site`.
- Kein HSTS für diese Namen: global steht es mit `includeSubDomains`, das
  würde sonst alle Subdomains dieser Domain auf https festlegen.
- Der Dateiname `dbg-weiterleitung.conf` sortiert bewusst hinter `dbg-ssl.conf`:
  so bleibt die Site der Standard-vHost für Port 443.

## Offene Ports

Mehr als diese drei ist nicht offen:

| Port | wofür |
|------|-------|
| `SSH_PORT` | Verwaltung **und Auslieferung aus GitHub**. `ufw limit`, also höchstens sechs Verbindungsversuche in 30 Sekunden je Adresse |
| 80/tcp | der ACME-Nachweis und die Weiterleitung auf https – sonst nichts |
| 443/tcp | die Website |

**Ping** bleibt beantwortet: `ufw` lässt `icmp echo-request` in seiner
`before.rules` von Haus aus durch, da war nichts zu tun. Nur Antworten auf
*Broadcast*-Pings sind aus (`net.ipv4.icmp_echo_ignore_broadcasts`) – sonst
könnte die VM als Verstärker für Angriffe auf Dritte dienen. Prüfen mit
`ping <vm>` von außen.

Die Firewall ist `ufw` und nicht `iptables-persistent` wie in den
`dev-vm`-Projekten: auf Ubuntu 24.04/26.04 filtert der Kern mit nftables, und
`ufw` ist die Oberfläche, die Ubuntu dafür mitbringt. fail2ban setzt seine
Sperren über dieselbe Oberfläche (`banaction = ufw`) – zwei Verwalter in
derselben Regelkette führen sonst zu Sperren, die nie greifen.

## Zwei Fallen auf neueren Ubuntu-Versionen

**Der SSH-Port steht nicht nur in `sshd_config`.** Ab Ubuntu 24.04 startet sshd
über eine Socket-Unit: systemd nimmt die Verbindung an, nicht sshd, und die
Zeile `Port` bleibt wirkungslos. `20-ssh.sh` erkennt das und legt zusätzlich
`/etc/systemd/system/ssh.socket.d/10-dbg-port.conf` ab. Ohne diesen Teil horcht
die VM nach dem Umstellen weiter auf 22 – und die Firewall lässt 22 nicht mehr
durch.

**Die Passwort-Anmeldung abzuschalten kann die VM aussperren.** Bei
`SSH_DISABLE_PASSWORD_AUTH="auto"` (Voreinstellung) sieht `20-ssh.sh` erst nach,
ob überhaupt ein Schlüssel in einer `authorized_keys` liegt. Wenn nicht, bleibt
die Passwort-Anmeldung an und es gibt einen Hinweis.

Beim Umstellen des SSH-Ports: die laufende Sitzung offen halten und den neuen
Port in einem zweiten Terminal prüfen. Wer einen Rückweg möchte, öffnet die 22
vorübergehend mit `FIREWALL_EXTRA_ALLOW="22/tcp"` und schließt sie später wieder
mit `sudo ufw delete allow 22/tcp`.

## Protokolle und Datenschutz

Übernommen aus `../deploy/` und in die Installation eingebaut – die beiden
Dateien dort (`apache-logging.conf`, `logrotate-dbg`) sind damit abgedeckt und
können entfallen.

### Abgleich mit der Datenschutzerklärung

`content/de/datenschutz.md`, Abschnitt „Server-Protokolldateien", macht konkrete
Zusagen. Jede einzelne davon gegen die Konfiguration gehalten:

| Zusage in der Erklärung | wo umgesetzt | passt |
|---|---|---|
| Webserver ist der Apache HTTP Server | `50-apache.sh` | ja |
| erfasst: Browser, Betriebssystem, Referrer, Dateiname, Datenmenge, Datum/Uhrzeit, IP | Format `combined` – genau diese Felder | ja |
| Auswertung nur auf dem eigenen Server, keine Werkzeuge Dritter | keine Analytics, kein CDN, keine externen Schriften | ja |
| **vollständige** Fassung: **7 Tage** | `logrotate_set_retention /etc/logrotate.d/apache2 7` | ja |
| **gekürzte** Fassung: **6 Monate** | `/etc/logrotate.d/dbg`, `monthly` + `rotate 6` | ja |
| Kürzung, **bevor** geschrieben wird | `SetEnvIf` + eigenes `LogFormat` in `dbg-logging.conf` | ja |
| IPv4: letztes Byte weg, IPv6: ab dem dritten Block | die beiden `SetEnvIf`-Regeln | ja |

Zwei Dinge sind dabei aufgefallen und behoben:

* **Das Fehlerprotokoll** `/var/log/apache2/error.log` enthält bei jeder
  Fehlermeldung die vollständige Adresse (`[client 203.0.113.47:…]`). Es fällt
  unter dieselbe logrotate-Regel wie die Zugriffsprotokolle, ist also mit
  denselben 7 Tagen erfasst. Ausgeliefert steht die Regel auf `rotate 14`.
* **`/var/log/fail2ban.log`** hält die vollständigen Adressen gesperrter
  Zugriffe fest. Ubuntu liefert dafür `weekly rotate 4` aus – bis zu fünf
  Wochen. Die Erklärung sagt für die vollständige Fassung 7 Tage zu, länger nur
  „zur Aufklärung eines konkreten Angriffs"; eine pauschale Fünf-Wochen-Datei
  ist das nicht. `40-fail2ban.sh` setzt die Regel deshalb ebenfalls auf
  `daily` / `rotate 7`.

`sudo ./install.sh --only verify` liest die drei Fristen aus den
logrotate-Regeln aus und vergleicht sie mit diesen Zahlen – eine Zusage, die
niemand nachprüft, ist keine.

Zwei Punkte, die ich bewusst **nicht** verändert habe, die du aber kennen
solltest:

* **Das systemd-Journal** hält fehlgeschlagene SSH-Anmeldungen samt
  vollständiger Adresse, und zwar länger als 7 Tage (Ubuntu begrenzt es nach
  Platz, nicht nach Zeit). Das sind keine Websitebesucher, sondern
  Zugriffsversuche auf die Verwaltung – die Erklärung spricht ausdrücklich vom
  *Webserver* und deckt das nicht ab. Wer es trotzdem begrenzen will:
  `MaxRetentionSec=1month` in `/etc/systemd/journald.conf`.
* **Die gekürzte Fassung behält Referrer und User-Agent** für 6 Monate. Die
  Erklärung sagt nur „IP-Adresse gekürzt" und nennt als Zweck die Zugriffszahlen
  – für die bräuchte man beides nicht. Formal ist es gedeckt, und Auswerter wie
  GoAccess zeigen damit auch die Browserverteilung. Soll es strenger sein, in
  `dbg-logging.conf` das `LogFormat anonymisiert` auf
  `%{client_anon}e %l %u %t "%r" %>s %b` kürzen.

### Die beiden Protokolle

| Datei | Inhalt | Frist |
|-------|--------|-------|
| `/var/log/apache2/{access,ssl_access,error}.log` | vollständig, mit IP-Adresse | 7 Tage |
| `/var/log/apache2-stats/access-anon.log` | IP gekürzt | 6 Monate |
| `/var/log/fail2ban.log` | gesperrte Adressen, vollständig | 7 Tage |

Die Kürzung geschieht **beim Schreiben** – in `access-anon.log` steht die
vollständige Adresse zu keinem Zeitpunkt, nicht erst nach einem nachträglichen
Bereinigungslauf, den man vergessen könnte. Das gekürzte Protokoll liegt bewusst
in einem eigenen Verzeichnis, weil die mitgelieferte logrotate-Regel
`/var/log/apache2/*.log` pauschal erfasst und es sonst nach sieben Tagen
mitlöschen würde.

Das Format entspricht `combined`, nur mit der gekürzten Adresse an erster
Stelle – GoAccess, AWStats und webalizer lesen die Datei unverändert.

**Aufrufe der Vorschau unter `/staging/` stehen nicht in der
Zugriffsstatistik.** Dort sind nur wir selbst unterwegs; sie würden die Zahlen
verfälschen, die die Nutzung der öffentlichen Website zeigen sollen. Im
vollständigen Protokoll bleiben sie, dort sind sie für die Fehlersuche nützlich.
Ebenso ausgenommen sind die Aufrufe des Zustelldiensts von Let's Encrypt.

> **Hinweis zu `deploy/logrotate-dbg`:** dort stand `rotate 6   # Kommentar`.
> logrotate erlaubt keinen Kommentar hinter einer Anweisung, verwirft deshalb
> die ganze Regel – das anonymisierte Protokoll wäre nie rotiert worden und
> unbegrenzt gewachsen, entgegen der Zusage von 6 Monaten. In beiden Dateien
> korrigiert. Nachprüfen mit `logrotate -d /etc/logrotate.d/dbg` (muss ohne
> `error:` durchlaufen).

## Content Security Policy

Die generierte Site lädt Skripte (lunr, leaflet, MathJax, highlight.js), Stile
und Schriften ausnahmslos lokal. Von außen kommen nur die Kartenkacheln der
Ärzteliste, deshalb stehen in `img-src` zusätzlich `tile.openstreetmap.org` und
`tile.openstreetmap.de` (`CSP_IMG_HOSTS`).

`form-action` begrenzt, wohin ein **Formular** abschicken darf. Die Suche
bleibt auf der Site, der Spendenknopf auf der Seite „Spenden" schickt aber an
PayPal – dafür steht `CSP_FORM_HOSTS` (`https://www.paypal.com`). Fehlt der
Host, bricht der Browser das Abschicken ohne Rückmeldung ab: ein Klick, und
scheinbar passiert nichts. Nur in der Konsole steht „Refused to send form data
… violates … form-action". Ein gewöhnlicher Link ist davon nicht betroffen,
deshalb funktioniert `paypal.me` auf derselben Seite auch ohne Eintrag.

Kommt eine externe Quelle dazu, gehört sie in `CSP_IMG_HOSTS`,
`CSP_FORM_HOSTS` bzw. in
`files/etc/apache2/conf-available/dbg-csp.conf`. Zum Ausprobieren ohne
Nebenwirkungen in dieser Datei `Content-Security-Policy` durch
`Content-Security-Policy-Report-Only` ersetzen und in der Browser-Konsole
nachsehen. Ganz abschalten: `ENABLE_CSP="no"`.

## Inhalt von Hand ausrollen

Im Normalfall tut das GitHub. Von Hand geht es so:

```bash
# auf dem Arbeitsrechner
mvn package
rsync -av --delete target/website/ <benutzer>@<vm>:/tmp/website/

# auf der VM
cd vm-install && sudo ./deploy-site.sh /tmp/website
```

Mit `--dry-run` zeigt `deploy-site.sh` vorher, was sich ändern würde. Die
Dateien gehören `root:www-data` und sind für den Webserver nur lesbar – ein
Fehler im Webserver kann damit keine Seite verändern.

## Nachsehen, ob alles läuft

```bash
sudo ./install.sh --only verify
```

Prüft Dienste, offene Ports, Firewall, fail2ban, Apache-Konfiguration, den
Auslieferungszugang, ruft die Site über die Loopback-Schnittstelle ab
(unabhängig von DNS und Firewall) und zeigt Antwortkopfzeilen und
Zertifikatsdaten. Ändert nichts.

Einzelne Handgriffe:

```bash
systemctl status apache2 fail2ban ufw ssh
apache2ctl -S                          # welcher vHost ist zuständig?
ufw status verbose
fail2ban-client status
fail2ban-client status sshd
fail2ban-client set sshd unbanip 203.0.113.5
certbot certificates
certbot renew --dry-run
tail -f /var/log/apache2/error.log
tail -f /var/log/dbg-deploy.log        # Auslieferungen
journalctl -u apache2 -n 50
```

Von außen prüfen lassen: <https://www.ssllabs.com/ssltest/> und
<https://securityheaders.com/>.

### Wenn Apache nicht startet

Fast immer fehlt eine Zertifikatsdatei oder `dbg-ssl.conf` zeigt auf den
falschen Pfad:

```bash
apache2ctl configtest
ls -l /etc/letsencrypt/live/<SITE_NAME>/ /etc/ssl/dbg/
```

Übergangsweise den https-vHost abschalten und ohne ihn starten:

```bash
sudo a2dissite dbg-ssl && sudo systemctl restart apache2
```

### Wenn eine Sicherungskopie in sites-enabled/ liegt

Apache wählt bei mehreren `VirtualHost`-Blöcken mit demselben `ServerName` einen
davon aus – eine dort abgelegte Sicherungskopie kann die richtige Konfiguration
verdrängen. Dieser Fehler ist in den `dev-vm`-Projekten schon einmal
aufgetreten. `70-site.sh` warnt, wenn es für `*:443` mehr als einen Eintrag mit
`<SITE_NAME>` gibt. Sicherungen gehören nach `/var/backups/dbg-vm-install/`,
nicht nach `sites-enabled/`.

### Wenn die Auslieferung aus GitHub scheitert

```
Permission denied (publickey)
```
Der Schlüssel passt nicht. `sudo ./show-deploy-secrets.sh` auf der VM und
`VM_SSH_KEY` neu eintragen – vollständig, ohne führende Leerzeichen.

```
Host key verification failed
```
`VM_KNOWN_HOSTS` passt nicht zum Namen oder Port. Bei einem Port ≠ 22 muss die
Form `[name]:port …` lauten. Auch nach einer Neuinstallation der VM neu
eintragen – dann hat sie neue Host-Schlüssel.

```
sudo: a password is required
```
`/etc/sudoers.d/dbg-deploy` fehlt oder ist fehlerhaft:
`sudo ./install.sh --only deploy`.

Es kommt eine **Shell** statt einer Antwort: der erzwungene Befehl fehlt in der
`authorized_keys`. Ebenfalls `--only deploy`.

Nichts davon, sondern eine **Zeitüberschreitung**: möglicherweise hat fail2ban
die Adresse des Runners gesperrt (nach fünf Fehlversuchen). Nachsehen und lösen:

```bash
fail2ban-client status sshd
fail2ban-client unban --all
```

## Probleme und offene Punkte

Was beim Einrichten auffallen wird, und was bewusst so ist:

* **Die Vorschau ist offen erreichbar.** Dass nur Eingeweihte die Adresse
  kennen, ist Verschleierung, kein Schutz: Pfade sickern über den `Referer`
  beim Klick nach außen, über weitergegebene Links, über Chat- und
  Mailprogramme, die Vorschaubilder erzeugen und die Adresse dafür abrufen, und
  über Browser-Erweiterungen. Für „noch nicht fertig" ist das in Ordnung. Für
  etwas, das wirklich niemand sehen darf, nicht – dann
  `STAGING_BASIC_AUTH_USERS` setzen, das ist eine Zeile.
  `X-Robots-Tag: noindex` hält immerhin die Suchmaschinen fern, und zwar
  verlässlicher als eine robots.txt, die den Pfad ihrerseits verraten würde.
* **Die Karte der Ärzteliste ist der einzige Dienst eines Dritten.** Sie lädt
  ihre Kacheln von `tile.openstreetmap.org`, womit die IP-Adresse des Besuchers
  an die OpenStreetMap Foundation geht. Die Datenschutzerklärung sagte früher,
  die Website binde „keine externen … Karten" ein – das war ein Widerspruch und
  ist behoben: `content/de/datenschutz.md` und `content/en/privacy.md` haben
  jetzt den Abschnitt „Kartenanzeige in der Ärzte- und Therapeutenliste" mit
  Anbieter, übertragenen Daten, Zweck und Rechtsgrundlage (Art. 6 Abs. 1 lit. f
  DSGVO). **Wenn hier ein Host zu `CSP_IMG_HOSTS` dazukommt, gehört er auch
  dorthin.** Zwei Punkte solltest du vor dem Livegang noch prüfen lassen: den
  Satz zur Übermittlung ins Vereinigte Königreich (der Angemessenheitsbeschluss
  der EU-Kommission wird befristet erteilt und verlängert, der Text verweist
  deshalb auf den „jeweils geltenden") und ob euch die Rechtsgrundlage
  „berechtigtes Interesse" genügt – wer stattdessen eine Einwilligung möchte,
  braucht die Variante mit „Karte anzeigen"-Klick, die ich auf Zuruf einbauen
  kann.

* **SSH darf nicht auf eigene IP-Adressen beschränkt werden.** Die Auslieferung
  kommt von GitHubs Runnern, und deren Adressen wechseln aus einem sehr großen
  Bereich. Wer SSH auf bekannte Adressen eingrenzen will, kann den
  Schiebe-Ansatz nicht verwenden; dann wäre ein Hol-Ansatz richtig (ein Dienst
  auf der VM lädt das Ergebnis des letzten `main`-Builds von der GitHub-API).
  Mehr Teile, aber kein eingehender Zugang. Auch das gern auf Zuruf.
* **`main` sollte geschützt sein.** Ohne Regel geht ein direkter Push auf `main`
  sofort live. Eine Pull-Request-Pflicht und, wer mag, *Required reviewers* an
  der Umgebung `production` (Settings → Environments) schieben einen Klick
  dazwischen.
* **Der Zweig `staging` existiert noch nicht** – `pages.yml` läuft erst, wenn er
  angelegt ist. Bis dahin passiert bei einem Checkin dort schlicht nichts.
* **Aus `pages.yml` ist `staging.yml` geworden.** Die alte Datei löste auf
  `main` aus und veröffentlichte nach GitHub Pages; beides gilt nicht mehr.
  GitHub Pages wird gar nicht mehr gebraucht und kann in den
  Repository-Einstellungen abgeschaltet werden.
* **Die Engine wird mit `main` gebaut** (`ENGINE_REPO`/`engine-ref`). Für
  reproduzierbare Builds dort ein Tag eintragen; sonst kann eine Änderung in
  `site-gen` die Site verändern, ohne dass in diesem Repo etwas passiert ist.
  `live.yml` nimmt den Stand bei einem Start von Hand auch als Eingabefeld an.
* **Kein Mailversand.** fail2ban und unattended-upgrades sind auf `ADMIN_EMAIL`
  eingestellt, versenden aber nur, wenn ein MTA vorhanden ist. Soll die VM
  Meldungen verschicken, gehört ein `msmtp` als Nur-Versand-Relais dazu.
* **`ufw` braucht einen echten Kern.** Bei einem virtualisierten Wurzelsystem
  (LXC/OpenVZ, wie bei manchen günstigen Anbietern) lassen sich die
  Protokollregeln von ufw nicht laden. `30-firewall.sh` erkennt das und schaltet
  die Firewall-Protokollierung ab, statt die Maschine ungeschützt zu lassen –
  mit einem deutlichen Hinweis. Auf einer echten VM tritt das nicht auf.

## Was dieses Projekt nicht tut

* **Kein Backup.** Ausdrücklich nicht gewünscht, und sinnvoll: die Site ist
  vollständig aus `content/` reproduzierbar, und eine Fassung zurück geht mit
  `rollback`. Zu sichern wären allenfalls `/etc/letsencrypt/` (ein Zertifikat
  ist aber jederzeit neu zu holen) und `config/dbg-vm.conf` – das liegt im
  Projekt.
* **Kein Tomcat, kein PHP, kein CGI, keine Datenbank.** Die Site ist statisch.
  Die entsprechenden Apache-Module bleiben aus.
* **Keine Benutzerverwaltung.** Außer dem Auslieferungskonto legen die Skripte
  keine Konten an und ändern keine Passwörter.

## Geprüft mit

Die Skripte sind mehrfach in einem Ubuntu-24.04-Container mit laufendem systemd
durchgelaufen:

* Installation von Grund auf, anschließend ein zweiter Durchlauf, der **keine
  einzige Datei** neu schreibt
* https mit http/2 und 200, Weiterleitung von http mit 301, alle
  Antwortkopfzeilen gesetzt (CSP einschließlich der Kachelserver)
* SSH über die Socket-Unit, auf Port 22 und auf 4382, je über IPv4 **und** IPv6
  geprüft; Passwort-Anmeldung automatisch abgeschaltet, weil ein Schlüssel
  hinterlegt war
* fail2ban mit acht Regeln aktiv
* `ufw` mit genau den drei Regeln, einschließlich des Rückfalls auf
  abgeschaltete Firewall-Protokollierung
* die Protokolle: gekürzte Adresse in `access-anon.log` (`127.0.0.1` →
  `127.0.0.0`), vollständige im 7-Tage-Protokoll, Vorschau nur dort und nicht in
  der Statistik, und alle drei Fristen von `--only verify` nachgerechnet
* Vorschau und öffentliche Site **unabhängig**: eine Auslieferung auf die Site
  lässt die Vorschau unberührt und umgekehrt, `rollback` und
  `rollback-staging` treffen jeweils nur ihr Ziel
* die Abweisung fehlerhafter Archive (leer, ohne `index.html`, mit absoluten
  Pfaden, kein gzip) und des Versuchs, eine Shell zu bekommen – in jedem Fall
  blieb der laufende Stand unverändert

Die Abläufe unter `.github/` sind mit `actionlint` (einschließlich shellcheck)
ohne Befund, alle Shell-Skripte mit `shellcheck --severity=warning` ebenfalls.

### Beim Prüfen gefundene Fehler

Der Reihe nach, damit bei ähnlichen Symptomen klar ist, wo man suchen kann:

1. **`rotate 6   # Kommentar`** in `deploy/logrotate-dbg`. logrotate erlaubt
   keinen Kommentar hinter einer Anweisung und verwirft die ganze Regel – das
   anonymisierte Protokoll wäre nie rotiert worden.
2. **Ein `grep` ohne Treffer** brach den Prüfschritt ab (`set -e`).
3. **Ein verlorener Rückgabewert** in der Protokollfunktion: `local rc=$?` nach
   einem `if` liest immer 0. Ein fehlgeschlagenes `apt-get` hätte wie ein Erfolg
   gewirkt.
4. **`curl … || echo 000`** gab „000000" aus – curl schreibt die 000 selbst.
5. **Die SSH-Socket-Unit horchte nur auf IPv6.** Ubuntus `ssh.socket` bringt
   zwei `ListenStream`-Zeilen mit und dazu `BindIPv6Only=ipv6-only`; ein
   einzelnes `ListenStream=<port>` bindet dann ausschließlich `[::]`. Jede
   Anmeldung über IPv4 bekam „Connection refused" – also genau die Aussperrung,
   vor der der SSH-Abschnitt warnt. Die Prüfung sagte trotzdem „horcht", weil
   sie nur `ss` gelesen hat; sie baut jetzt je Adressfamilie eine Verbindung
   auf.
6. **rsync übertrug eine geänderte Datei nicht.** Ohne `--checksum` entscheidet
   rsync nach Größe und Änderungszeit, und `tar` schreibt die Zeit nur
   sekundengenau: zwei gleich lange Fassungen aus derselben Sekunde gelten als
   identisch. Beide Auslieferungen benutzen jetzt `--checksum`.
7. **Ein Platzhalter blieb unersetzt**, weil `dbg-logging.conf` mit `copy_file`
   statt `render` abgelegt wurde – die Apache-Regel war gültig, tat aber nichts.
   `copy_file` bricht jetzt ab, wenn die Vorlage einen Platzhalter enthält.
