<#
    Lesezeichen-Prüfer  (PowerShell 7 + WinForms)
    (c) 2026 Siedenburg
    ======================================================
    Öffnet Lesezeichen-Exporte als JSON (Firefox) oder HTML (Firefox, Chrome,
    Edge - "Netscape Bookmark"-Format) und bietet zwei Werkzeuge in Reitern:

      1) Erreichbarkeit  - prüft parallel, ob die Seiten noch erreichbar sind,
                           listet Problemfälle live während der Prüfung auf
                           und lässt ausgewählte Einträge löschen.
      2) Dubletten       - findet mehrfach gespeicherte Lesezeichen und lässt
                           pro Gruppe eines behalten, den Rest löschen.

    Extras: GUI umschaltbar Deutsch/Englisch, Farb-Legende, Hervorheben
    bestimmter Fehler (404, Zeitüberschreitung, Bot-Schutz, Serverfehler),
    eigene Kategorie für Seiten hinter DDoS-/Bot-Schutz, Doppelklick öffnet
    die Seite im Standardbrowser, zweiter Prüfdurchlauf mit einstellbarer
    Wartezeit für Seiten, die wegen zu vieler Anfragen (429) blocken -
    dabei wird zwischen Anfragen an denselben Host jeweils gewartet.

    Die Originaldatei bleibt unverändert; gespeichert wird eine neue Kopie.

    Voraussetzung: Windows + PowerShell 7 (pwsh). Keine weiteren Abhängigkeiten.
    Start:   pwsh -File .\LesezeichenPruefer.ps1
	Start mit bypass: pwsh -ExecutionPolicy Bypass -File '.\LesezeichenPruefer.ps1'
#>

# --- PowerShell-7-Pruefung ---
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Dieses Skript benötigt PowerShell 7 (pwsh).`nThis script requires PowerShell 7 (pwsh).",
        'PowerShell 7', 'OK', 'Warning') | Out-Null
    return
}

# --- STA sicherstellen (WinForms-Dialoge brauchen einen STA-Thread) ---
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    Start-Process -FilePath 'pwsh' -ArgumentList @(
        '-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`""
    )
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36'

# ---------------------------------------------------------------------------
# Sprachtabellen
# ---------------------------------------------------------------------------
$Loc = @{
    de = @{
        app_title   = 'Lesezeichen-Prüfer'
        btn_open    = 'Lesezeichen-Datei öffnen...'
        btn_export  = 'Exportieren...'
        btn_del     = 'Markierte löschen'
        btn_stop    = 'Abbrechen'
        aborted     = 'Abgebrochen - {0} Ergebnisse übernommen.'
        deleted     = '{0} Einträge entfernt - noch nicht gespeichert.'
        col_redirect= 'Leitet um nach'
        lbl_dupmode = 'Vergleichen nach:'
        dm_url      = 'URL'
        dm_title    = 'Titel'
        bad_url     = 'Ungültige URL (http/https erwartet) - Änderung verworfen.'
        url_saved   = 'URL geändert - wird beim Speichern übernommen.'
        confirm_close = "Es gibt ungespeicherte Änderungen.`nTrotzdem schließen?"
        lbl_ua      = 'User-Agent:'
        ctx_open    = 'Im Browser öffnen'
        ctx_copy    = 'URL kopieren'
        ctx_edit    = 'URL bearbeiten...'
        ctx_redir   = 'Umleitungsziel als URL übernehmen'
        t_ok        = 'OK'
        t_cancel    = 'Abbrechen'
        sfx_clean   = '_bereinigt'
        no_file     = 'Keine Datei geladen'
        tab_av      = 'Erreichbarkeit'
        tab_dup     = 'Dubletten'
        lbl_timeout = 'Timeout (s):'
        lbl_parallel= 'Parallel:'
        chk_ssl     = 'SSL-Zertifikate ignorieren'
        lbl_show    = 'Anzeigen:'
        f_dead      = 'Nur nicht verfügbare'
        f_deadsusp  = 'Nicht verfügbar + verdächtig/Bot'
        f_all       = 'Alle'
        lbl_hl      = 'Hervorheben:'
        h_404       = '404 (Nicht gefunden)'
        h_timeout   = 'Zeitüberschreitung'
        h_bot       = 'Bot-Schutz'
        h_5xx       = 'Serverfehler (5xx)'
        lbl_retry   = 'Warten bei 429 (s, 0 = aus):'
        chk_dark    = 'Dunkelmodus'
        btn_check   = 'Prüfung starten'
        btn_all     = 'Alle markieren'
        btn_none    = 'Alle abwählen'
        btn_csv     = 'CSV-Report...'
        btn_save    = 'Speichern...'
        btn_finddup = 'Dubletten finden'
        btn_keep1   = 'Pro Gruppe nur erste behalten'
        cmp_ignore  = 'Beim Vergleich ignorieren:'
        cmp_case    = 'Groß/Klein (Host)'
        cmp_frag    = 'Anker (#...)'
        cmp_slash   = 'End-Schrägstrich'
        cmp_query   = 'Parameter (?...)'
        cmp_sub     = 'Subdomains (www., old., ...)'
        col_del     = 'Löschen'
        col_status  = 'Status'
        col_code    = 'Code'
        col_title   = 'Titel'
        col_url     = 'URL'
        col_folder  = 'Ordner'
        col_group   = 'Gruppe'
        checking    = 'Prüfe {0}/{1} ...'
        retrying    = '2. Versuch (429) mit {0} s Wartezeit: {1}/{2} ...'
        done        = 'Fertig: {0} nicht verfügbar, {1} hinter Bot-Schutz.'
        loaded      = '{0}   ({1} Lesezeichen gefunden)'
        remaining   = '{0}   ({1} Lesezeichen verbleibend)'
        no_http     = 'Keine http/https-Lesezeichen gefunden.'
        t_hint      = 'Hinweis'
        t_error     = 'Fehler'
        t_confirm   = 'Bestätigen'
        t_done      = 'Fertig'
        no_marked   = 'Es sind keine Einträge zum Löschen markiert.'
        confirm_del = "{0} {1} werden aus der Kopie entfernt.`nDie Originaldatei bleibt unverändert.`n`nFortfahren?"
        items_bk    = 'Lesezeichen'
        items_dup   = 'Dubletten'
        save_title  = 'Bereinigte Datei speichern'
        csv_title   = 'CSV speichern'
        saved       = "Gespeichert:`n{0}`n`nIn Firefox wieder einlesen über:`nLesezeichen verwalten (Strg+Umschalt+O) -> Importieren und Sichern -> Sicherung wiederherstellen -> Datei wählen ..."
        saved_html  = "Gespeichert:`n{0}`n`nWieder importieren über:`nFirefox: Lesezeichen verwalten -> Importieren und Sichern -> Lesezeichen von HTML importieren`nChrome/Edge: Lesezeichen-/Favoriten-Manager -> Importieren"
        no_results  = 'Es liegen keine Ergebnisse vor.'
        csv_saved   = "CSV gespeichert:`n{0}"
        dup_status  = '{0} Gruppen mit Dubletten, {1} überzählige Einträge. Grün = Vorschlag zum Behalten.'
        no_dups     = 'Keine Dubletten gefunden.'
        saved_av    = 'Gespeichert. Bei Bedarf erneut prüfen.'
        saved_dup   = 'Gespeichert. Bei Bedarf erneut suchen.'
        load_err    = "Fehler beim Laden:`n{0}"
        save_err    = "Fehler beim Speichern:`n{0}"
        lbl_legend  = 'Farben:'
        leg_hl      = 'Hervorgehoben'
        hint_dbl    = 'Doppelklick öffnet die Seite; Rechtsklick für URL-Aktionen.'
        suf_retry   = '(2. Versuch)'
        # Status-Texte (lesbar, ohne den Code zu wiederholen)
        st_ok       = 'OK'
        st_notfound = 'Seite nicht gefunden'
        st_gone     = 'Dauerhaft entfernt'
        st_server   = 'Serverfehler'
        st_timeout  = 'Zeitüberschreitung'
        st_conn     = 'Server nicht erreichbar'
        st_ssl      = 'SSL-Zertifikatsfehler'
        st_auth     = 'Anmeldung erforderlich'
        st_forbidden= 'Zugriff verweigert'
        st_ratelimit= 'Zu viele Anfragen'
        st_bot      = 'Bot-/DDoS-Schutz aktiv'
        st_err      = 'HTTP-Fehler'
        cat_ok      = 'OK'
        cat_susp    = 'Verdächtig'
        cat_tot     = 'Nicht verfügbar'
        cat_bot     = 'Bot-Schutz'
    }
    en = @{
        app_title   = 'Bookmark Checker'
        btn_open    = 'Open bookmark file...'
        btn_export  = 'Export...'
        btn_del     = 'Delete selected'
        btn_stop    = 'Stop'
        aborted     = 'Aborted - {0} results kept.'
        deleted     = '{0} entries removed - not saved yet.'
        col_redirect= 'Redirects to'
        lbl_dupmode = 'Compare by:'
        dm_url      = 'URL'
        dm_title    = 'Title'
        bad_url     = 'Invalid URL (http/https expected) - change discarded.'
        url_saved   = 'URL changed - will be applied on save.'
        confirm_close = "There are unsaved changes.`nClose anyway?"
        lbl_ua      = 'User agent:'
        ctx_open    = 'Open in browser'
        ctx_copy    = 'Copy URL'
        ctx_edit    = 'Edit URL...'
        ctx_redir   = 'Use redirect target as URL'
        t_ok        = 'OK'
        t_cancel    = 'Cancel'
        sfx_clean   = '_cleaned'
        no_file     = 'No file loaded'
        tab_av      = 'Availability'
        tab_dup     = 'Duplicates'
        lbl_timeout = 'Timeout (s):'
        lbl_parallel= 'Parallel:'
        chk_ssl     = 'Ignore SSL certificates'
        lbl_show    = 'Show:'
        f_dead      = 'Unavailable only'
        f_deadsusp  = 'Unavailable + suspicious/bot'
        f_all       = 'All'
        lbl_hl      = 'Highlight:'
        h_404       = '404 (Not found)'
        h_timeout   = 'Timeout'
        h_bot       = 'Bot protection'
        h_5xx       = 'Server errors (5xx)'
        lbl_retry   = 'Wait on 429 (s, 0 = off):'
        chk_dark    = 'Dark mode'
        btn_check   = 'Start check'
        btn_all     = 'Select all'
        btn_none    = 'Deselect all'
        btn_csv     = 'CSV report...'
        btn_save    = 'Save...'
        btn_finddup = 'Find duplicates'
        btn_keep1   = 'Keep only first per group'
        cmp_ignore  = 'Ignore when comparing:'
        cmp_case    = 'Case (host)'
        cmp_frag    = 'Anchor (#...)'
        cmp_slash   = 'Trailing slash'
        cmp_query   = 'Parameters (?...)'
        cmp_sub     = 'Subdomains (www., old., ...)'
        col_del     = 'Delete'
        col_status  = 'Status'
        col_code    = 'Code'
        col_title   = 'Title'
        col_url     = 'URL'
        col_folder  = 'Folder'
        col_group   = 'Group'
        checking    = 'Checking {0}/{1} ...'
        retrying    = 'Retry pass (429) with {0}s wait: {1}/{2} ...'
        done        = 'Done: {0} unavailable, {1} behind bot protection.'
        loaded      = '{0}   ({1} bookmarks found)'
        remaining   = '{0}   ({1} bookmarks remaining)'
        no_http     = 'No http/https bookmarks found.'
        t_hint      = 'Note'
        t_error     = 'Error'
        t_confirm   = 'Confirm'
        t_done      = 'Done'
        no_marked   = 'No entries are selected for deletion.'
        confirm_del = "{0} {1} will be removed from the copy.`nThe original file remains untouched.`n`nContinue?"
        items_bk    = 'bookmarks'
        items_dup   = 'duplicates'
        save_title  = 'Save cleaned file'
        csv_title   = 'Save CSV'
        saved       = "Saved:`n{0}`n`nRestore in Firefox via:`nManage bookmarks (Ctrl+Shift+O) -> Import and Backup -> Restore -> Choose file ..."
        saved_html  = "Saved:`n{0}`n`nRe-import via:`nFirefox: Manage bookmarks -> Import and Backup -> Import Bookmarks from HTML`nChrome/Edge: Bookmark/Favorites manager -> Import"
        no_results  = 'There are no results yet.'
        csv_saved   = "CSV saved:`n{0}"
        dup_status  = '{0} duplicate groups, {1} redundant entries. Green = suggested to keep.'
        no_dups     = 'No duplicates found.'
        saved_av    = 'Saved. Re-run the check if needed.'
        saved_dup   = 'Saved. Search again if needed.'
        load_err    = "Failed to load:`n{0}"
        save_err    = "Failed to save:`n{0}"
        lbl_legend  = 'Colors:'
        leg_hl      = 'Highlighted'
        hint_dbl    = 'Double-click opens the page; right-click for URL actions.'
        suf_retry   = '(retried)'
        st_ok       = 'OK'
        st_notfound = 'Page not found'
        st_gone     = 'Permanently removed'
        st_server   = 'Server error'
        st_timeout  = 'Timeout'
        st_conn     = 'Server unreachable'
        st_ssl      = 'SSL certificate error'
        st_auth     = 'Login required'
        st_forbidden= 'Access denied'
        st_ratelimit= 'Too many requests'
        st_bot      = 'Bot/DDoS protection active'
        st_err      = 'HTTP error'
        cat_ok      = 'OK'
        cat_susp    = 'Suspicious'
        cat_tot     = 'Unavailable'
        cat_bot     = 'Bot protection'
    }
}
$script:Lang = 'de'
$script:L = $Loc[$script:Lang]
function T([string]$k) { [string]$script:L[$k] }

