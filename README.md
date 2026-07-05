# Lesezeichen-Prüfer

**Deutsch** | [English](README.en.md)

Ein Windows-Tool mit grafischer Oberfläche zum Aufräumen von Browser-Lesezeichen –
geschrieben als **einzelnes PowerShell-7-Skript ohne weitere Abhängigkeiten**.

Es prüft, welche gespeicherten Seiten noch erreichbar sind, findet doppelte
Lesezeichen, erkennt Seiten hinter Bot-/DDoS-Schutz, zeigt Umleitungsziele an
und schreibt eine bereinigte Kopie – wahlweise als Firefox-JSON oder als
HTML-Datei für Firefox, Chrome und Edge.

© 2026 Siedenburg

---

## Funktionen

**Erreichbarkeitsprüfung**
- Parallele Prüfung aller Lesezeichen (Anzahl der gleichzeitigen Anfragen einstellbar)
- Lesbare Statusmeldungen statt nackter Fehlercodes („Seite nicht gefunden",
  „Zeitüberschreitung", „Zugriff verweigert" …), HTTP-Code in eigener Spalte
- Vier farbige Kategorien:
  - 🟢 **OK** – Seite erreichbar
  - 🟡 **Verdächtig** – 401/403/429 oder SSL-Fehler; die Seite lebt oft noch
  - 🟣 **Bot-Schutz** – Cloudflare & Co. blockieren die automatische Prüfung
    (erkannt an Challenge-Seiten und Server-Headern); im Browser meist erreichbar
  - 🔴 **Nicht verfügbar** – 404/410, Serverfehler, Timeout, Verbindungsfehler
