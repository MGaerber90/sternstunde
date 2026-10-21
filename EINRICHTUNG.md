# Sternstunde einrichten (einmalig, ca. 15 Minuten)

Ohne diese Schritte läuft die App im Testmodus, und die Daten bleiben im jeweiligen Browser. Erst mit dem Server sehen Lehrkraft und Schüler auf verschiedenen Geräten dasselbe, live.

## Vorher klären

- Verhaltensampel und Sterne sind personenbezogene Daten. Den Einsatz kurz mit der Schulleitung bzw. dem Datenschutzbeauftragten absprechen.
- Supabase bietet einen Auftragsverarbeitungsvertrag (DPA) an: Dashboard > Organization > Legal Documents.
- Rechenzentrum beim Anlegen auf **Frankfurt** stellen.

## 1. Supabase-Projekt anlegen

1. Auf https://supabase.com kostenlos registrieren.
2. **New project**:
   - Name: `sternstunde`
   - Database Password: auf **Generate** klicken und im Passwortmanager speichern (wird für die App nicht gebraucht)
   - Region: **Central EU (Frankfurt)**
   - Plan: Free
3. Warten, bis das Projekt bereit ist (1 bis 2 Minuten).

## 2. Datenbank einrichten

Links **SQL Editor** > **New query**. Nacheinander den Inhalt dieser drei Dateien einfügen und jeweils **Run** klicken:

| Reihenfolge | Datei | Inhalt |
|---|---|---|
| 1 | `supabase/schema.sql` | Tabellen und Server-Funktionen |
| 2 | `supabase/items.sql` | Shop-Preise |
| 3 | `supabase/seed.local.sql` | Klasse, Namen, PINs, Lehrer-PIN |

Jedes Mal sollte unten „Success. No rows returned“ stehen.

## 3. App mit dem Server verbinden

1. In Supabase: **Project Settings** > **API Keys**. Den **Publishable key** (`sb_publishable_...`) kopieren.
2. In Supabase: **Project Settings** > **Data API**. Die **Project URL** kopieren.
3. In `config.js` beide Werte eintragen:

```js
window.STERNSTUNDE_CONFIG = {
  supabaseUrl: 'https://xxxxxxxx.supabase.co',
  supabaseKey: 'sb_publishable_xxxxxxxx'
};
```

4. `index.html` öffnen. Auf der Startseite fehlt jetzt der Hinweis „Testmodus“, und die Lehrer-PIN ist die 8-stellige aus `zugangskarten.local.html`.

## 4. Online stellen (GitHub Pages)

Hochgeladen werden nur Dateien ohne Namen und PINs. `.gitignore` schließt alle `*.local.*`-Dateien aus.

1. Repository `sternstunde` anlegen und den Ordner hochladen.
2. Repository > **Settings** > **Pages** > Branch `main`, Ordner `/ (root)` > Save.
3. Nach ca. 1 Minute läuft die App unter https://mgaerber90.github.io/sternstunde/

Steht die App unter einer anderen Adresse, die Karten neu erzeugen: `node tools/zugaenge.mjs --url=https://...` (PINs bleiben gleich).

## 5. Zugangskarten verteilen

`zugangskarten.local.html` öffnen > **Als PDF herunterladen** > drucken und ausschneiden. Oben steht deine Lehrer-PIN; dieser Teil wird nicht mitgedruckt.

Beim ersten Login gibt jede Person ein: Klassencode, Namen auswählen, PIN. Danach folgen Geburtstag, Spitzname und Avatar.

## Gut zu wissen

- **Pause bei Inaktivität:** Kostenlose Supabase-Projekte pausieren nach 7 Tagen ohne Zugriff (z. B. in den Ferien). Im Dashboard auf **Restore project** klicken, die Daten bleiben erhalten.
- **PIN vergessen:** In der Lehreransicht auf die Schülerkarte klicken > Zugang > Neue PIN.
- **Lehrer-PIN ändern:** Einstellungen > Lehrer-PIN (6 bis 12 Ziffern).
- **Sicherung:** Einstellungen > Sicherung herunterladen. Vor dem Reset passiert das automatisch.
- **Neues Schuljahr:** In `namen.local.js` die neuen Namen eintragen, `node tools/zugaenge.mjs --neu` ausführen, `seed.local.sql` erneut in Supabase ausführen.
- **Shop erweitert:** Nach Änderungen am Katalog `node tools/zugaenge.mjs` ausführen und `supabase/items.sql` erneut in Supabase ausführen, sonst lehnt der Server Käufe neuer Items ab.