# Setzt lokalisierten Text auf ein Label und merkt sich Schluessel + Argumente,
# damit der Text beim Sprachwechsel neu gerendert werden kann
function Set-LocText {
    param($Label, [string]$Key, [object[]]$Fmt = @())
    $Label.Tag = @{ Key = $Key; Fmt = $Fmt }
    if (-not $Key) { $Label.Text = ''; return }
    $Label.Text = if ($Fmt.Count -gt 0) { (T $Key) -f $Fmt } else { T $Key }
}

# ---------------------------------------------------------------------------
# Skript-weiter Zustand
# ---------------------------------------------------------------------------
$script:Data      = $null
$script:Items     = @()
$script:ItemById  = @{}
$script:FilePath  = $null
$script:AvResults = @{}
$script:RowById   = @{}
$script:Queue     = $null
$script:Handles   = @()
$script:Pool      = $null
$script:Processed = 0
$script:Total     = 0
$script:Running   = $false
$script:Phase     = 1
$script:RetryWait = 0
$script:UpdatingUi = $false
$script:Dark      = $false
$script:Format    = 'json'
$script:Dirty     = $false
$script:UaCur     = $UA
$script:Copyright = [string][char]0x00A9 + ' 2026 Siedenburg'

# ---------------------------------------------------------------------------
# Baum einsammeln / löschen / URL normalisieren
# ---------------------------------------------------------------------------
function Collect-Bookmarks {
    param($Node, [string[]]$Folder, [System.Collections.ArrayList]$Out)
    if ($null -eq $Node) { return }
    $props = $Node.PSObject.Properties.Name
    if (($props -contains 'type') -and $Node.type -eq 'text/x-moz-place') {
        $uri = $Node.uri
        if ($uri -and ($uri.StartsWith('http://') -or $uri.StartsWith('https://'))) {
            if (-not ($props -contains '__id')) {
                $Node | Add-Member -NotePropertyName '__id' `
                    -NotePropertyValue ([guid]::NewGuid().ToString()) -Force
            }
            $folderText = ($Folder | Where-Object { $_ }) -join ' / '
            if (-not $folderText) { $folderText = '(Root)' }
            [void]$Out.Add([pscustomobject]@{
                Node   = $Node
                Id     = $Node.__id
                Folder = $folderText
                Title  = [string]$Node.title
                Url    = [string]$uri
            })
        }
    }
    if (($props -contains 'children') -and $Node.children) {
        $childFolder = $Folder + @([string]$Node.title)
        foreach ($c in $Node.children) { Collect-Bookmarks -Node $c -Folder $childFolder -Out $Out }
    }
}

function Rebuild-Items {
    $list = New-Object System.Collections.ArrayList
    Collect-Bookmarks -Node $script:Data -Folder @() -Out $list
    $script:Items = $list.ToArray()
    $script:ItemById = @{}
    foreach ($it in $script:Items) { $script:ItemById[$it.Id] = $it }
}

function Prune-Tree {
    param($Node, [System.Collections.Generic.HashSet[string]]$DelSet)
    if ($null -eq $Node) { return }
    $props = $Node.PSObject.Properties.Name
    if (($props -contains 'children') -and $Node.children) {
        $Node.children = @($Node.children | Where-Object {
            $cp = $_.PSObject.Properties.Name
            -not (($cp -contains '__id') -and $DelSet.Contains([string]$_.__id))
        })
        foreach ($c in $Node.children) { Prune-Tree -Node $c -DelSet $DelSet }
    }
}

function Strip-Ids {
    param($Node)
    if ($null -eq $Node) { return }
    $props = $Node.PSObject.Properties.Name
    if ($props -contains '__id') { $Node.PSObject.Properties.Remove('__id') }
    if (($props -contains 'children') -and $Node.children) {
        foreach ($c in $Node.children) { Strip-Ids -Node $c }
    }
}

# Liefert die registrierbare Domain (Domain + TLD) eines Hostnamens, entfernt
# also vorangestellte Subdomain-Ebenen wie "www." oder "old.". Zweiteilige
# Endungen (co.uk, com.au, ...) werden ueber eine eingebaute Liste erkannt.
$TwoPartTlds = @(
    'co.uk','org.uk','me.uk','ac.uk','gov.uk','net.uk','sch.uk','ltd.uk','plc.uk',
    'com.au','net.au','org.au','edu.au','gov.au','id.au','asn.au',
    'co.nz','net.nz','org.nz','govt.nz','ac.nz',
    'co.jp','or.jp','ne.jp','ac.jp','go.jp','ad.jp',
    'com.br','net.br','org.br','gov.br','edu.br',
    'com.mx','org.mx','com.ar','com.co','com.pe','com.ve','com.uy','com.ec',
    'co.za','org.za','net.za','web.za',
    'com.tr','net.tr','org.tr','gen.tr',
    'com.cn','net.cn','org.cn','gov.cn','edu.cn',
    'com.hk','com.tw','com.sg','com.my','com.ph','com.vn',
    'co.th','co.id','co.in','net.in','org.in','ac.in','gov.in',
    'co.kr','or.kr','ac.kr','com.ua','in.ua','com.pl','edu.pl',
    'com.eg','com.sa','com.pk','com.bd','com.ng'
)
function Get-BaseDomain {
    param([string]$HostName)
    if (-not $HostName) { return $HostName }
    $ip = $null
    if ([System.Net.IPAddress]::TryParse($HostName, [ref]$ip)) { return $HostName }
    $parts = $HostName.Split('.')
    if ($parts.Count -le 2) { return $HostName }
    $lastTwo = ($parts[-2..-1] -join '.').ToLower()
    $keep = if ($TwoPartTlds -contains $lastTwo) { 3 } else { 2 }
    if ($parts.Count -le $keep) { return $HostName }
    return ($parts[($parts.Count - $keep)..($parts.Count - 1)] -join '.')
}

function Normalize-Url {
    param([string]$Url, [bool]$IgnFrag, [bool]$IgnSlash, [bool]$IgnQuery,
          [bool]$CiHost, [bool]$IgnSub)
    try { $u = [uri]$Url } catch { return $Url }
    $scheme = $u.Scheme.ToLower()
    $hostName = $u.Host
    if ($CiHost) { $hostName = $hostName.ToLower() }
    if ($IgnSub) { $hostName = Get-BaseDomain $hostName }
    $netloc = if ($u.IsDefaultPort) { $hostName } else { "{0}:{1}" -f $hostName, $u.Port }
    $path = $u.AbsolutePath
    if ($IgnSlash -and $path.Length -gt 1 -and $path.EndsWith('/')) { $path = $path.TrimEnd('/') }
    $query = if ($IgnQuery) { '' } else { $u.Query }
    $frag  = if ($IgnFrag)  { '' } else { $u.Fragment }
    # Bei aktivem Subdomain-Ignorieren zaehlt nur Domain+TLD+Pfad -> dann
    # auch das Schema (http/https) nicht unterscheiden
    $prefix = if ($IgnSub) { '' } else { "$scheme`://" }
    return "$prefix$netloc$path$query$frag"
}

# ---------------------------------------------------------------------------
# HTML-Lesezeichen (Netscape-Format: Firefox-HTML-Export, Chrome/Edge-Favoriten)
# Der Parser erzeugt denselben Baum wie der JSON-Pfad (type/title/uri/children),
# merkt sich aber je Eintrag die Original-Attribute (__attrs: ADD_DATE, ICON,
# PERSONAL_TOOLBAR_FOLDER, ...), damit beim Speichern nichts verloren geht.
# ---------------------------------------------------------------------------
function ConvertFrom-BookmarkHtml {
    param([string]$Html)
    $root = [pscustomobject]@{
        type     = 'text/x-moz-place-container'
        title    = ''
        children = New-Object System.Collections.ArrayList
    }
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $pending = $null
    $rx = [regex]'(?is)<DL[^>]*>|</DL\s*>|<DT>\s*<H3([^>]*)>(.*?)</H3>|<DT>\s*<A([^>]*)>(.*?)</A>|<HR[^>]*>'
    foreach ($m in $rx.Matches($Html)) {
        $tok = $m.Value
        if ($tok -match '^(?i)</DL') {
            if ($stack.Count -gt 1) { [void]$stack.Pop() }
        }
        elseif ($tok -match '^(?i)<DL') {
            if ($pending) {
                [void]$stack.Peek().children.Add($pending)
                $stack.Push($pending)
                $pending = $null
            } else {
                # Root-Liste (oder verirrte anonyme Liste): Top duplizieren,
                # damit das zugehoerige </DL> die Balance nicht zerstoert
                $stack.Push($stack.Peek())
            }
        }
        elseif ($tok -match '^(?i)<HR') {
            [void]$stack.Peek().children.Add([pscustomobject]@{ type = 'separator' })
        }
        elseif ($m.Groups[2].Success -or $m.Groups[1].Success) {
            # Ordner (H3); die zugehoerige <DL> folgt als naechstes Token
            $pending = [pscustomobject]@{
                type     = 'text/x-moz-place-container'
                title    = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value).Trim()
                children = New-Object System.Collections.ArrayList
                __attrs  = $m.Groups[1].Value
            }
        }
        else {
            # Lesezeichen (A)
            $attrs = $m.Groups[3].Value
            $href = ''
            if ($attrs -match '(?i)HREF\s*=\s*"([^"]*)"') { $href = $matches[1] }
            elseif ($attrs -match "(?i)HREF\s*=\s*'([^']*)'") { $href = $matches[1] }
            $node = [pscustomobject]@{
                type    = 'text/x-moz-place'
                title   = [System.Net.WebUtility]::HtmlDecode($m.Groups[4].Value).Trim()
                uri     = [System.Net.WebUtility]::HtmlDecode($href)
                __attrs = $attrs
            }
            [void]$stack.Peek().children.Add($node)
        }
    }
    return $root
}

function Write-BmChildren {
    param($Node, [System.Text.StringBuilder]$Sb, [string]$Indent)
    foreach ($c in @($Node.children)) {
        $props = $c.PSObject.Properties.Name
        $attrs = if ($props -contains '__attrs') { [string]$c.__attrs } else { '' }
        if ($c.type -eq 'text/x-moz-place-container') {
            $isRoot = $props -contains 'root'
            $kidCount = if (($props -contains 'children') -and $c.children) { @($c.children).Count } else { 0 }
            # Leere Firefox-Wurzelordner (mobile, unfiled, ...) nicht exportieren
            if ($isRoot -and $kidCount -eq 0) { continue }
            if (-not $attrs) {
                if (($props -contains 'dateAdded') -and $c.dateAdded) {
                    $attrs += ' ADD_DATE="' + [long]([long]$c.dateAdded / 1000000) + '"'
                }
                if ($isRoot -and $c.root -eq 'toolbarFolder') {
                    $attrs += ' PERSONAL_TOOLBAR_FOLDER="true"'
                }
            }
            $t = [System.Net.WebUtility]::HtmlEncode([string]$c.title)
            [void]$Sb.AppendLine("$Indent<DT><H3$attrs>$t</H3>")
            [void]$Sb.AppendLine("$Indent<DL><p>")
            Write-BmChildren -Node $c -Sb $Sb -Indent ($Indent + '    ')
            [void]$Sb.AppendLine("$Indent</DL><p>")
        }
        elseif ($c.type -eq 'text/x-moz-place') {
            $uri = [string]$c.uri
            # Interne Firefox-Abfragen (place:...) sind nicht importierbar
            if ($uri.StartsWith('place:')) { continue }
            $t = [System.Net.WebUtility]::HtmlEncode([string]$c.title)
            if (-not $attrs) {
                $attrs = ' HREF="' + [System.Net.WebUtility]::HtmlEncode($uri) + '"'
                if (($props -contains 'dateAdded') -and $c.dateAdded) {
                    $attrs += ' ADD_DATE="' + [long]([long]$c.dateAdded / 1000000) + '"'
                }
            }
            [void]$Sb.AppendLine("$Indent<DT><A$attrs>$t</A>")
        }
        elseif ($c.type -eq 'separator' -or $c.type -eq 'text/x-moz-place-separator') {
            [void]$Sb.AppendLine("$Indent<HR>")
        }
    }
}

function ConvertTo-BookmarkHtml {
    param($Root)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
    [void]$sb.AppendLine('<!-- This is an automatically generated file.')
    [void]$sb.AppendLine('     It will be read and overwritten.')
    [void]$sb.AppendLine('     DO NOT EDIT! -->')
    [void]$sb.AppendLine('<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">')
    [void]$sb.AppendLine('<TITLE>Bookmarks</TITLE>')
    [void]$sb.AppendLine('<H1>Bookmarks</H1>')
    [void]$sb.AppendLine('<DL><p>')
    Write-BmChildren -Node $Root -Sb $sb -Indent '    '
    [void]$sb.AppendLine('</DL><p>')
    return $sb.ToString()
}

# ---------------------------------------------------------------------------
# HTML-Baum -> Firefox-Backup-JSON (wiederherstellbar ueber "Sicherung
# wiederherstellen"). Erzeugt die von Firefox erwartete Struktur mit den
# festen Wurzel-GUIDs, typeCode-Feldern und Mikrosekunden-Zeitstempeln.
# Der Ordner mit PERSONAL_TOOLBAR_FOLDER wird der Lesezeichen-Symbolleiste
# zugeordnet, alles Uebrige dem Lesezeichen-Menue.
# ---------------------------------------------------------------------------
function New-MozGuid {
    $chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
    -join (1..12 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}
function Get-AttrDateUs {
    param([string]$Attrs, [string]$Name, [long]$Default)
    if ($Attrs -and $Attrs -match ('(?i)' + $Name + '\s*=\s*"(\d+)"')) {
        return [long]$matches[1] * 1000000
    }
    return $Default
}
function ConvertTo-MozNode {
    param($Node, [int]$Index, [long]$NowUs)
    $script:MozId++
    $props = $Node.PSObject.Properties.Name
    $attrs = if ($props -contains '__attrs') { [string]$Node.__attrs } else { '' }
    $added = Get-AttrDateUs -Attrs $attrs -Name 'ADD_DATE' -Default $NowUs
    $mod   = Get-AttrDateUs -Attrs $attrs -Name 'LAST_MODIFIED' -Default $added
    $o = [ordered]@{
        guid = New-MozGuid; title = [string]$Node.title; index = $Index
        dateAdded = $added; lastModified = $mod; id = $script:MozId
    }
    if ($Node.type -eq 'text/x-moz-place-container') {
        $o.typeCode = 2; $o.type = 'text/x-moz-place-container'
        $kids = @(); $i = 0
        foreach ($c in @($Node.children)) {
            $kids += , (ConvertTo-MozNode -Node $c -Index $i -NowUs $NowUs); $i++
        }
        if ($kids.Count -gt 0) { $o.children = $kids }
    }
    elseif ($Node.type -eq 'separator' -or $Node.type -eq 'text/x-moz-place-separator') {
        $o.typeCode = 3; $o.type = 'text/x-moz-place-separator'
    }
    else {
        $o.typeCode = 1; $o.type = 'text/x-moz-place'; $o.uri = [string]$Node.uri
    }
    return [pscustomobject]$o
}
function New-MozRoot {
    param([string]$Guid, [string]$Title, [string]$RootName, [int]$Index,
          $Kids, [long]$NowUs, [int]$Id)
    $ch = @(); $i = 0
    foreach ($k in @($Kids)) {
        $ch += , (ConvertTo-MozNode -Node $k -Index $i -NowUs $NowUs); $i++
    }
    return [pscustomobject]([ordered]@{
        guid = $Guid; title = $Title; index = $Index
        dateAdded = $NowUs; lastModified = $NowUs; id = $Id
        typeCode = 2; type = 'text/x-moz-place-container'
        root = $RootName; children = $ch
    })
}
function ConvertTo-FirefoxJson {
    param($Root)
    $nowUs = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) * 1000
    $toolbarKids = @(); $menuKids = @()
    foreach ($c in @($Root.children)) {
        $p = $c.PSObject.Properties.Name
        $isToolbar = ($c.type -eq 'text/x-moz-place-container') -and
                     ($p -contains '__attrs') -and
                     ($c.__attrs -match '(?i)PERSONAL_TOOLBAR_FOLDER\s*=\s*"?true')
        if ($isToolbar) {
            foreach ($k in @($c.children)) { $toolbarKids += , $k }
        } else {
            $menuKids += , $c
        }
    }
    $script:MozId = 5   # 1 = Root, 2-5 = die vier festen Wurzeln
    $menu    = New-MozRoot -Guid 'menu________' -Title 'menu'    -RootName 'bookmarksMenuFolder'    -Index 0 -Kids $menuKids    -NowUs $nowUs -Id 2
    $toolbar = New-MozRoot -Guid 'toolbar_____' -Title 'toolbar' -RootName 'toolbarFolder'          -Index 1 -Kids $toolbarKids -NowUs $nowUs -Id 3
    $unfiled = New-MozRoot -Guid 'unfiled_____' -Title 'unfiled' -RootName 'unfiledBookmarksFolder' -Index 2 -Kids @()          -NowUs $nowUs -Id 4
    $mobile  = New-MozRoot -Guid 'mobile______' -Title 'mobile'  -RootName 'mobileFolder'           -Index 3 -Kids @()          -NowUs $nowUs -Id 5
    return [pscustomobject]([ordered]@{
        guid = 'root________'; title = ''; index = 0
        dateAdded = $nowUs; lastModified = $nowUs; id = 1
        typeCode = 2; type = 'text/x-moz-place-container'
        root = 'placesRoot'
        children = @($menu, $toolbar, $unfiled, $mobile)
    })
}

# Schreibt den aktuell geladenen Baum in eine Datei - im gewuenschten Format,
# unabhaengig vom Quellformat (JSON <-> HTML Konvertierung).
function Export-Bookmarks {
    param([string]$Path, [string]$OutFmt)
    if ($OutFmt -eq 'html') {
        $out = ConvertTo-BookmarkHtml -Root $script:Data
        Set-Content -LiteralPath $Path -Value $out -Encoding utf8
    }
    else {
        if ($script:Format -eq 'html') {
            $obj = ConvertTo-FirefoxJson -Root $script:Data
            $json = $obj | ConvertTo-Json -Depth 100
            Set-Content -LiteralPath $Path -Value $json -Encoding utf8
        } else {
            Strip-Ids -Node $script:Data
            $json = $script:Data | ConvertTo-Json -Depth 100
            Set-Content -LiteralPath $Path -Value $json -Encoding utf8
            Rebuild-Items   # interne __id wiederherstellen
        }
    }
}

# ---------------------------------------------------------------------------
# Prüf-Kern (wird als Text in die Runspaces übergeben)
# Liefert Hashtable: Id, Url, Code, Cat (ok|verdaechtig|bot|tot), Key, Title
# ---------------------------------------------------------------------------
$CheckCore = {
    param($Id, $Url, $Timeout, $IgnoreSsl, $Ua)
    $ProgressPreference = 'SilentlyContinue'
    $res = @{ Id = $Id; Url = $Url; Code = $null; Cat = 'tot'; Key = 'conn'; Title = $null; Retried = $false; Final = '' }
    # Eng gefasst (fuer 200er-Antworten): eindeutige Challenge-Seiten
    $botStrict = '(?is)<title[^>]*>\s*(just a moment|attention required|access denied|security check|bot verification)' +
                 '|cf-browser-verification|cf_chl_|challenge-platform|_incapsula_'
    # Breiter gefasst (fuer 403/429/503-Fehlerantworten)
    $botBroad  = '(?i)just a moment|attention required|checking your browser|cf-browser-verification|cf_chl_' +
                 '|challenge-platform|ddos protection|enable javascript and cookies|verify (that )?you are (a )?human' +
                 '|perimeterx|_incapsula_|incapsula|distil|cloudflare|akamai.*denied|request unsuccessful'
    try {
        $p = @{
            Uri                = $Url
            Method             = 'Get'
            TimeoutSec         = $Timeout
            MaximumRedirection = 5
            Headers            = @{ 'User-Agent' = $Ua; 'Accept-Language' = 'de,en;q=0.8' }
            ErrorAction        = 'Stop'
        }
        if ($IgnoreSsl) { $p['SkipCertificateCheck'] = $true }
        $resp = Invoke-WebRequest @p
        $code = [int]$resp.StatusCode
        $res.Code = $code
        try {
            $fin = [string]$resp.BaseResponse.RequestMessage.RequestUri
            if ($fin -and ($fin.TrimEnd('/') -ne $Url.TrimEnd('/'))) { $res.Final = $fin }
        } catch { }
        $body = [string]$resp.Content
        if ($body -match '(?is)<title[^>]*>(.*?)</title>') {
            $res.Title = ($matches[1] -replace '\s+', ' ').Trim()
        }
        if ($body -match $botStrict) { $res.Cat = 'bot'; $res.Key = 'bot' }
        elseif ($code -eq 401) { $res.Cat = 'verdaechtig'; $res.Key = 'auth' }
        elseif ($code -eq 403) { $res.Cat = 'verdaechtig'; $res.Key = 'forbidden' }
        elseif ($code -eq 429) { $res.Cat = 'verdaechtig'; $res.Key = 'ratelimit' }
        else { $res.Cat = 'ok'; $res.Key = 'ok' }
    }
    catch {
        $ex = $_.Exception
        $resp2 = $null
        try { $resp2 = $ex.Response } catch { }
        $errBody = ''
        try { if ($_.ErrorDetails) { $errBody = [string]$_.ErrorDetails.Message } } catch { }
        $server = ''
        try {
            if ($resp2 -and $resp2.Headers -and $resp2.Headers.Server) {
                $server = (@($resp2.Headers.Server) | ForEach-Object { $_.ToString() }) -join ' '
            }
        } catch { }
        if ($resp2 -and $resp2.StatusCode) {
            $code = [int]$resp2.StatusCode
            $res.Code = $code
            $isBot = ($errBody -match $botBroad) -or
                     ($server -match '(?i)cloudflare|incapsula|akamai|sucuri|ddos-guard|imperva')
            if (($code -in 403, 429, 503) -and $isBot) { $res.Cat = 'bot'; $res.Key = 'bot' }
            elseif ($code -eq 404) { $res.Cat = 'tot'; $res.Key = 'notfound' }
            elseif ($code -eq 410) { $res.Cat = 'tot'; $res.Key = 'gone' }
            elseif ($code -eq 401) { $res.Cat = 'verdaechtig'; $res.Key = 'auth' }
            elseif ($code -eq 403) { $res.Cat = 'verdaechtig'; $res.Key = 'forbidden' }
            elseif ($code -eq 429) { $res.Cat = 'verdaechtig'; $res.Key = 'ratelimit' }
            elseif ($code -ge 500) { $res.Cat = 'tot'; $res.Key = 'server' }
            else { $res.Cat = 'tot'; $res.Key = 'err' }
        }
        else {
            $msg = [string]$ex.Message
            if ($msg -match '(?i)timeout|timed out|cancell?ed|abgelaufen') {
                $res.Cat = 'tot'; $res.Key = 'timeout'
            }
            elseif ($msg -match '(?i)ssl|certificate|zertifikat|trust') {
                $res.Cat = 'verdaechtig'; $res.Key = 'ssl'
            }
            else { $res.Cat = 'tot'; $res.Key = 'conn' }
        }
    }
    return $res
}
$CheckCoreStr = $CheckCore.ToString()

# Durchlauf 1: eine URL pro Runspace, Ergebnis in die Queue
$WorkerScript = {
    param($Id, $Url, $Timeout, $IgnoreSsl, $Ua, $Queue, $CoreStr)
    $core = [scriptblock]::Create($CoreStr)
    $res = & $core $Id $Url $Timeout $IgnoreSsl $Ua
    $Queue.Enqueue($res)
}

# Durchlauf 2 (429-Retry): sequenziell, mit Wartezeit; zwischen Anfragen an
# DENSELBEN Host wird jeweils die volle Wartezeit eingehalten.
$RetryScript = {
    param($ItemList, $Timeout, $IgnoreSsl, $Ua, $Queue, $Wait, $CoreStr)
    $core = [scriptblock]::Create($CoreStr)
    Start-Sleep -Seconds $Wait
    $prevHost = ''
    foreach ($it in ($ItemList | Sort-Object Host)) {
        if ($prevHost) {
            if ($it.Host -eq $prevHost) { Start-Sleep -Seconds $Wait }
            else { Start-Sleep -Seconds 1 }
        }
        $prevHost = $it.Host
        $res = & $core $it.Id $it.Url $Timeout $IgnoreSsl $Ua
        $res.Retried = $true
        $Queue.Enqueue($res)
    }
}

# ---------------------------------------------------------------------------
# Farben
# ---------------------------------------------------------------------------
$ColTot  = [System.Drawing.Color]::FromArgb(192, 57, 43)    # rot
$ColSusp = [System.Drawing.Color]::FromArgb(154, 103, 0)    # gelbbraun
$ColOk   = [System.Drawing.Color]::FromArgb(26, 127, 55)    # gruen
$ColBot  = [System.Drawing.Color]::FromArgb(113, 54, 138)   # violett
$ColHl   = [System.Drawing.Color]::FromArgb(255, 246, 178)  # Hervorhebung (hellgelb)
$script:ColRowBack = [System.Drawing.Color]::White   # Zeilenhintergrund (Theme-abhaengig)
function Get-CatColor([string]$Cat) {
    switch ($Cat) {
        'tot' { $ColTot } 'verdaechtig' { $ColSusp } 'bot' { $ColBot } default { $ColOk }
    }
}

# ---------------------------------------------------------------------------
# GUI aufbauen
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size(1140, 780)
$form.MinimumSize = New-Object System.Drawing.Size(1050, 600)
$form.StartPosition = 'CenterScreen'

# ---- Kopfzeile ----
$panelTop = New-Object System.Windows.Forms.Panel
$panelTop.Dock = 'Top'; $panelTop.Height = 44
$btnOpen = New-Object System.Windows.Forms.Button
$btnOpen.Location = New-Object System.Drawing.Point(8, 8)
$btnOpen.Size = New-Object System.Drawing.Size(210, 28)
$lblFile = New-Object System.Windows.Forms.Label
$lblFile.AutoSize = $true
$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Location = New-Object System.Drawing.Point(226, 8)
$btnExport.Size = New-Object System.Drawing.Size(120, 28)
$btnExport.Enabled = $false
$lblFile.Location = New-Object System.Drawing.Point(356, 14)
$lblFile.ForeColor = [System.Drawing.Color]::DimGray
$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.DropDownStyle = 'DropDownList'; $cmbLang.Width = 110
$cmbLang.Anchor = 'Top,Right'
[void]$cmbLang.Items.AddRange(@('Deutsch', 'English'))
$cmbLang.SelectedIndex = 0
$chkDark = New-Object System.Windows.Forms.CheckBox
$chkDark.AutoSize = $true
$chkDark.Anchor = 'Top,Right'
$panelTop.Controls.AddRange(@($btnOpen, $btnExport, $lblFile, $chkDark, $cmbLang))

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$tabAv  = New-Object System.Windows.Forms.TabPage
$tabDup = New-Object System.Windows.Forms.TabPage
$tabs.TabPages.AddRange(@($tabAv, $tabDup))

# Tab-Kopfzeilen selbst zeichnen, damit sie im Dunkelmodus mitfaerben
$script:ThTabSel = [System.Drawing.SystemColors]::Window
$script:ThTabBar = [System.Drawing.SystemColors]::Control
$script:ThText   = [System.Drawing.SystemColors]::ControlText
$tabs.DrawMode = 'OwnerDrawFixed'
$tabs.Add_DrawItem({
    param($s, $e)
    $back = if ($e.Index -eq $s.SelectedIndex) { $script:ThTabSel } else { $script:ThTabBar }
    $br = New-Object System.Drawing.SolidBrush $back
    $e.Graphics.FillRectangle($br, $e.Bounds); $br.Dispose()
    $flags = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
             [System.Windows.Forms.TextFormatFlags]::VerticalCenter
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $s.TabPages[$e.Index].Text,
        $e.Font, $e.Bounds, $script:ThText, $flags)
})

$form.Controls.Add($tabs)
$form.Controls.Add($panelTop)

function New-TextCol {
    param([string]$Name, [int]$Fill = 0, [int]$Width = 0)
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $Name; $c.ReadOnly = $true
    if ($Fill -gt 0) { $c.AutoSizeMode = 'Fill'; $c.FillWeight = $Fill }
    elseif ($Width -gt 0) { $c.AutoSizeMode = 'None'; $c.Width = $Width }
    return $c
}
function New-CheckCol {
    $c = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $c.Name = 'sel'; $c.AutoSizeMode = 'None'; $c.Width = 65
    return $c
}
function New-Grid {
    $g = New-Object System.Windows.Forms.DataGridView
    $g.Dock = 'Fill'
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.RowHeadersVisible = $false
    $g.SelectionMode = 'FullRowSelect'
    $g.MultiSelect = $false
    $g.AutoSizeColumnsMode = 'Fill'
    $g.EditMode = 'EditOnKeystrokeOrF2'
    return $g
}

# =====================  Reiter 1: Erreichbarkeit  =====================
$avOpts = New-Object System.Windows.Forms.Panel; $avOpts.Dock = 'Top'; $avOpts.Height = 106
$lblTo = New-Object System.Windows.Forms.Label
$lblTo.Location = New-Object System.Drawing.Point(8, 12); $lblTo.AutoSize = $true
$numTimeout = New-Object System.Windows.Forms.NumericUpDown
$numTimeout.Location = New-Object System.Drawing.Point(90, 9); $numTimeout.Width = 50
$numTimeout.Minimum = 2; $numTimeout.Maximum = 60; $numTimeout.Value = 10
$lblPar = New-Object System.Windows.Forms.Label
$lblPar.Location = New-Object System.Drawing.Point(156, 12); $lblPar.AutoSize = $true
$numThreads = New-Object System.Windows.Forms.NumericUpDown
$numThreads.Location = New-Object System.Drawing.Point(216, 9); $numThreads.Width = 50
$numThreads.Minimum = 1; $numThreads.Maximum = 100; $numThreads.Value = 20
$chkSsl = New-Object System.Windows.Forms.CheckBox
$chkSsl.AutoSize = $true; $chkSsl.Location = New-Object System.Drawing.Point(286, 11)
$lblShow = New-Object System.Windows.Forms.Label
$lblShow.Location = New-Object System.Drawing.Point(496, 12); $lblShow.AutoSize = $true
$cmbFilter = New-Object System.Windows.Forms.ComboBox
$cmbFilter.DropDownStyle = 'DropDownList'; $cmbFilter.Width = 250
$cmbFilter.Location = New-Object System.Drawing.Point(566, 9)
# Zeile 2: Hervorheben + 429-Wartezeit
$lblHl = New-Object System.Windows.Forms.Label
$lblHl.Location = New-Object System.Drawing.Point(8, 46); $lblHl.AutoSize = $true
$chkH404 = New-Object System.Windows.Forms.CheckBox
$chkH404.AutoSize = $true; $chkH404.Location = New-Object System.Drawing.Point(110, 44)
$chkHTimeout = New-Object System.Windows.Forms.CheckBox
$chkHTimeout.AutoSize = $true; $chkHTimeout.Location = New-Object System.Drawing.Point(280, 44)
$chkHBot = New-Object System.Windows.Forms.CheckBox
$chkHBot.AutoSize = $true; $chkHBot.Location = New-Object System.Drawing.Point(440, 44)
$chkH5xx = New-Object System.Windows.Forms.CheckBox
$chkH5xx.AutoSize = $true; $chkH5xx.Location = New-Object System.Drawing.Point(565, 44)
$lblRetry = New-Object System.Windows.Forms.Label
$lblRetry.Location = New-Object System.Drawing.Point(730, 46); $lblRetry.AutoSize = $true
$numRetry = New-Object System.Windows.Forms.NumericUpDown
$numRetry.Location = New-Object System.Drawing.Point(905, 44); $numRetry.Width = 55
$numRetry.Minimum = 0; $numRetry.Maximum = 120; $numRetry.Value = 20
$lblUa = New-Object System.Windows.Forms.Label
$lblUa.Location = New-Object System.Drawing.Point(8, 78); $lblUa.AutoSize = $true
$txtUa = New-Object System.Windows.Forms.TextBox
$txtUa.Location = New-Object System.Drawing.Point(110, 75)
$txtUa.Width = 720; $txtUa.Anchor = 'Top,Left,Right'
$txtUa.Text = $UA
$avOpts.Controls.AddRange(@($lblTo, $numTimeout, $lblPar, $numThreads, $chkSsl,
    $lblShow, $cmbFilter, $lblHl, $chkH404, $chkHTimeout, $chkHBot, $chkH5xx,
    $lblRetry, $numRetry, $lblUa, $txtUa))

$avAct = New-Object System.Windows.Forms.Panel; $avAct.Dock = 'Top'; $avAct.Height = 40
$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Location = New-Object System.Drawing.Point(8, 6)
$btnCheck.Size = New-Object System.Drawing.Size(130, 28); $btnCheck.Enabled = $false
$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Location = New-Object System.Drawing.Point(146, 6)
$btnStop.Size = New-Object System.Drawing.Size(100, 28); $btnStop.Enabled = $false
$btnAvAll = New-Object System.Windows.Forms.Button
$btnAvAll.Location = New-Object System.Drawing.Point(252, 6)
$btnAvAll.Size = New-Object System.Drawing.Size(110, 28)
$btnAvNone = New-Object System.Windows.Forms.Button
$btnAvNone.Location = New-Object System.Drawing.Point(368, 6)
$btnAvNone.Size = New-Object System.Drawing.Size(110, 28)
$btnCsv = New-Object System.Windows.Forms.Button
$btnCsv.Location = New-Object System.Drawing.Point(484, 6)
$btnCsv.Size = New-Object System.Drawing.Size(105, 28)
$btnDelAv = New-Object System.Windows.Forms.Button
$btnDelAv.Size = New-Object System.Drawing.Size(160, 28); $btnDelAv.Enabled = $false
$btnDelAv.Anchor = 'Top,Right'
$btnSaveAv = New-Object System.Windows.Forms.Button
$btnSaveAv.Size = New-Object System.Drawing.Size(110, 28); $btnSaveAv.Enabled = $false
$btnSaveAv.Anchor = 'Top,Right'
$avAct.Controls.AddRange(@($btnCheck, $btnStop, $btnAvAll, $btnAvNone, $btnCsv, $btnDelAv, $btnSaveAv))

$avProg = New-Object System.Windows.Forms.Panel; $avProg.Dock = 'Top'; $avProg.Height = 26
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(8, 4)
$progress.Size = New-Object System.Drawing.Size(700, 16)
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(720, 6)
$avProg.Controls.AddRange(@($progress, $lblStatus))

# ---- Farb-Legende ----
$avLegend = New-Object System.Windows.Forms.FlowLayoutPanel
$avLegend.Dock = 'Top'; $avLegend.Height = 28
$avLegend.WrapContents = $false
$avLegend.Padding = New-Object System.Windows.Forms.Padding(6, 5, 6, 0)
function New-LegendLabel {
    param($Fore, $Back)
    $l = New-Object System.Windows.Forms.Label
    $l.AutoSize = $true
    $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 16, 0)
    if ($Fore) { $l.ForeColor = $Fore }
    if ($Back) { $l.BackColor = $Back }
    return $l
}
$lblLegT   = New-LegendLabel -Fore ([System.Drawing.Color]::Black)  -Back $null
$lblLegOk  = New-LegendLabel -Fore $ColOk   -Back $null
$lblLegSusp= New-LegendLabel -Fore $ColSusp -Back $null
$lblLegBot = New-LegendLabel -Fore $ColBot  -Back $null
$lblLegTot = New-LegendLabel -Fore $ColTot  -Back $null
$lblLegHl  = New-LegendLabel -Fore ([System.Drawing.Color]::Black)  -Back $ColHl
$lblLegDbl = New-LegendLabel -Fore ([System.Drawing.Color]::DimGray) -Back $null
$avLegend.Controls.AddRange(@($lblLegT, $lblLegOk, $lblLegSusp, $lblLegBot,
    $lblLegTot, $lblLegHl, $lblLegDbl))

