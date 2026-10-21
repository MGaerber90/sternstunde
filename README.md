# Sternstunde: Klassen-App 9m

Browser-App zur Organisation der Klasse 9m (24 Schüler, Schuljahr 2026/27). Getrennte Ansichten für Lehrkraft und Schüler.

## Status

- [x] Phase 1: Layout und kompletter Aufbau als Einzeldatei `index.html` (Testmodus, Daten im Browser)
- [x] Retro-Space-Design (Pixel-Schrift Press Start 2P, eingebettet), Mission (Klassenziel), Geburtstagskalender
- [x] 28 Erfolge (Achievements), hellerer Look, runde Ampel, "Was steht an?" geteilt (Hausaufgaben | Termine und Proben)
- [x] Vornamen eingetragen: lokal in `namen.local.js` (steht in `.gitignore`, wird nie hochgeladen), alphabetisch sortiert
- [x] Spitzname beim ersten Login, nur für die Person selbst sichtbar
- [x] Verkleidungen (9 Kostüme) und Alien-Stil (Fantasy-Haut, Antennen, Alien-Augen, drittes Auge)
- [x] Phase 2: Server-Betrieb gebaut und lokal mit echtem Postgres getestet (Supabase, Anleitung in `EINRICHTUNG.md`)
- [x] Zugänge erzeugt: Klassencode, 24 PINs, Lehrer-PIN, Zugangskarten (`zugangskarten.local.html`)
- [x] Supabase live (Projekt `sternstunde`, eu-west-1 Irland, Free), `config.js` gefüllt, 22 API- + 8 Browser-Tests gegen den echten Server bestanden (2026-10-21)
- [ ] Datenschutz mit Schulleitung klären, dann Karten austeilen
- [ ] Auf GitHub Pages veröffentlichen (nach Okay)
- [ ] Datenschutz mit Schulleitung bzw. Datenschutzbeauftragtem klären
- [ ] Veröffentlichung über GitHub Pages

## Funktionen

| Lehrkraft | Schüler |
|---|---|
| Übersicht aller 24 mit Avatar, Ampel, Sternen | Eigener Avatar, beim ersten Login gestalten |
| Ampel grün/gelb/rot mit Rückmeldung und Verlauf | Eigene Ampel mit Rückmeldung (sieht nur die Person selbst) |
| Hilferufe live: Karte blinkt rot, Ton, Tab-Titel blinkt | Roter Notfallknopf "Ich komme nicht weiter" |
| Feedback-Stream, anonym, Filter nach Kategorie | Anonymes Feedback in 4 Kategorien |
| Hausaufgaben, Proben, Termine eintragen | "Was steht an?" mit Countdown |
| +1 Stern pro Karte, mit Begründung, ganze Klasse +1 | Garderobe und Shop: Items anprobieren, mit Sternen freischalten |
| Beamer-Modus (Ampel und Sterne ausgeblendet) | Sterne-Verlauf mit Begründungen |
| PIN-Karten drucken, Sicherung, Schuljahr-Reset | |
| Mission: Ziel, Belohnung, Sternzahl, Deadline frei wählbar, Bonus-Sterne | Mission mit Raketen-Fortschritt, eigener Beitrag, Sterne spenden |
| Geburtstage des Monats in der Seitenleiste, Kuchen auf der Karte | Geburtstag beim ersten Login angeben (Tag und Monat), Monatskalender, Banner am Geburtstag |

## Dateien

| Datei | Inhalt | Veröffentlichen? |
|---|---|---|
| `index.html` | die App | ja |
| `config.js` | Server-Adresse und öffentlicher Schlüssel | ja |
| `supabase/schema.sql`, `supabase/items.sql` | Datenbank | ja |
| `tools/zugaenge.mjs` | erzeugt PINs, Code, Karten, Startdaten | ja |
| `*.local.*` (Namen, PINs, Karten, Startdaten) | personenbezogen | **nein** (`.gitignore`) |

## Testen

`index.html` im Browser öffnen, zwei Tabs: einer als Lehrkraft (PIN 0000), einer als Schüler (PIN unter Einstellungen). Änderungen erscheinen sofort im anderen Tab.

## Avatar-Shop

- Frei ab Start: 3 Frisuren, 3 Haarfarben, Standard-Shirt, alle Hauttöne, 6 Gesichter
- Zu kaufen: 15 Frisuren, 10 Haarfarben (auch Regenbogen, Feuer), 15 Oberteile, 10 Kopf-Items, 7 Brillen, 4 Hals-Items, 6 Extras, 4 Begleiter, 9 Hintergründe
- Fantasy-Haut zu kaufen (Alien-Grün, Pandora-Blau, Galaxie-Lila, Roboter-Chrom, Goldstatue); echte Hauttöne bleiben kostenlos
- Kostüme: Mumie, Pirat, Ninja, Alien-Overall, Vampir, Banane, Hai, Ritter, Roboter
- Nur über Erfolge: Superhelden-Anzug, Heiligenschein, Partyhut, Medaille, Phönix, Schwarzes Loch
- Preise 2 bis 25 Sterne, Stufen Normal, Selten, Episch, Legendär
- Hauttöne sind bewusst nie kostenpflichtig
