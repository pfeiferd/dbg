# Deutsche Borreliose-Gesellschaft e.V. – Website

Inhalte der Website der DBG, gebaut mit der Engine **site-gen**. Dieses Projekt
enthält nur `content/` – Templates, CSS/JS und die Build-Werkzeuge kommen aus der
Engine im Schwesterordner `../site-gen`.

## Bauen

```bash
mvn package
```

Das Ergebnis liegt in `target/website/`. Anschauen z. B. mit

```bash
cd target/website && python3 -m http.server 8080
```

Der Build startet die Engine als eigenen Maven-Lauf und reicht ihr den Inhalt
dieses Projekts durch (`-Dcontent.dir=<hier>/content`); anschließend wird das
fertige Site-Verzeichnis nach `target/website` geholt. Liegt die Engine woanders:

```bash
mvn package -Dengine.dir=/pfad/zu/site-gen
```

## Aufbau des Inhalts

```
content/
  meta.properties      Träger, Logo, Kopf- und Fußzeile
  index.md             publish=false – "/" leitet auf de/ weiter
  search.md            Suchseite
  style.css            eigene Stilanpassungen (wird als css/site.css geladen)
  images/              Logo, Favicon (favicon.svg ist die Quelle) und Banner
  files/               Downloads (PDFs der Originalseite)
  data/                aerzte.json - Einträge der Ärzte-/Therapeutenliste
  de/
    meta.properties    lectureTitle
    index.md           Start (navorder=00)
    aerzteliste.md  aktuelles.md  veranstaltungen.md  ueber-uns.md
    wissenschaft.md  spenden.md  impressum.md  datenschutz.md
    images/            Bilder der Seiten
```

Die Site verwendet das **flache Layout** von site-gen: der Inhalt liegt direkt
unter `content/`, die Seiten werden unter `/de/…` ausgeliefert. Jeder Eintrag im
Seitenmenü links ist eine `.md`-Datei; die Reihenfolge steuert `navorder`.

### Herkunft der Inhalte

Übernommen aus <https://www.borreliose-gesellschaft.de/> (Stand: 16.09.2026).
Die alte Site ist ein CMSimple-System, dessen Hauptmenüpunkte je eine Seite mit
Ankern für die Untermenüpunkte liefern. Daraus wurde:

| Original | hier |
|----------|------|
| Hauptmenüpunkt (`/?Ueber-uns`) | eine Seite, ein Eintrag im Seitenmenü |
| Untermenüpunkt (`/?Ueber-uns#Ueber-uns/Vorstand`) | Abschnitt mit `##`-Überschrift auf dieser Seite |
| nicht verlinkte Veranstaltungsseiten | Abschnitte unter „Veranstaltungen" |
| Modalboxen Impressum/Datenschutz | eigene Seiten |
| `userfiles/downloads/*.pdf` | `content/files/` (im Text `[Titel](files/datei.pdf)`) |
| `userfiles/images/**` | `content/de/images/` (Dateinamen normalisiert) |

Die Übernahme lief einmalig über ein Wegwerf-Skript; sie ist **nicht** Teil des
Builds. Gepflegt wird ab jetzt das Markdown in diesem Projekt.

## Kopfzeile

Eingestellt in `content/meta.properties`:

| Schlüssel | Wirkung |
|-----------|---------|
| `showHeaderToggle=false` | kein Pfeil zum Einklappen der Kopfzeile |
| `showFullscreen=false` | kein Vollbildknopf |
| `documentOnly=true` | kein Folienmodus – damit entfällt auch der Umschalter Dokument/Slides, und die Dokumentansicht gilt verbindlich (auch im Druck) |
| `facultyName=e.V.` | Text rechts neben dem Logo; den Namen trägt die Wortmarke |
| `footerOrg=…` | eine Organisation in der Fußzeile statt Dozent/Fakultät/Hochschule |
| `siteTitle=…` | Titel der Registerkarte nach dem Seitennamen |

Der Schriftzug neben der Bildmarke ist in `content/style.css` vergrößert
(`.logo-sub`); die Vorgabe der Engine ist für einen Fakultätszusatz gedacht.

## Favicon

`content/images/favicon.svg` ist die Quelle: dieselbe Bildmarke wie im Kopf, aber
auf quadratischer Fläche und mit kräftigeren Strichen – in Originalstärke wäre
die Spirochäte bei 32 Pixeln kaum zu erkennen. Der Hintergrund bleibt
transparent, damit das Symbol in hellen wie dunklen Browserleisten sitzt.

Daraus entstehen `favicon.png` (32 × 32, wie im Template deklariert) und
`favicon.ico` (16/32/48). Das Original der alten Seite war ein 200 × 112 großes
PNG, das der Browser in die quadratische Fläche gequetscht hat – daher die
Verzerrung.

## Farben und Seitenleiste

`content/style.css` trägt auch das Farbschema aus dem ersten Entwurf dieser
Site (dem JBake/Bootstrap-Projekt, das dieses hier abgelöst hat):
Teal-Grün (`#0e7c66`) als Primärfarbe, Magenta aus dem Logo (`#c10ac1`) als
Akzent. Überschrieben werden nur die Farbvariablen aus `:root` – dadurch ziehen
Bedienelemente, Verläufe, Druck und Nachtmodus automatisch mit; für den
Nachtmodus stehen aufgehellte Töne daneben, weil dunkle Flächen dort unsichtbar
wären.