$gridAv = New-Grid
[void]$gridAv.Columns.Add((New-CheckCol))
[void]$gridAv.Columns.Add((New-TextCol -Name 'status' -Width 195))
[void]$gridAv.Columns.Add((New-TextCol -Name 'code'   -Width 55))
[void]$gridAv.Columns.Add((New-TextCol -Name 'title'  -Fill 26))
[void]$gridAv.Columns.Add((New-TextCol -Name 'url'    -Fill 28))
[void]$gridAv.Columns.Add((New-TextCol -Name 'redirect' -Fill 20))
[void]$gridAv.Columns.Add((New-TextCol -Name 'folder' -Fill 14))

# Reihenfolge: zuletzt hinzugefuegte Dock-Top-Panels liegen oben
$tabAv.Controls.Add($gridAv)
$tabAv.Controls.Add($avLegend)
$tabAv.Controls.Add($avProg)
$tabAv.Controls.Add($avAct)
$tabAv.Controls.Add($avOpts)

# =====================  Reiter 2: Dubletten  =====================
$dupOpts = New-Object System.Windows.Forms.Panel; $dupOpts.Dock = 'Top'; $dupOpts.Height = 74
$lblDupMode = New-Object System.Windows.Forms.Label
$lblDupMode.Location = New-Object System.Drawing.Point(8, 12); $lblDupMode.AutoSize = $true
$cmbDupMode = New-Object System.Windows.Forms.ComboBox
$cmbDupMode.DropDownStyle = 'DropDownList'; $cmbDupMode.Width = 120
$cmbDupMode.Location = New-Object System.Drawing.Point(140, 9)
$lblCmp = New-Object System.Windows.Forms.Label
$lblCmp.Location = New-Object System.Drawing.Point(8, 46); $lblCmp.AutoSize = $true
$chkCase = New-Object System.Windows.Forms.CheckBox
$chkCase.AutoSize = $true; $chkCase.Checked = $true
$chkCase.Location = New-Object System.Drawing.Point(190, 45)
$chkFrag = New-Object System.Windows.Forms.CheckBox
$chkFrag.AutoSize = $true; $chkFrag.Checked = $true
$chkFrag.Location = New-Object System.Drawing.Point(340, 45)
$chkSlash = New-Object System.Windows.Forms.CheckBox
$chkSlash.AutoSize = $true; $chkSlash.Checked = $true
$chkSlash.Location = New-Object System.Drawing.Point(455, 45)
$chkQuery = New-Object System.Windows.Forms.CheckBox
$chkQuery.AutoSize = $true; $chkQuery.Checked = $false
$chkQuery.Location = New-Object System.Drawing.Point(605, 45)
$chkSub = New-Object System.Windows.Forms.CheckBox
$chkSub.AutoSize = $true; $chkSub.Checked = $false
$chkSub.Location = New-Object System.Drawing.Point(755, 45)
$dupOpts.Controls.AddRange(@($lblDupMode, $cmbDupMode, $lblCmp, $chkCase, $chkFrag,
    $chkSlash, $chkQuery, $chkSub))

