# Bookmark Checker

[Deutsch](README.md) | **English**

A Windows GUI tool for cleaning up browser bookmarks – written as a
**single PowerShell 7 script with no additional dependencies**.

It checks which saved pages are still reachable, finds duplicate bookmarks,
detects pages behind bot/DDoS protection, shows redirect targets and writes a
cleaned copy – either as Firefox JSON or as an HTML file for Firefox, Chrome
and Edge.

© 2026 Siedenburg

---

## Features

**Availability check**
- Parallel checking of all bookmarks (number of concurrent requests adjustable)
- Human-readable status messages instead of bare error codes ("Page not
  found", "Timeout", "Access denied" …), HTTP code in its own column
- Four color-coded categories:
  - 🟢 **OK** – page reachable
  - 🟡 **Suspicious** – 401/403/429 or SSL error; the page is often still alive
  - 🟣 **Bot protection** – Cloudflare & co. block the automated check
    (detected via challenge pages and server headers); usually fine in a browser
  - 🔴 **Unavailable** – 404/410, server errors, timeout, connection failure
- Results appear **live during the check**, not only at the end
- **Stop button** – results gathered so far are kept
- Automatic **second pass for 429** ("too many requests"): sequential, with a
  configurable wait between requests to the same host
- **"Redirects to"** column shows the target of permanent redirects
- Optional **highlighting** of selected error types (404, timeout, bot
  protection, 5xx)
- Filters (unavailable only / + suspicious & bot / all), sorting (code column
  sorts numerically), **CSV report**
- **Customizable user agent** for the check requests

**Duplicate finder**
- Comparison **by URL** with configurable normalization: host casing, anchors
  (`#…`), trailing slash, parameters (`?…`) and **subdomains** (`www.`,
  `old.` … – `old.reddit.com` = `reddit.com`; two-part endings such as
  `co.uk` are handled correctly)
- Alternatively, comparison **by title** (same title, different URL)
- The first entry of each group is automatically suggested to keep (green),
  the rest is marked for deletion – adjustable per entry at any time

**Editing & saving**
- **Right-click menu** on every row: *Open in browser*, *Copy URL*,
  *Edit URL…* and – when available – *Use redirect target as URL*
  (fix moved pages with a single click)
- **Double-click** on a row opens the page in the default browser
  (double-clicking the redirect cell opens the redirect target)
- **Deleting and saving are separate:** "Delete selected" removes entries in
  memory only – keep checking, deleting and fixing as long as you like.
  "Save…" then writes the current state to a **new file**; the original file
  is never touched
- **Confirmation on close** if there are unsaved changes

**Formats & conversion**
- Reads **Firefox JSON** (bookmark backup) and **HTML in Netscape bookmark
  format** (Firefox HTML export, Chrome and Edge favorites)
- Saves as JSON **or** HTML – regardless of the source format
- The **Export…** button also converts the loaded file to the other format
  without any changes
- HTML → JSON produces a genuine Firefox backup structure (root GUIDs,
  typeCodes, timestamps) suitable for "Restore"
- When writing HTML, original attributes (ADD_DATE, ICON, toolbar flag) are
  preserved

**Interface**
- Switchable **German / English** (top right)
- **Dark mode** (top right), including adjusted signal colors
- Color legend below the results table

![Userinterface](https://github.com/siedenburg2/BookmarkChecker/blob/main/Screenshot-en.png?raw=true)

---

## Requirements

| What | Details |
|---|---|
| Operating system | Windows 10 / 11 |
| PowerShell | **PowerShell 7** (`pwsh`) – [download](https://github.com/PowerShell/PowerShell/releases). The preinstalled Windows PowerShell 5.1 is **not** sufficient; the script shows a notice on startup. |
| Other | No modules, no `pip`/`npm`, no admin rights required |

---

## Installation & start

1. Download `LesezeichenPruefer.ps1` (or clone the repository).
2. Since the file comes from the internet, remove the download block once:

   ```powershell
   Unblock-File .\LesezeichenPruefer.ps1
   ```

3. Run it:

   ```powershell
   pwsh -File .\LesezeichenPruefer.ps1
   ```

   Alternatively: right-click → "Run with PowerShell 7".

**If the execution policy blocks the script:** either once (recommended, no
admin rights needed)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

or per invocation `pwsh -ExecutionPolicy Bypass -File .\LesezeichenPruefer.ps1`.
If needed, the script relaunches itself in STA mode (required for the file
dialogs).

---

## Exporting bookmarks (creating the input file)

| Browser | Path | Result |
|---|---|---|
| Firefox (JSON) | Manage bookmarks (`Ctrl+Shift+O`) → Import and Backup → **Backup…** | `.json` |
| Firefox (HTML) | same menu → **Export Bookmarks to HTML…** | `.html` |
| Chrome | Bookmark manager (`Ctrl+Shift+O`) → ⋮ → **Export bookmarks** | `.html` |
| Edge | Favorites (`Ctrl+Shift+O`) → … → **Export favorites** | `.html` |

---

## Typical workflow

1. **Open bookmark file…** – the format is detected automatically.
2. **Availability** tab → **Start check**. Problem cases appear live.
3. Review the results: double-click opens the page, right-click offers URL
   actions. When in doubt, open yellow/purple entries in the browser yourself –
   bot protection does not mean dead.
4. Tick the delete column (or "Select all") → **Delete selected**.
5. Optionally switch to the **Duplicates** tab → **Find duplicates** → review
   the suggestions → **Delete selected**.
6. **Save…** – choose target file and format. Done; the message explains how
   to re-import into your browser.

**Back into the browser:**
- Firefox (JSON): Import and Backup → **Restore** –
  ⚠️ replaces all existing bookmarks!
- Firefox (HTML): **Import Bookmarks from HTML** (additive)
- Chrome/Edge: bookmark/favorites manager → **Import**

---

## Settings (Availability tab)

| Option | Default | Meaning |
|---|---|---|
| Timeout (s) | 10 | Wait time per request |
| Parallel | 20 | Concurrent requests |
| Wait on 429 (s) | 20 | Wait time of the 429 retry pass; `0` = off |
| Ignore SSL certificates | off | Also checks pages with broken certificates |
| User agent | Chrome UA | Identity the tool presents to servers |
| Highlight | off | Yellow background for 404 / timeout / bot / 5xx |

---

## Known limitations

- **Bot/DDoS protection (purple)** cannot be resolved automatically – these
  pages are almost always reachable in a browser. Don't delete them blindly.
- Subdomain detection uses a built-in list of common two-part endings
  (`co.uk`, `com.au`, …) instead of the full Public Suffix List. Exotic
  endings can be added to `$TwoPartTlds` in the script.
- Rare `<DD>` description lines are lost when saving HTML; internal Firefox
  queries (`place:…`) are omitted from HTML exports.
- Due to WinForms, scroll bars, system dialogs, the progress bar and the menu
  hover keep the Windows look in dark mode.
- Firefox's "Restore" feature is strict and **replaces** the bookmark
  collection – when in doubt, the HTML import is the gentler route.

## Troubleshooting

| Problem | Solution |
|---|---|
| "This script requires PowerShell 7" | Install PowerShell 7; start the file with `pwsh` instead of `powershell` |
| Script won't start / policy error | Run `Unblock-File` or `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| Many 403/"suspicious" hits | Adjust the user-agent field and re-check; when in doubt, open the page via double-click |
| Many 429 hits on one host | Increase "Wait on 429" – the second pass rechecks those entries gently |

---

## About this project

This tool is a **vibe-coding project**: it was developed entirely in
conversation with **Claude** (Anthropic) – from the initial idea through every
feature to this README. Concept, requirements, testing and polish came from
the dialogue; the code was written and iteratively improved by the AI. Bug
reports and suggestions are welcome.

## License

This project is licensed under the **MIT License** – see [LICENSE](LICENSE).

In practice this means: use (including **commercial** use), copying,
**modification** and redistribution are expressly permitted. The only
condition is **attribution**: the copyright notice "© 2026 Siedenburg" and the
license text must be preserved in all copies or substantial portions of the
software. The software is provided without warranty of any kind.