Die **Kopfzeile** liegt auf `content/images/zecke-banner.jpg`, darüber ein
Teal-Verlauf; Beschriftungen, Icons und Suchfeld sind darauf abgestimmt (weiß
bzw. leicht durchscheinend).

Das Bannerbild ist aus dem Panorama `zecke_pano.jpg` des ersten Entwurfs gebaut,
weil dessen Format (1900 × 281) für einen so flachen Balken nicht passt:

1. auf die Zecke zugeschnitten (y 33–217), mit 15 px Luft über und unter ihr,
2. **beidseitig** verlängert, bis die Zecke in der Bildmitte liegt – Endformat
   4200 × 184, also 23 : 1 und damit flacher als der Balken bei jeder üblichen
   Fensterbreite. Die Verlängerungen sind der gespiegelte, weichgezeichnete
   Bildrand: ohne Struktur, ohne zweite Zecke (die tauchte bei breiten Fenstern
   auf, als nur der zeckennahe Bereich gespiegelt wurde) und über 300 px
   eingeblendet, sodass keine Naht sichtbar ist.

Dadurch braucht die CSS-Regel keine Ausschnittsakrobatik: `cover` mit
Vorgabeposition beschneidet nur seitlich, nie oben oder unten. Die Zecke bleibt
mittig und vollständig und schrumpft einfach mit der Balkenhöhe mit – die steht
als `--header-height` (62 px) in derselben Datei, zusammen mit dem verringerten
senkrechten Innenabstand der Kopfzeile. Geprüft bei 1000, 1280 und
1600 px Fensterbreite.

> **Achtung:** das Ausgangs-Panorama liegt nicht mehr im Projekt – es gehörte
> zum abgelösten Entwurf. Für eine andere Balkenhöhe oder einen anderen
> Ausschnitt wäre es wieder nötig; falls es noch im alten Repository liegt,
> gehört es als Quelle nach `content/images/` (so wie `favicon.svg`).

Die Beschriftung des Seitenmenüs steht in `content/site_de.properties` bzw.
`site_en.properties` auf „Menü"/„Menu" (Schlüssel `sidebar.lecture`, für die
Vorlesefunktion zusätzlich `sidebar.topics`). Nicht genannte Schlüssel behalten
die Formulierung aus site-gen.

Das Logo `content/images/dbg-logo.svg` trägt deshalb nur noch den Schriftzug
ohne „e.V."; `<title>`/`aria-label` nennen weiterhin den vollständigen Namen.

## Ärzte- und Therapeutenliste

Die Karte auf `de/aerzteliste.md` ist ein `map`-Block von site-gen mit
`data: aerzte`; die Einträge stehen in `content/data/aerzte.json` (30 Stück,
alle mit Koordinaten).

Die Originalseite lädt dieselben Daten über ein CMSimple-Plugin von
`/?&aerztekarte_ajax=1` nach. Von dort stammen sie – einmalig geholt und in das
Format von site-gen überführt (`title`, `subtitle`, `lines[]`, `href`). Zwei
Einträge hatten dort keine Koordinaten („Adresse konnte nicht geokodiert
werden"); die wurden über Nominatim nachgetragen.

**Kachelserver:** `mapTiles`/`mapAttribution` in `content/meta.properties` stellen
alle Karten der Site auf den Server des deutschen OSM-Vereins
(`tile.openstreetmap.de`) – deutsche Beschriftungen, Betrieb in Deutschland.
Ohne diese Angabe nähme site-gen `tile.openstreetmap.org` wie die
Originalseite. Beides sind Gemeinschaftsserver mit Nutzungsrichtlinie; bei
dauerhaft starkem Verkehr wäre ein Anbieter mit Vertrag oder ein eigener Cache
der saubere Weg. Umgestellt ist es mit einer Zeile.

**Pflege:** die JSON-Datei ist jetzt die Quelle. Ein neuer Eintrag braucht
`lat`/`lon` und `land` (letzteres füllt die Auswahlliste) – Adressen werden nicht
automatisch geokodiert. Beim Nachtragen hilft
z. B. <https://nominatim.openstreetmap.org/> (Rechtsklick auf die Karte → Adresse
anzeigen). Beim erneuten Abgleich mit dem Original nicht vergessen, dass die
beiden nachgetragenen Koordinaten dort weiterhin fehlen.

Die Filterleiste des Originals ist nachgebaut, aber im Browser statt auf dem
Server: `filter: land | Land` baut die Auswahlliste aus dem Feld `land` der
Einträge, `search: PLZ oder Ort` durchsucht Titel, Einrichtung und alle Zeilen
(also auch PLZ, Ort, Fachgebiet), `list: true` zeigt die Treffer unter der Karte.

Zwei Unterschiede zum Original: dort wurden nach einer PLZ-Suche die **fünf
nächstgelegenen** Ärzte mit Entfernung in km gezeigt – das setzt voraus, dass der
Suchbegriff geokodiert wird, also eine Anfrage an einen Geodienst pro Suche.
Hier wird stattdessen gefiltert, ohne dass beim Tippen Daten nach außen gehen.
Und die Länderliste enthält nur, was in den Daten vorkommt (Deutschland,
Schweiz) statt einer festen Liste mit Österreich.

## Offene Punkte der Umgestaltung

- Überschriften werden automatisch nummeriert – für eine Vereinsseite evtl. unnötig.
- Vorstand/Beirat: im Original Karten mit Hover-Text, hier je Person eine
  Überschrift mit Bild und vollständigen Angaben.
- Englische Fassung fehlt bewusst (erst einmal nur Deutsch).