$dupAct = New-Object System.Windows.Forms.Panel; $dupAct.Dock = 'Top'; $dupAct.Height = 40
$btnDup = New-Object System.Windows.Forms.Button
$btnDup.Location = New-Object System.Drawing.Point(8, 6)
$btnDup.Size = New-Object System.Drawing.Size(150, 28); $btnDup.Enabled = $false
$btnDupAuto = New-Object System.Windows.Forms.Button
$btnDupAuto.Location = New-Object System.Drawing.Point(166, 6)
$btnDupAuto.Size = New-Object System.Drawing.Size(210, 28)
$btnDupAll = New-Object System.Windows.Forms.Button
$btnDupAll.Location = New-Object System.Drawing.Point(384, 6)
$btnDupAll.Size = New-Object System.Drawing.Size(105, 28)
$btnDupNone = New-Object System.Windows.Forms.Button
$btnDupNone.Location = New-Object System.Drawing.Point(495, 6)
$btnDupNone.Size = New-Object System.Drawing.Size(105, 28)
$btnDelDup = New-Object System.Windows.Forms.Button
$btnDelDup.Size = New-Object System.Drawing.Size(160, 28); $btnDelDup.Enabled = $false
$btnDelDup.Anchor = 'Top,Right'
$btnSaveDup = New-Object System.Windows.Forms.Button
$btnSaveDup.Size = New-Object System.Drawing.Size(110, 28); $btnSaveDup.Enabled = $false
$btnSaveDup.Anchor = 'Top,Right'
$dupAct.Controls.AddRange(@($btnDup, $btnDupAuto, $btnDupAll, $btnDupNone, $btnDelDup, $btnSaveDup))