- Ergebnisse erscheinen **live während der Prüfung**, nicht erst am Ende
- **Abbrechen-Button** – bereits geprüfte Ergebnisse bleiben erhalten
- Automatischer **zweiter Durchlauf bei 429** („zu viele Anfragen"): sequenziell,
  mit einstellbarer Wartezeit zwischen Anfragen an denselben Host
- Spalte **„Leitet um nach"** zeigt das Ziel dauerhafter Weiterleitungen
- Wählbares **Hervorheben** bestimmter Fehlerarten (404, Timeout, Bot-Schutz, 5xx)
- Filter (nur nicht verfügbare / + verdächtig & Bot / alle), Sortierung
  (Code-Spalte numerisch), **CSV-Report**
- **Anpassbarer User-Agent** für die Prüf-Anfragen

**Dubletten-Finder**
- Vergleich **nach URL** mit einstellbarer Normalisierung: Groß-/Kleinschreibung
  im Host, Anker (`#…`), End-Schrägstrich, Parameter (`?…`) und **Subdomains**
  (`www.`, `old.` … – `old.reddit.com` = `reddit.com`; zweiteilige Endungen wie
  `co.uk` werden korrekt behandelt)
- Alternativ Vergleich **nach Titel** (gleicher Titel, andere URL)
- Pro Gruppe wird automatisch der erste Eintrag zum Behalten vorgeschlagen
  (grün), der Rest zum Löschen markiert – jederzeit einzeln umstellbar

**Bearbeiten & Speichern**
- **Rechtsklick-Menü** auf jeder Zeile: *Im Browser öffnen*, *URL kopieren*,
  *URL bearbeiten…* und – falls vorhanden – *Umleitungsziel als URL übernehmen*
  (umgezogene Seiten mit einem Klick korrigieren)
- **Doppelklick** auf eine Zeile öffnet die Seite im Standardbrowser
  (Doppelklick auf die Redirect-Zelle öffnet das Umleitungsziel)
- **Löschen und Speichern sind getrennt:** „Markierte löschen" entfernt Einträge
  zunächst nur im Speicher – man kann beliebig weiterprüfen, löschen und
  korrigieren. „Speichern…" schreibt dann den Stand in eine **neue Datei**;
  die Originaldatei bleibt immer unangetastet
- **Nachfrage beim Schließen**, wenn ungespeicherte Änderungen vorliegen

**Formate & Konvertierung**
- Liest **Firefox-JSON** (Lesezeichen-Sicherung) und **HTML im
  Netscape-Bookmark-Format** (Firefox-HTML-Export, Chrome- und Edge-Favoriten)
- Speichert wahlweise als JSON **oder** HTML – unabhängig vom Quellformat
- **Exportieren…**-Button konvertiert die geladene Datei auch ohne Änderungen
  ins jeweils andere Format
- HTML → JSON erzeugt eine echte Firefox-Backup-Struktur (Wurzel-GUIDs,
  typeCodes, Zeitstempel) für „Sicherung wiederherstellen"
- Beim HTML-Rückschreiben bleiben Original-Attribute (ADD_DATE, ICON,
  Toolbar-Kennzeichnung) erhalten

**Oberfläche**
- Umschaltbar **Deutsch / Englisch** (oben rechts)
- **Dunkelmodus** (oben rechts), inkl. angepasster Signalfarben
- Farb-Legende unter der Ergebnistabelle

![Userinterface](https://github.com/siedenburg2/BookmarkChecker/blob/main/Screenshot.png?raw=true)

---

## Voraussetzungen

| Was | Details |
|---|---|
| Betriebssystem | Windows 10 / 11 |
| PowerShell | **PowerShell 7** (`pwsh`) – [Download](https://github.com/PowerShell/PowerShell/releases). Das vorinstallierte Windows PowerShell 5.1 reicht **nicht**; das Skript weist beim Start darauf hin. |
| Sonstiges | Keine Module, kein `pip`/`npm`, keine Adminrechte nötig |

---

## Installation & Start

1. `LesezeichenPruefer.ps1` herunterladen (oder Repository klonen).
2. Da die Datei aus dem Internet stammt, einmalig die Download-Sperre entfernen:

   ```powershell
   Unblock-File .\LesezeichenPruefer.ps1
   ```

3. Starten:

   ```powershell
   pwsh -File .\LesezeichenPruefer.ps1
   ```

   Alternativ: Rechtsklick → „Mit PowerShell 7 ausführen".

**Falls die Ausführungsrichtlinie blockt:** Entweder einmalig (empfohlen, ohne Adminrechte)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

oder pro Aufruf `pwsh -ExecutionPolicy Bypass -File .\LesezeichenPruefer.ps1`.
Das Skript startet sich bei Bedarf selbst im STA-Modus neu (für die Datei-Dialoge nötig).

---

## Lesezeichen exportieren (Eingabedatei erzeugen)

| Browser | Weg | Ergebnis |
|---|---|---|
| Firefox (JSON) | Lesezeichen verwalten (`Strg+Umschalt+O`) → Importieren und Sichern → **Sichern…** | `.json` |
| Firefox (HTML) | ebd. → **Lesezeichen nach HTML exportieren…** | `.html` |
| Chrome | Lesezeichen-Manager (`Strg+Umschalt+O`) → ⋮ → **Lesezeichen exportieren** | `.html` |
| Edge | Favoriten (`Strg+Umschalt+O`) → … → **Favoriten exportieren** | `.html` |

---

## Typischer Ablauf

1. **Lesezeichen-Datei öffnen…** – Format wird automatisch erkannt.
2. Reiter **Erreichbarkeit** → **Prüfung starten**. Problemfälle erscheinen live.
3. Ergebnisse sichten: Doppelklick öffnet die Seite, Rechtsklick bietet
   URL-Aktionen. Gelbe/violette Einträge im Zweifel selbst im Browser prüfen –
   Bot-Schutz heißt nicht tot.
4. Häkchen in der Löschen-Spalte setzen (oder „Alle markieren") →
   **Markierte löschen**.
5. Optional Reiter **Dubletten** → **Dubletten finden** → Vorschläge prüfen →
   **Markierte löschen**.
6. **Speichern…** – Zieldatei und Format wählen. Fertig; die Meldung erklärt
   den Re-Import in den jeweiligen Browser.

**Zurück in den Browser:**
- Firefox (JSON): Importieren und Sichern → **Sicherung wiederherstellen** –
  ⚠️ ersetzt alle vorhandenen Lesezeichen!
- Firefox (HTML): **Lesezeichen von HTML importieren** (fügt hinzu)
- Chrome/Edge: Lesezeichen-/Favoriten-Manager → **Importieren**

---

## Einstellungen (Reiter Erreichbarkeit)

| Option | Standard | Bedeutung |
|---|---|---|
| Timeout (s) | 10 | Wartezeit pro Anfrage |
| Parallel | 20 | Gleichzeitige Anfragen |
| Warten bei 429 (s) | 20 | Wartezeit der 429-Nachprüfrunde; `0` = aus |
| SSL-Zertifikate ignorieren | aus | Prüft auch Seiten mit kaputtem Zertifikat |
| User-Agent | Chrome-UA | Kennung, mit der sich das Tool ausweist |
| Hervorheben | aus | Gelber Hintergrund für 404 / Timeout / Bot / 5xx |

---

## Bekannte Grenzen

- **Bot-/DDoS-Schutz (violett)** lässt sich automatisiert nicht auflösen – diese
  Seiten sind im Browser fast immer erreichbar. Nicht blind löschen.
- Die Subdomain-Erkennung nutzt eine eingebaute Liste gängiger zweiteiliger
  Endungen (`co.uk`, `com.au`, …) statt der vollständigen Public Suffix List.
  Exotische Endungen können in `$TwoPartTlds` im Skript ergänzt werden.
- Beim HTML-Speichern gehen seltene `<DD>`-Beschreibungszeilen verloren;
  interne Firefox-Abfragen (`place:…`) werden beim HTML-Export ausgelassen.
- WinForms-bedingt bleiben im Dunkelmodus Scrollleisten, System-Dialoge,
  Fortschrittsbalken und der Menü-Hover im Windows-Design.
- Die Firefox-Funktion „Sicherung wiederherstellen" ist streng und **ersetzt**
  den Lesezeichenbestand – im Zweifel ist der HTML-Import der gutmütigere Weg.

## Fehlerbehebung

| Problem | Lösung |
|---|---|
| „Dieses Skript benötigt PowerShell 7" | PowerShell 7 installieren; Datei ggf. mit `pwsh` statt `powershell` starten |
| Skript startet nicht / Richtlinien-Fehler | `Unblock-File` ausführen bzw. `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| Viele 403/„Verdächtig"-Treffer | User-Agent-Feld anpassen und erneut prüfen; im Zweifel Seite per Doppelklick selbst öffnen |
| Viele 429-Treffer eines Hosts | „Warten bei 429" erhöhen – die zweite Runde prüft diese Einträge gemächlich nach |

---

## Über dieses Projekt

Dieses Tool ist ein **Vibe-Coding-Projekt**: Es wurde vollständig im Dialog mit
**Claude** (Anthropic) entwickelt – von der ersten Idee über alle Funktionen
bis zu dieser README. Konzept, Anforderungen, Tests und Feinschliff kamen aus
der Konversation; der Code wurde von der KI geschrieben und iterativ
verbessert. Fehlerberichte und Verbesserungsvorschläge sind willkommen.

## Lizenz

Dieses Projekt steht unter der **MIT-Lizenz** – siehe [LICENSE](LICENSE).

Das bedeutet konkret: Nutzung (auch **kommerziell**), Kopieren, **Verändern**
und Weiterverbreiten sind ausdrücklich erlaubt. Einzige Bedingung ist die
**Namensnennung**: Der Copyright-Vermerk „© 2026 Siedenburg" und der
Lizenztext müssen in allen Kopien bzw. wesentlichen Teilen der Software
erhalten bleiben. Die Software wird ohne Gewährleistung bereitgestellt.