$dupInfoPanel = New-Object System.Windows.Forms.Panel; $dupInfoPanel.Dock = 'Top'; $dupInfoPanel.Height = 24
$lblDup = New-Object System.Windows.Forms.Label; $lblDup.AutoSize = $true
$lblDup.Location = New-Object System.Drawing.Point(8, 4)
$lblDup.ForeColor = [System.Drawing.Color]::DimGray
$dupInfoPanel.Controls.Add($lblDup)

$gridDup = New-Grid
[void]$gridDup.Columns.Add((New-CheckCol))
[void]$gridDup.Columns.Add((New-TextCol -Name 'group'  -Width 110))
[void]$gridDup.Columns.Add((New-TextCol -Name 'title'  -Fill 30))
[void]$gridDup.Columns.Add((New-TextCol -Name 'url'    -Fill 40))
[void]$gridDup.Columns.Add((New-TextCol -Name 'folder' -Fill 18))

$tabDup.Controls.Add($gridDup)
$tabDup.Controls.Add($dupInfoPanel)
$tabDup.Controls.Add($dupAct)
$tabDup.Controls.Add($dupOpts)

# ---------------------------------------------------------------------------
# Sprache anwenden
# ---------------------------------------------------------------------------
function Apply-Language {
    $script:UpdatingUi = $true
    $script:L = $Loc[$script:Lang]
    $form.Text = (T 'app_title') + '  -  ' + $script:Copyright
    $btnOpen.Text = T 'btn_open'
    $lblUa.Text = T 'lbl_ua'
    $miOpen.Text = T 'ctx_open'; $miCopy.Text = T 'ctx_copy'
    $miEdit.Text = T 'ctx_edit'; $miRedir.Text = T 'ctx_redir'
    $chkDark.Text = T 'chk_dark'
    $btnExport.Text = T 'btn_export'
    if (-not $lblFile.Tag) { Set-LocText $lblFile 'no_file' }
    foreach ($dynLbl in @($lblFile, $lblStatus, $lblDup)) {
        if ($dynLbl.Tag -and $dynLbl.Tag.Key) {
            Set-LocText $dynLbl $dynLbl.Tag.Key $dynLbl.Tag.Fmt
        }
    }
    $tabAv.Text = '  ' + (T 'tab_av') + '  '
    $tabDup.Text = '  ' + (T 'tab_dup') + '  '
    $lblTo.Text = T 'lbl_timeout'; $lblPar.Text = T 'lbl_parallel'
    $chkSsl.Text = T 'chk_ssl'; $lblShow.Text = T 'lbl_show'
    $lblHl.Text = T 'lbl_hl'
    $chkH404.Text = T 'h_404'; $chkHTimeout.Text = T 'h_timeout'
    $chkHBot.Text = T 'h_bot'; $chkH5xx.Text = T 'h_5xx'
    $lblRetry.Text = T 'lbl_retry'
    $btnCheck.Text = T 'btn_check'
    $btnAvAll.Text = T 'btn_all'; $btnAvNone.Text = T 'btn_none'
    $btnCsv.Text = T 'btn_csv'; $btnSaveAv.Text = T 'btn_save'
    $btnStop.Text = T 'btn_stop'; $btnDelAv.Text = T 'btn_del'
    $btnDup.Text = T 'btn_finddup'; $btnDupAuto.Text = T 'btn_keep1'
    $btnDupAll.Text = T 'btn_all'; $btnDupNone.Text = T 'btn_none'
    $btnSaveDup.Text = T 'btn_save'
    $btnDelDup.Text = T 'btn_del'
    $lblDupMode.Text = T 'lbl_dupmode'
    $lblCmp.Text = T 'cmp_ignore'
    $chkCase.Text = T 'cmp_case'; $chkFrag.Text = T 'cmp_frag'
    $chkSlash.Text = T 'cmp_slash'; $chkQuery.Text = T 'cmp_query'
    $chkSub.Text = T 'cmp_sub'
    # Legende
    $lblLegT.Text   = T 'lbl_legend'
    $lblLegOk.Text  = T 'cat_ok'
    $lblLegSusp.Text= T 'cat_susp'
    $lblLegBot.Text = T 'cat_bot'
    $lblLegTot.Text = T 'cat_tot'
    $lblLegHl.Text  = T 'leg_hl'
    $lblLegDbl.Text = T 'hint_dbl'
    # Spalten
    $gridAv.Columns['sel'].HeaderText    = T 'col_del'
    $gridAv.Columns['status'].HeaderText = T 'col_status'
    $gridAv.Columns['code'].HeaderText   = T 'col_code'
    $gridAv.Columns['title'].HeaderText  = T 'col_title'
    $gridAv.Columns['url'].HeaderText    = T 'col_url'
    $gridAv.Columns['redirect'].HeaderText = T 'col_redirect'
    $gridAv.Columns['folder'].HeaderText = T 'col_folder'
    $gridDup.Columns['sel'].HeaderText    = T 'col_del'
    $gridDup.Columns['group'].HeaderText  = T 'col_group'
    $gridDup.Columns['title'].HeaderText  = T 'col_title'
    $gridDup.Columns['url'].HeaderText    = T 'col_url'
    $gridDup.Columns['folder'].HeaderText = T 'col_folder'
    $sel = $cmbFilter.SelectedIndex; if ($sel -lt 0) { $sel = 0 }
    $cmbFilter.Items.Clear()
    [void]$cmbFilter.Items.AddRange(@((T 'f_dead'), (T 'f_deadsusp'), (T 'f_all')))
    $cmbFilter.SelectedIndex = $sel
    $sel2 = $cmbDupMode.SelectedIndex; if ($sel2 -lt 0) { $sel2 = 0 }
    $cmbDupMode.Items.Clear()
    [void]$cmbDupMode.Items.AddRange(@((T 'dm_url'), (T 'dm_title')))
    $cmbDupMode.SelectedIndex = $sel2
    Update-DupModeUi
    $script:UpdatingUi = $false
    if ($script:AvResults.Count -gt 0) { Refresh-AvTable }
}

# ---------------------------------------------------------------------------
# Grid-Helfer
# ---------------------------------------------------------------------------
function Set-AllChecks {
    param($Grid, [bool]$Value)
    foreach ($row in $Grid.Rows) { $row.Cells['sel'].Value = $Value }
    $Grid.RefreshEdit()
}
function Get-CheckedIds {
    param($Grid)
    $ids = New-Object System.Collections.Generic.HashSet[string]
    foreach ($row in $Grid.Rows) {
        if ($row.Cells['sel'].Value -eq $true -and $row.Tag) {
            [void]$ids.Add([string]$row.Tag.Id)
        }
    }
    return $ids
}
$commitHandler = {
    param($s, $e)
    if ($s.IsCurrentCellDirty) {
        $s.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
}
$gridAv.Add_CurrentCellDirtyStateChanged($commitHandler)
$gridDup.Add_CurrentCellDirtyStateChanged($commitHandler)

# Code-Spalte numerisch sortieren (Zeilen ohne Code ans Ende)
$gridAv.Add_SortCompare({
    param($s, $e)
    if ($e.Column.Name -ne 'code') { return }
    $a = 0; $b = 0
    $pa = [int]::TryParse([string]$e.CellValue1, [ref]$a)
    $pb = [int]::TryParse([string]$e.CellValue2, [ref]$b)
    if ($pa -and $pb)  { $e.SortResult = $a.CompareTo($b) }
    elseif ($pa)       { $e.SortResult = -1 }
    elseif ($pb)       { $e.SortResult = 1 }
    else               { $e.SortResult = [string]::Compare([string]$e.CellValue1,
                                                           [string]$e.CellValue2) }
    $e.Handled = $true
})

# Im Dubletten-Reiter nicht sortieren - das wuerde die Gruppen auseinanderreissen
foreach ($col in $gridDup.Columns) { $col.SortMode = 'NotSortable' }

# Doppelklick oeffnet die Seite im Standardbrowser (nicht auf der Checkbox-Spalte)
$openHandler = {
    param($s, $e)
    if ($e.RowIndex -lt 0) { return }
    $colName = if ($e.ColumnIndex -ge 0) { $s.Columns[$e.ColumnIndex].Name } else { '' }
    if ($colName -eq 'sel') { return }   # Haken-Spalte nicht oeffnen
    $u = ''
    if ($colName -eq 'redirect') { $u = [string]$s.Rows[$e.RowIndex].Cells['redirect'].Value }
    if (-not $u) { $u = [string]$s.Rows[$e.RowIndex].Cells['url'].Value }
    if ($u -and ($u.StartsWith('http://') -or $u.StartsWith('https://'))) {
        try { Start-Process $u } catch { }
    }
}
$gridAv.Add_CellDoubleClick($openHandler)
$gridDup.Add_CellDoubleClick($openHandler)

# ---------------------------------------------------------------------------
# URL-Aktionen per Rechtsklick-Menue (Bearbeiten, Kopieren, Oeffnen,
# Umleitungsziel uebernehmen). Aenderungen werden in den Baum zurueckgeschrieben.
# ---------------------------------------------------------------------------
function Set-BookmarkUrl {
    param($Row, [string]$New)
    if (-not $Row -or -not $Row.Tag) { return $false }
    $id = [string]$Row.Tag.Id
    $item = $script:ItemById[$id]
    if (-not $item) { return $false }
    $New = ([string]$New).Trim()
    if (-not $New -or $New -eq $item.Url) { return $false }
    if (-not ($New -match '^(?i)https?://\S+$')) {
        [System.Windows.Forms.MessageBox]::Show((T 'bad_url'), (T 't_hint'),
            'OK', 'Information') | Out-Null
        return $false
    }
    $item.Node.uri = $New
    $item.Url = $New
    # HTML-Quelle: gespeicherten HREF-Attributwert mitziehen
    $np = $item.Node.PSObject.Properties.Name
    if ($np -contains '__attrs') {
        $enc = [System.Net.WebUtility]::HtmlEncode($New)
        $repl = ('HREF="' + $enc + '"').Replace('$', '$$')
        $a = [string]$item.Node.__attrs
        if ($a -match '(?i)HREF\s*=\s*"[^"]*"') {
            $item.Node.__attrs = [regex]::Replace($a, '(?i)HREF\s*=\s*"[^"]*"', $repl)
        } else {
            $item.Node.__attrs = ' HREF="' + $enc + '"' + $a
        }
    }
    if ($script:AvResults.ContainsKey($id)) { $script:AvResults[$id]['Url'] = $New }
    $Row.Cells['url'].Value = $New
    $script:Dirty = $true
    Set-LocText $lblStatus 'url_saved'
    return $true
}

function Show-UrlDialog {
    param([string]$Current)
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = T 'ctx_edit'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $dlg.StartPosition = 'CenterParent'
    $dlg.ClientSize = New-Object System.Drawing.Size(620, 86)
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(12, 14)
    $tb.Width = 596; $tb.Text = $Current
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = T 't_ok'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(444, 48)
    $ok.Size = New-Object System.Drawing.Size(78, 28)
    $ca = New-Object System.Windows.Forms.Button
    $ca.Text = T 't_cancel'
    $ca.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $ca.Location = New-Object System.Drawing.Point(530, 48)
    $ca.Size = New-Object System.Drawing.Size(78, 28)
    $dlg.Controls.AddRange(@($tb, $ok, $ca))
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $ca
    if ($script:ThemeP) {
        $dlg.BackColor = $script:ThemeP.Back
        Set-ThemeRecursive $dlg $script:ThemeP
    }
    $tb.SelectAll()
    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        return [string]$tb.Text
    }
    return $null
}

$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$miOpen  = New-Object System.Windows.Forms.ToolStripMenuItem
$miCopy  = New-Object System.Windows.Forms.ToolStripMenuItem
$miEdit  = New-Object System.Windows.Forms.ToolStripMenuItem
$miRedir = New-Object System.Windows.Forms.ToolStripMenuItem
[void]$ctxMenu.Items.AddRange(@($miOpen, $miCopy, $miEdit, $miRedir))
$script:CtxGrid = $null

$ctxMenu.Add_Opening({
    param($s, $e)
    $g = $s.SourceControl
    $script:CtxGrid = $g
    if (-not $g -or -not $g.CurrentRow) { $e.Cancel = $true; return }
    $hasRedir = $false
    if ($g -eq $gridAv) {
        $hasRedir = [bool]([string]$g.CurrentRow.Cells['redirect'].Value)
    }
    $miRedir.Visible = $hasRedir
})

# Rechtsklick waehlt die Zeile unter dem Cursor aus
$ctxMouseHandler = {
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Right) { return }
    if ($e.RowIndex -lt 0) { return }
    $s.ClearSelection()
    $s.Rows[$e.RowIndex].Selected = $true
    $col = if ($e.ColumnIndex -ge 0) { $e.ColumnIndex } else { 1 }
    $s.CurrentCell = $s.Rows[$e.RowIndex].Cells[$col]
}
$gridAv.Add_CellMouseDown($ctxMouseHandler)
$gridDup.Add_CellMouseDown($ctxMouseHandler)
$gridAv.ContextMenuStrip = $ctxMenu
$gridDup.ContextMenuStrip = $ctxMenu

$miOpen.Add_Click({
    $g = $script:CtxGrid
    if (-not $g -or -not $g.CurrentRow) { return }
    $u = [string]$g.CurrentRow.Cells['url'].Value
    if ($u -match '^(?i)https?://') { try { Start-Process $u } catch { } }
})
$miCopy.Add_Click({
    $g = $script:CtxGrid
    if (-not $g -or -not $g.CurrentRow) { return }
    $u = [string]$g.CurrentRow.Cells['url'].Value
    if ($u) { try { [System.Windows.Forms.Clipboard]::SetText($u) } catch { } }
})
$miEdit.Add_Click({
    $g = $script:CtxGrid
    if (-not $g -or -not $g.CurrentRow) { return }
    $cur = [string]$g.CurrentRow.Cells['url'].Value
    $new = Show-UrlDialog -Current $cur
    if ($null -ne $new) { [void](Set-BookmarkUrl -Row $g.CurrentRow -New $new) }
})
$miRedir.Add_Click({
    $g = $script:CtxGrid
    if ($g -ne $gridAv -or -not $g.CurrentRow) { return }
    $red = [string]$g.CurrentRow.Cells['redirect'].Value
    if ($red) { [void](Set-BookmarkUrl -Row $g.CurrentRow -New $red) }
})

# ---------------------------------------------------------------------------
# Hervorhebung
# ---------------------------------------------------------------------------
function Get-HighlightKeys {
    $ks = @()
    if ($chkH404.Checked)     { $ks += 'notfound' }
    if ($chkHTimeout.Checked) { $ks += 'timeout' }
    if ($chkHBot.Checked)     { $ks += 'bot' }
    if ($chkH5xx.Checked)     { $ks += 'server' }
    return $ks
}
function Apply-Highlight {
    $ks = Get-HighlightKeys
    foreach ($row in $gridAv.Rows) {
        $k = if ($row.Tag) { [string]$row.Tag.Key } else { '' }
        $row.DefaultCellStyle.BackColor = if ($ks -contains $k) { $ColHl } else { $script:ColRowBack }
    }
}
$hlHandler = { Apply-Highlight }
$chkH404.Add_CheckedChanged($hlHandler)
$chkHTimeout.Add_CheckedChanged($hlHandler)
$chkHBot.Add_CheckedChanged($hlHandler)
$chkH5xx.Add_CheckedChanged($hlHandler)

# ---------------------------------------------------------------------------
# Zeilen aufbauen / live aktualisieren
# ---------------------------------------------------------------------------
function Get-ShowCats {
    switch ($cmbFilter.SelectedIndex) {
        0 { @('tot') }
        1 { @('tot', 'verdaechtig', 'bot') }
        default { @('tot', 'verdaechtig', 'bot', 'ok') }
    }
}

function Get-StatusText($r) {
    $s = T ('st_' + $r.Key)
    if ($r.Retried) { $s += ' ' + (T 'suf_retry') }
    return $s
}

function Style-Row($Row, $r, $HlKeys) {
    $Row.Tag = [pscustomobject]@{ Id = $r.Id; Key = $r.Key }
    $Row.DefaultCellStyle.ForeColor = Get-CatColor $r.Cat
    $Row.DefaultCellStyle.BackColor = if ($HlKeys -contains $r.Key) { $ColHl } else { $script:ColRowBack }
}

# Fuegt eine Zeile fuer ein Ergebnis hinzu oder aktualisiert die bestehende.
# Wird waehrend der Pruefung live aufgerufen.
function Add-OrUpdateRow($r) {
    $show = Get-ShowCats
    $hl = Get-HighlightKeys
    $item = $script:ItemById[$r.Id]
    $existing = $script:RowById[$r.Id]

    if ($existing) {
        if ($show -notcontains $r.Cat) {
            $gridAv.Rows.Remove($existing)
            $script:RowById.Remove($r.Id)
            return
        }
        $existing.Cells['status'].Value = Get-StatusText $r
        $existing.Cells['code'].Value = if ($null -ne $r.Code) { [string]$r.Code } else { [string][char]0x2013 }
        $existing.Cells['redirect'].Value = if ($r.ContainsKey('Final')) { [string]$r.Final } else { '' }
        if ($r.Title) { $existing.Cells['title'].Value = $r.Title }
        Style-Row $existing $r $hl
        return
    }
    if ($show -notcontains $r.Cat) { return }
    $folder = if ($item) { $item.Folder } else { '' }
    $title = if ($r.Title) { $r.Title }
             elseif ($item -and $item.Title) { $item.Title }
             else { [string][char]0x2014 }
    $codeTxt = if ($null -ne $r.Code) { [string]$r.Code } else { [string][char]0x2013 }
    $red = if ($r.ContainsKey('Final')) { [string]$r.Final } else { '' }
    $idx = $gridAv.Rows.Add(@($false, (Get-StatusText $r), $codeTxt, $title, $r.Url, $red, $folder))
    $rw = $gridAv.Rows[$idx]
    Style-Row $rw $r $hl
    $script:RowById[$r.Id] = $rw
}

# Kompletter Neuaufbau (nach Filterwechsel / Sprachwechsel / Abschluss) - sortiert.
function Refresh-AvTable {
    $gridAv.Rows.Clear()
    $script:RowById = @{}
    $show = Get-ShowCats
    $hl = Get-HighlightKeys
    $order = @{ tot = 0; bot = 1; verdaechtig = 2; ok = 3 }
    $sorted = $script:AvResults.Values | Sort-Object { $order[$_.Cat] }
    foreach ($r in $sorted) {
        if ($show -notcontains $r.Cat) { continue }
        $item = $script:ItemById[$r.Id]
        $folder = if ($item) { $item.Folder } else { '' }
        $title = if ($r.Title) { $r.Title }
                 elseif ($item -and $item.Title) { $item.Title }
                 else { [string][char]0x2014 }
        $codeTxt = if ($null -ne $r.Code) { [string]$r.Code } else { [string][char]0x2013 }
        $red = if ($r.ContainsKey('Final')) { [string]$r.Final } else { '' }
        $idx = $gridAv.Rows.Add(@($false, (Get-StatusText $r), $codeTxt, $title, $r.Url, $red, $folder))
        $rw = $gridAv.Rows[$idx]
        Style-Row $rw $r $hl
        $script:RowById[$r.Id] = $rw
    }
}

# ---------------------------------------------------------------------------
# Abschluss / Aufraeumen der Hintergrund-Jobs
# ---------------------------------------------------------------------------
function Dispose-Jobs {
    foreach ($h in $script:Handles) {
        try { $h.PS.EndInvoke($h.Handle) } catch { }
        try { $h.PS.Dispose() } catch { }
    }
    $script:Handles = @()
    if ($script:Pool) {
        try { $script:Pool.Close(); $script:Pool.Dispose() } catch { }
        $script:Pool = $null
    }
}

function Finish-Check {
    $script:Running = $false
    $btnCheck.Enabled = $true
    $btnStop.Enabled = $false
    $btnDelAv.Enabled = $true
    $btnOpen.Enabled = $true
    $nTot = @($script:AvResults.Values | Where-Object { $_.Cat -eq 'tot' }).Count
    $nBot = @($script:AvResults.Values | Where-Object { $_.Cat -eq 'bot' }).Count
    Set-LocText $lblStatus 'done' @($nTot, $nBot)
    Refresh-AvTable
}

# Laufende Pruefung abbrechen: Jobs stoppen, bereits vorliegende Ergebnisse behalten
function Stop-Check {
    if (-not $script:Running) { return }
    $timer.Stop()
    $script:Running = $false
    foreach ($h in $script:Handles) {
        try { $h.PS.Stop() } catch { }
        try { $h.PS.Dispose() } catch { }
    }
    $script:Handles = @()
    if ($script:Pool) {
        try { $script:Pool.Close(); $script:Pool.Dispose() } catch { }
        $script:Pool = $null
    }
    if ($script:Queue) {
        while ($script:Queue.Count -gt 0) {
            $r = $script:Queue.Dequeue()
            $script:AvResults[$r.Id] = $r
        }
    }
    $btnCheck.Enabled = $true
    $btnStop.Enabled = $false
    $btnOpen.Enabled = $true
    $btnDelAv.Enabled = ($script:AvResults.Count -gt 0)
    Set-LocText $lblStatus 'aborted' @($script:AvResults.Count)
    Refresh-AvTable
}
$btnStop.Add_Click({ Stop-Check })

# ---------------------------------------------------------------------------
# Timer: Ergebnisse einsammeln, Tabelle live fuellen, Phasen steuern
# ---------------------------------------------------------------------------
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
    if ($null -eq $script:Queue) { return }
    while ($script:Queue.Count -gt 0) {
        $r = $script:Queue.Dequeue()
        $script:AvResults[$r.Id] = $r
        $script:Processed++
        Add-OrUpdateRow $r           # <- live waehrend der Pruefung
    }
    if ($script:Total -gt 0) {
        $progress.Value = [Math]::Min($script:Processed, $script:Total)
        if ($script:Phase -eq 1) {
            Set-LocText $lblStatus 'checking' @($script:Processed, $script:Total)
        } else {
            Set-LocText $lblStatus 'retrying' @($script:RetryWait, $script:Processed, $script:Total)
        }
    }
    if ($script:Processed -ge $script:Total -and $script:Running) {
        if ($script:Phase -eq 1) {
            Dispose-Jobs
            # 429-Kandidaten fuer den zweiten Durchlauf einsammeln
            $script:RetryWait = [int]$numRetry.Value
            $retry = @($script:AvResults.Values | Where-Object { $_.Code -eq 429 })
            if ($script:RetryWait -gt 0 -and $retry.Count -gt 0) {
                $script:Phase = 2
                $script:Processed = 0
                $script:Total = $retry.Count
                $progress.Maximum = $script:Total; $progress.Value = 0
                Set-LocText $lblStatus 'retrying' @($script:RetryWait, 0, $script:Total)
                $itemList = @(foreach ($r2 in $retry) {
                    $h = ''
                    try { $h = ([uri]$r2.Url).Host } catch { }
                    [pscustomobject]@{ Id = $r2.Id; Url = $r2.Url; Host = $h }
                })
                $ps = [powershell]::Create()
                [void]$ps.AddScript($RetryScript.ToString()).
                    AddArgument($itemList).AddArgument([int]$numTimeout.Value).
                    AddArgument($chkSsl.Checked).AddArgument($script:UaCur).
                    AddArgument($script:Queue).AddArgument($script:RetryWait).
                    AddArgument($CheckCoreStr)
                $h2 = $ps.BeginInvoke()
                $script:Handles = @(@{ PS = $ps; Handle = $h2 })
                return
            }
            $timer.Stop()
            Finish-Check
        }
        else {
            $timer.Stop()
            Dispose-Jobs
            Finish-Check
        }
    }
})

# ---------------------------------------------------------------------------
# Aktionen
# ---------------------------------------------------------------------------
$btnOpen.Add_Click({
    if ($script:Running) { return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = T 'btn_open'
    $dlg.Filter = 'JSON / HTML|*.json;*.html;*.htm|JSON (*.json)|*.json|HTML (*.html;*.htm)|*.html;*.htm|*.*|*.*'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $raw = Get-Content -LiteralPath $dlg.FileName -Raw -Encoding utf8
        $ext = [System.IO.Path]::GetExtension($dlg.FileName)
        if ($raw -match '(?is)^\s*<!DOCTYPE\s+NETSCAPE-Bookmark' -or $ext -match '^(?i)\.html?$') {
            $script:Data = ConvertFrom-BookmarkHtml -Html $raw
            $script:Format = 'html'
        } else {
            $script:Data = $raw | ConvertFrom-Json -Depth 100
            $script:Format = 'json'
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(((T 'load_err') -f $_.Exception.Message),
            (T 't_error'), 'OK', 'Error') | Out-Null
        return
    }
    $script:FilePath = $dlg.FileName
    Rebuild-Items
    Set-LocText $lblFile 'loaded' @([System.IO.Path]::GetFileName($dlg.FileName), $script:Items.Count)
    $script:AvResults = @{}
    $script:RowById = @{}
    $gridAv.Rows.Clear(); $gridDup.Rows.Clear()
    Set-LocText $lblStatus ''; Set-LocText $lblDup ''; $progress.Value = 0
    $has = $script:Items.Count -gt 0
    $btnCheck.Enabled = $has; $btnDup.Enabled = $has
    $btnExport.Enabled = $true
    $btnSaveAv.Enabled = $true; $btnSaveDup.Enabled = $true
    $btnDelAv.Enabled = $false; $btnDelDup.Enabled = $false
    $btnStop.Enabled = $false
    $script:Dirty = $false
    if (-not $has) {
        [System.Windows.Forms.MessageBox]::Show((T 'no_http'), (T 't_hint'),
            'OK', 'Information') | Out-Null
    }
})

$btnCheck.Add_Click({
    if ($script:Running -or $script:Items.Count -eq 0) { return }
    $timeout = [int]$numTimeout.Value
    $threads = [int]$numThreads.Value
    $ignoreSsl = $chkSsl.Checked
    $script:UaCur = $txtUa.Text.Trim()
    if (-not $script:UaCur) { $script:UaCur = $UA; $txtUa.Text = $UA }

    $script:AvResults = @{}
    $script:RowById = @{}
    $gridAv.Rows.Clear()
    $script:Queue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
    $script:Processed = 0
    $script:Total = $script:Items.Count
    $script:Phase = 1
    $progress.Maximum = $script:Total; $progress.Value = 0
    $btnCheck.Enabled = $false; $btnDelAv.Enabled = $false; $btnOpen.Enabled = $false
    $btnStop.Enabled = $true
    $script:Running = $true
    Set-LocText $lblStatus 'checking' @(0, $script:Total)

    $script:Pool = [runspacefactory]::CreateRunspacePool(1, $threads)
    $script:Pool.Open()
    $script:Handles = @()
    foreach ($it in $script:Items) {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $script:Pool
        [void]$ps.AddScript($WorkerScript.ToString()).
            AddArgument($it.Id).AddArgument($it.Url).AddArgument($timeout).
            AddArgument($ignoreSsl).AddArgument($script:UaCur).AddArgument($script:Queue).
            AddArgument($CheckCoreStr)
        $h = $ps.BeginInvoke()
        $script:Handles += @{ PS = $ps; Handle = $h }
    }
    $timer.Start()
})

$cmbFilter.Add_SelectedIndexChanged({
    if ($script:UpdatingUi) { return }
    if ($script:AvResults.Count -gt 0) { Refresh-AvTable }
})
$btnAvAll.Add_Click({ Set-AllChecks -Grid $gridAv -Value $true })
$btnAvNone.Add_Click({ Set-AllChecks -Grid $gridAv -Value $false })

$cmbLang.Add_SelectedIndexChanged({
    $script:Lang = if ($cmbLang.SelectedIndex -eq 1) { 'en' } else { 'de' }
    Apply-Language
})

# ---- Export / Formatkonvertierung (ohne Loeschen) ----
$btnExport.Add_Click({
    if ($script:Running -or $null -eq $script:Data) { return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = T 'btn_export'
    $base = [System.IO.Path]::GetFileNameWithoutExtension($script:FilePath)
    if ($script:Format -eq 'html') {
        # Konvertierung ins jeweils andere Format als Vorauswahl
        $sfd.Filter = 'JSON (*.json)|*.json|HTML (*.html)|*.html'
        $sfd.FileName = "$base.json"
    } else {
        $sfd.Filter = 'HTML (*.html)|*.html|JSON (*.json)|*.json'
        $sfd.FileName = "$base.html"
    }
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $outFmt = if ([System.IO.Path]::GetExtension($sfd.FileName) -match '^(?i)\.html?$') { 'html' } else { 'json' }
    try {
        Export-Bookmarks -Path $sfd.FileName -OutFmt $outFmt
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(((T 'save_err') -f $_.Exception.Message),
            (T 't_error'), 'OK', 'Error') | Out-Null
        return
    }
    $key = if ($outFmt -eq 'html') { 'saved_html' } else { 'saved' }
    [System.Windows.Forms.MessageBox]::Show(((T $key) -f $sfd.FileName),
        (T 't_done'), 'OK', 'Information') | Out-Null
    $script:Dirty = $false
})

# ---- gemeinsames Speichern ----
function Delete-Marked {
    param($Grid, [string]$Label)
    if ($script:Running) { return }
    $DelIds = Get-CheckedIds -Grid $Grid
    if ($DelIds.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((T 'no_marked'), (T 't_hint'),
            'OK', 'Information') | Out-Null
        return
    }
    $ans = [System.Windows.Forms.MessageBox]::Show(
        ((T 'confirm_del') -f $DelIds.Count, $Label),
        (T 't_confirm'), 'YesNo', 'Question')
    if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    Prune-Tree -Node $script:Data -DelSet $DelIds
    $script:Dirty = $true
    Rebuild-Items
    foreach ($id in @($DelIds)) { $script:AvResults.Remove($id) }
    Refresh-AvTable
    if ($gridDup.Rows.Count -gt 0) { Find-Duplicates }
    $btnDelAv.Enabled = ($script:AvResults.Count -gt 0)
    Set-LocText $lblFile 'remaining' @([System.IO.Path]::GetFileName($script:FilePath), $script:Items.Count)
    Set-LocText $lblStatus 'deleted' @($DelIds.Count)
    Set-LocText $lblDup 'deleted' @($DelIds.Count)
}

function Save-TreeAs {
    if ($script:Running -or $null -eq $script:Data) { return }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = T 'save_title'
    $base = [System.IO.Path]::GetFileNameWithoutExtension($script:FilePath)
    if ($script:Format -eq 'html') {
        $sfd.Filter = 'HTML (*.html)|*.html|JSON (*.json)|*.json'
        $sfd.FileName = $base + (T 'sfx_clean') + '.html'
    } else {
        $sfd.Filter = 'JSON (*.json)|*.json|HTML (*.html)|*.html'
        $sfd.FileName = $base + (T 'sfx_clean') + '.json'
    }
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $outFmt = if ([System.IO.Path]::GetExtension($sfd.FileName) -match '^(?i)\.html?$') { 'html' } else { 'json' }
    try {
        Export-Bookmarks -Path $sfd.FileName -OutFmt $outFmt
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show(((T 'save_err') -f $_.Exception.Message),
            (T 't_error'), 'OK', 'Error') | Out-Null
        return
    }
    $savedKey = if ($outFmt -eq 'html') { 'saved_html' } else { 'saved' }
    [System.Windows.Forms.MessageBox]::Show(((T $savedKey) -f $sfd.FileName),
        (T 't_done'), 'OK', 'Information') | Out-Null
    $script:Dirty = $false
}

$btnDelAv.Add_Click({ Delete-Marked -Grid $gridAv -Label (T 'items_bk') })
$btnDelDup.Add_Click({ Delete-Marked -Grid $gridDup -Label (T 'items_dup') })
$btnSaveAv.Add_Click({ Save-TreeAs })
$btnSaveDup.Add_Click({ Save-TreeAs })

# ---- CSV-Report ----
$btnCsv.Add_Click({
    if ($script:AvResults.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show((T 'no_results'), (T 't_hint'),
            'OK', 'Information') | Out-Null
        return
    }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Title = T 'csv_title'; $sfd.Filter = 'CSV (*.csv)|*.csv'; $sfd.FileName = 'report.csv'
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $catMap = @{ ok = (T 'cat_ok'); verdaechtig = (T 'cat_susp'); tot = (T 'cat_tot'); bot = (T 'cat_bot') }
    $rows = foreach ($r in $script:AvResults.Values) {
        $item = $script:ItemById[$r.Id]
        $o = [ordered]@{}
        $o['Kategorie/Category'] = $catMap[$r.Cat]
        $o[(T 'col_status')]     = Get-StatusText $r
        $o[(T 'col_code')]       = $r.Code
        $o[(T 'col_title')]      = if ($r.Title) { $r.Title } elseif ($item) { $item.Title } else { '' }
        $o[(T 'col_url')]        = $r.Url
        $o[(T 'col_redirect')]   = if ($r.ContainsKey('Final')) { $r.Final } else { '' }
        $o[(T 'col_folder')]     = if ($item) { $item.Folder } else { '' }
        [pscustomobject]$o
    }
    $rows | Export-Csv -LiteralPath $sfd.FileName -Delimiter ';' -NoTypeInformation -Encoding utf8BOM
    [System.Windows.Forms.MessageBox]::Show(((T 'csv_saved') -f $sfd.FileName),
        (T 't_done'), 'OK', 'Information') | Out-Null
})

# ---- Dubletten ----
function Auto-MarkDups {
    foreach ($row in $gridDup.Rows) {
        $keep = $false
        if ($row.Tag) { $keep = [bool]$row.Tag.Keep }
        $row.Cells['sel'].Value = (-not $keep)
    }
    $gridDup.RefreshEdit()
}

# Blendet die URL-Vergleichsoptionen aus, wenn nach Titel verglichen wird
function Update-DupModeUi {
    $urlMode = ($cmbDupMode.SelectedIndex -ne 1)
    foreach ($c in @($lblCmp, $chkCase, $chkFrag, $chkSlash, $chkQuery, $chkSub)) {
        $c.Enabled = $urlMode
    }
}
$cmbDupMode.Add_SelectedIndexChanged({
    if ($script:UpdatingUi) { return }
    Update-DupModeUi
})

function Find-Duplicates {
    if ($script:Items.Count -eq 0) { return }
    $byTitle = ($cmbDupMode.SelectedIndex -eq 1)
    $groups = @{}
    foreach ($it in $script:Items) {
        if ($byTitle) {
            # Titel-Vergleich: Whitespace normalisieren, Gross/Klein ignorieren
            $key = (([string]$it.Title) -replace '\s+', ' ').Trim().ToLowerInvariant()
            if (-not $key) { continue }   # Eintraege ohne Titel nicht gruppieren
        } else {
            $key = Normalize-Url -Url $it.Url -IgnFrag $chkFrag.Checked -IgnSlash $chkSlash.Checked `
                -IgnQuery $chkQuery.Checked -CiHost $chkCase.Checked -IgnSub $chkSub.Checked
        }
        if (-not $groups.ContainsKey($key)) { $groups[$key] = New-Object System.Collections.ArrayList }
        [void]$groups[$key].Add($it)
    }
    $dupGroups = @($groups.Values | Where-Object { $_.Count -gt 1 })
    $dupGroups = @($dupGroups | Sort-Object { -1 * $_.Count })

    $gridDup.Rows.Clear()
    $gi = 0; $nExtra = 0
    foreach ($group in $dupGroups) {
        $gi++
        $n = $group.Count
        for ($idx = 0; $idx -lt $n; $idx++) {
            $it = $group[$idx]
            $keep = ($idx -eq 0)
            $label = "#$gi  ($($idx + 1)/$n)"
            $title = if ($it.Title) { $it.Title } else { [string][char]0x2014 }
            $ri = $gridDup.Rows.Add(@($false, $label, $title, $it.Url, $it.Folder))
            $rw = $gridDup.Rows[$ri]
            $rw.Tag = [pscustomobject]@{ Id = $it.Id; Keep = $keep }
            $rw.DefaultCellStyle.ForeColor = if ($keep) { $ColOk } else { $ColTot }
            if (-not $keep) { $nExtra++ }
        }
    }
    $btnDelDup.Enabled = ($dupGroups.Count -gt 0)
    if ($dupGroups.Count -gt 0) {
        Set-LocText $lblDup 'dup_status' @($dupGroups.Count, $nExtra)
    } else {
        Set-LocText $lblDup 'no_dups'
    }
    Auto-MarkDups
}
$btnDup.Add_Click({ Find-Duplicates })

$btnDupAuto.Add_Click({ Auto-MarkDups })
$btnDupAll.Add_Click({ Set-AllChecks -Grid $gridDup -Value $true })
$btnDupNone.Add_Click({ Set-AllChecks -Grid $gridDup -Value $false })

# ---------------------------------------------------------------------------
# Layout: rechtsbuendige Elemente positionieren
# ---------------------------------------------------------------------------
function Update-RightAligned {
    $cmbLang.Left = [Math]::Max(700, $panelTop.ClientSize.Width - $cmbLang.Width - 8)
    $cmbLang.Top = 9
    $chkDark.Left = $cmbLang.Left - $chkDark.Width - 14
    $chkDark.Top = 12
    $btnSaveAv.Left = [Math]::Max(770, $avAct.ClientSize.Width - $btnSaveAv.Width - 8)
    $btnSaveAv.Top = 6
    $btnDelAv.Left = $btnSaveAv.Left - $btnDelAv.Width - 8
    $btnDelAv.Top = 6
    $btnSaveDup.Left = [Math]::Max(770, $dupAct.ClientSize.Width - $btnSaveDup.Width - 8)
    $btnSaveDup.Top = 6
    $btnDelDup.Left = $btnSaveDup.Left - $btnDelDup.Width - 8
    $btnDelDup.Top = 6
    $lblStatus.Left = [Math]::Max(420, $avProg.ClientSize.Width - $lblStatus.Width - 8)
    $progress.Width = [Math]::Max(200, $lblStatus.Left - $progress.Left - 8)
    # 429-Wartezeit-Feld direkt hinter das Label setzen (Sprachwechsel!)
    $numRetry.Left = $lblRetry.Left + $lblRetry.Width + 6
}
$panelTop.Add_Resize({ Update-RightAligned })
$avAct.Add_Resize({ Update-RightAligned })
$dupAct.Add_Resize({ Update-RightAligned })
$avProg.Add_Resize({ Update-RightAligned })
$form.Add_Shown({ Update-RightAligned })

# ---------------------------------------------------------------------------
# Hell-/Dunkelmodus
# ---------------------------------------------------------------------------
function Set-ThemeRecursive($Ctrl, $P) {
    foreach ($c in $Ctrl.Controls) {
        switch ($c.GetType().Name) {
            'Panel'           { $c.BackColor = $P.Back }
            'FlowLayoutPanel' { $c.BackColor = $P.Back }
            'TabPage'         { $c.BackColor = $P.Back }
            'Label'           { $c.ForeColor = $P.Text }
            'CheckBox'        { $c.ForeColor = $P.Text; $c.BackColor = $P.Back }
            'Button' {
                if ($P.Dark) {
                    $c.FlatStyle = 'Flat'
                    $c.BackColor = $P.Ctl; $c.ForeColor = $P.Text
                    $c.FlatAppearance.BorderColor = $P.Border
                } else {
                    $c.FlatStyle = 'Standard'
                    $c.BackColor = [System.Drawing.SystemColors]::Control
                    $c.ForeColor = [System.Drawing.SystemColors]::ControlText
                    $c.UseVisualStyleBackColor = $true
                }
            }
            'NumericUpDown'   { $c.BackColor = $P.Field; $c.ForeColor = $P.Text }
            'TextBox'         { $c.BackColor = $P.Field; $c.ForeColor = $P.Text }
            'ComboBox'        { $c.BackColor = $P.Field; $c.ForeColor = $P.Text
                                $c.FlatStyle = if ($P.Dark) { 'Flat' } else { 'Standard' } }
            'DataGridView' {
                $c.EnableHeadersVisualStyles = -not $P.Dark
                $c.BackgroundColor = $P.Back
                $c.GridColor = $P.Border
                $c.DefaultCellStyle.BackColor = $script:ColRowBack
                $c.DefaultCellStyle.ForeColor = $P.Text
                $c.DefaultCellStyle.SelectionBackColor = $P.Sel
                $c.DefaultCellStyle.SelectionForeColor = $P.Text
                $c.ColumnHeadersDefaultCellStyle.BackColor = $P.Ctl
                $c.ColumnHeadersDefaultCellStyle.ForeColor = $P.Text
            }
        }
        if ($c.Controls.Count -gt 0) { Set-ThemeRecursive $c $P }
    }
}

function Apply-Theme {
    if ($script:Dark) {
        $P = @{ Dark = $true
                Back   = [System.Drawing.Color]::FromArgb(32, 32, 34)
                Ctl    = [System.Drawing.Color]::FromArgb(52, 52, 56)
                Field  = [System.Drawing.Color]::FromArgb(45, 45, 48)
                Text   = [System.Drawing.Color]::FromArgb(230, 230, 230)
                Border = [System.Drawing.Color]::FromArgb(90, 90, 95)
                Sel    = [System.Drawing.Color]::FromArgb(60, 80, 110) }
        # Kategorie-Farben: auf dunklem Grund hellere Varianten
        $script:ColTot  = [System.Drawing.Color]::FromArgb(255, 110, 97)
        $script:ColSusp = [System.Drawing.Color]::FromArgb(224, 178, 60)
        $script:ColOk   = [System.Drawing.Color]::FromArgb(96, 211, 130)
        $script:ColBot  = [System.Drawing.Color]::FromArgb(199, 146, 234)
        $script:ColHl   = [System.Drawing.Color]::FromArgb(84, 76, 28)
        $script:ColRowBack = [System.Drawing.Color]::FromArgb(37, 37, 40)
        $script:ThTabSel = $P.Back; $script:ThTabBar = $P.Ctl; $script:ThText = $P.Text
        $gray = [System.Drawing.Color]::FromArgb(170, 170, 170)
    } else {
        $P = @{ Dark = $false
                Back   = [System.Drawing.SystemColors]::Control
                Ctl    = [System.Drawing.SystemColors]::Control
                Field  = [System.Drawing.SystemColors]::Window
                Text   = [System.Drawing.SystemColors]::ControlText
                Border = [System.Drawing.SystemColors]::ControlDark
                Sel    = [System.Drawing.SystemColors]::Highlight }
        $script:ColTot  = [System.Drawing.Color]::FromArgb(192, 57, 43)
        $script:ColSusp = [System.Drawing.Color]::FromArgb(154, 103, 0)
        $script:ColOk   = [System.Drawing.Color]::FromArgb(26, 127, 55)
        $script:ColBot  = [System.Drawing.Color]::FromArgb(113, 54, 138)
        $script:ColHl   = [System.Drawing.Color]::FromArgb(255, 246, 178)
        $script:ColRowBack = [System.Drawing.Color]::White
        $script:ThTabSel = [System.Drawing.SystemColors]::Window
        $script:ThTabBar = [System.Drawing.SystemColors]::Control
        $script:ThText   = [System.Drawing.SystemColors]::ControlText
        $gray = [System.Drawing.Color]::DimGray
    }
    $script:ThemeP = $P
    $form.BackColor = $P.Back
    Set-ThemeRecursive $form $P
    # Kontextmenue mitfaerben
    $ctxMenu.BackColor = $P.Ctl; $ctxMenu.ForeColor = $P.Text
    foreach ($mi in $ctxMenu.Items) { $mi.BackColor = $P.Ctl; $mi.ForeColor = $P.Text }
    # Grautoene und Legendenfarben nach dem Walker gezielt setzen
    $lblFile.ForeColor   = $gray
    $lblDup.ForeColor    = $gray
    $lblLegDbl.ForeColor = $gray
    $lblLegT.ForeColor   = $P.Text
    $lblLegOk.ForeColor  = $script:ColOk
    $lblLegSusp.ForeColor= $script:ColSusp
    $lblLegBot.ForeColor = $script:ColBot
    $lblLegTot.ForeColor = $script:ColTot
    $lblLegHl.BackColor  = $script:ColHl
    $lblLegHl.ForeColor  = $P.Text
    # bereits vorhandene Ergebnis-Zeilen mit der neuen Palette umfaerben
    if ($script:RowById -and $script:RowById.Count -gt 0) {
        $hl = Get-HighlightKeys
        foreach ($id in @($script:RowById.Keys)) {
            $r = $script:AvResults[$id]
            if ($r) { Style-Row $script:RowById[$id] $r $hl }
        }
    }
    foreach ($row in $gridDup.Rows) {
        if ($row.Tag) {
            $row.DefaultCellStyle.ForeColor = if ($row.Tag.Keep) { $script:ColOk } else { $script:ColTot }
            $row.DefaultCellStyle.BackColor = $script:ColRowBack
        }
    }
    $tabs.Invalidate()
}

$chkDark.Add_CheckedChanged({
    $script:Dark = $chkDark.Checked
    Apply-Theme
})

# Aufraeumen beim Schliessen
$form.Add_FormClosing({
    param($s, $e)
    if ($script:Dirty) {
        $ans = [System.Windows.Forms.MessageBox]::Show((T 'confirm_close'),
            (T 't_confirm'), 'YesNo', 'Warning')
        if ($ans -ne [System.Windows.Forms.DialogResult]::Yes) {
            $e.Cancel = $true
            return
        }
    }
    try { $timer.Stop() } catch { }
    Dispose-Jobs
})

Apply-Language
Apply-Theme
Update-RightAligned
[void]$form.ShowDialog()
