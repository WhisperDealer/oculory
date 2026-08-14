<#
.SYNOPSIS
  Fast structural sanity check for Spriggit record YAML.

.DESCRIPTION
  Catches the cheap-to-detect, expensive-to-debug mistakes in hand-edited Spriggit YAML *before*
  they reach a build or a play session:

    - a UTF-8 BOM or CRLF line endings (Spriggit writes UTF-8 / LF; .gitattributes enforces it)
    - tab characters used for indentation (invalid YAML - the parser will reject the file)
    - odd indentation, trailing whitespace
    - a filename whose <EditorID> / <FormID> disagrees with the EditorID: / FormKey: inside it
    - a new FormID outside 0x800-0xFFF in an ESL ('Small') flagged plugin

  This is deliberately NOT a YAML parser. Windows PowerShell 5.1 ships no YAML support, and a full
  parse would be slow to run on every edit. The checks above are the ones that actually recur.
  For deep semantic auditing (collisions, dangling references, in-game anti-patterns) use the
  `spriggit-formkey-auditor` subagent instead - see arch-docs/skyrim-record-patterns.md.

  Only files that live inside a Spriggit plugin folder are examined. A folder counts as one when it,
  or one of its ancestors, contains a spriggit-meta.json. Everything else is ignored, so this is safe
  to point at arbitrary paths (workflow YAML, configs, ...).

.PARAMETER Path
  One or more .yaml files, or folders to scan recursively. When omitted, the YAML that git tracks
  (plus new, not-yet-ignored files) is checked - deliberately NOT a walk of the repo root, since
  reference/ and modlist/ are gitignored and can be hundreds of gigabytes.

.PARAMETER FromHook
  Read a Claude Code PostToolUse hook payload from stdin and check the file it touched.
  Exits 2 with findings on stderr so the agent sees and fixes them; exits 0 otherwise.

.EXAMPLE
  pwsh build/Test-RecordYaml.ps1
  pwsh build/Test-RecordYaml.ps1 -Path src/ExampleMod/ExampleModESP
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [switch]$FromHook
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot

# ---- Findings ---------------------------------------------------------------
$script:Findings = @()

function Add-Finding {
    param(
        [string]$File,
        [int]$Line,
        [ValidateSet('error', 'warning')][string]$Severity,
        [string]$Message
    )
    $rel = $File
    if ($File.StartsWith($RepoRoot)) { $rel = $File.Substring($RepoRoot.Length).TrimStart('\', '/') }
    $script:Findings += [pscustomobject]@{
        File     = $rel -replace '\\', '/'
        Line     = $Line
        Severity = $Severity
        Message  = $Message
    }
}

# ---- Plugin-folder discovery ------------------------------------------------
# Walk up from a file until we find the spriggit-meta.json that owns it. Returns $null when the
# file is not part of a Spriggit plugin (so we leave it alone).
$script:PluginCache = @{}

function Get-PluginRoot {
    param([string]$FilePath)
    $dir = Split-Path -Parent $FilePath
    while ($dir -and $dir.Length -ge $RepoRoot.Length) {
        if ($script:PluginCache.ContainsKey($dir)) { return $script:PluginCache[$dir] }
        if (Test-Path (Join-Path $dir 'spriggit-meta.json')) {
            $script:PluginCache[$dir] = $dir
            return $dir
        }
        $parent = Split-Path -Parent $dir
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

# Reads ModKey + ESL flag out of a plugin's root RecordData.yaml. Cheap regex, not a YAML parse -
# both keys sit at a known depth in a file Spriggit generates, so this is stable.
$script:HeaderCache = @{}

function Get-PluginHeader {
    param([string]$PluginRoot)
    if ($script:HeaderCache.ContainsKey($PluginRoot)) { return $script:HeaderCache[$PluginRoot] }
    $info = [pscustomobject]@{ ModKey = $null; IsEsl = $false }
    $headerPath = Join-Path $PluginRoot 'RecordData.yaml'
    if (Test-Path $headerPath) {
        $text = Get-Content $headerPath -Raw
        if ($text -match '(?m)^ModKey:\s*(.+?)\s*$') { $info.ModKey = $Matches[1].Trim() }
        if ($text -match '(?ms)^ModHeader:.*?^\s{2}Flags:\s*\r?\n(?:\s*-\s*\w+\r?\n)*?\s*-\s*Small\b') {
            $info.IsEsl = $true
        }
    }
    $script:HeaderCache[$PluginRoot] = $info
    return $info
}

# ---- The checks -------------------------------------------------------------
function Test-RecordFile {
    param([string]$FilePath)

    $pluginRoot = Get-PluginRoot -FilePath $FilePath
    if (-not $pluginRoot) { return }          # not Spriggit YAML - not our business

    $name = Split-Path -Leaf $FilePath

    # --- byte-level: BOM ---
    # Line endings are deliberately NOT checked here. .gitattributes pins *.yaml to eol=lf in the
    # index, so git owns normalization; on Windows with core.autocrlf=true the working-tree copy is
    # legitimately CRLF and flagging it would fire on every file for every Windows contributor.
    $bytes = [System.IO.File]::ReadAllBytes($FilePath)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-Finding $FilePath 1 'error' 'File starts with a UTF-8 BOM. Spriggit writes UTF-8 without BOM; rewrite it (in PowerShell use [System.IO.File]::WriteAllText, or Set-Content -Encoding utf8 on PS7+).'
    }
    $raw = [System.Text.Encoding]::UTF8.GetString($bytes)

    # --- line-level ---
    $lines = $raw -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $lineNo = $i + 1
        if ($line -match '^[ ]*\t') {
            Add-Finding $FilePath $lineNo 'error' 'Tab character used for indentation. YAML forbids tabs - this file will fail to parse. Use spaces.'
            continue
        }
        if ($line.Trim().Length -gt 0) {
            $indent = $line.Length - $line.TrimStart(' ').Length
            if ($indent % 2 -ne 0) {
                Add-Finding $FilePath $lineNo 'warning' "Indentation is $indent spaces (not a multiple of 2). Spriggit emits 2-space indentation; odd indentation usually means a hand-edit went in at the wrong depth."
            }
        }
        if ($line -match '[ \t]+$') {
            Add-Finding $FilePath $lineNo 'warning' 'Trailing whitespace.'
        }
    }

    # --- filename <-> content agreement ---
    # Spriggit names flat records "<EditorID> - <FormID>_<DefiningMaster>.esp.yaml".
    # Nested cell/worldspace leaves are RecordData.yaml / GroupRecordData.yaml inside a folder named
    # that way instead, so they are exempt from this check.
    if ($name -ne 'RecordData.yaml' -and $name -ne 'GroupRecordData.yaml') {
        if ($name -match '^(?<eid>.+) - (?<fid>[0-9A-Fa-f]{6})_(?<master>.+)\.(?:esp|esm|esl)\.yaml$') {
            $fileEid    = $Matches['eid']
            $fileFid    = $Matches['fid']
            $fileMaster = $Matches['master']

            if ($raw -match '(?m)^FormKey:\s*([0-9A-Fa-f]{6}):(.+?)\s*$') {
                $innerFid    = $Matches[1]
                $innerMaster = $Matches[2].Trim()
                if ($innerFid -ne $fileFid) {
                    Add-Finding $FilePath 1 'error' "Filename says FormID $fileFid but FormKey: inside says $innerFid. One of them is a copy-paste leftover."
                }
                if ($innerMaster -ne "$fileMaster.esp" -and $innerMaster -ne "$fileMaster.esm" -and $innerMaster -ne "$fileMaster.esl") {
                    Add-Finding $FilePath 1 'error' "Filename says master '$fileMaster' but FormKey: inside says '$innerMaster'."
                }
            }

            if ($raw -match '(?m)^EditorID:\s*(.+?)\s*$') {
                $innerEid = $Matches[1].Trim().Trim("'", '"')
                if ($innerEid -ne $fileEid) {
                    Add-Finding $FilePath 1 'error' "Filename says EditorID '$fileEid' but EditorID: inside says '$innerEid'. Rename the file to match, or fix the EditorID."
                }
            }
        }
        else {
            Add-Finding $FilePath 1 'warning' "Filename does not follow Spriggit's '<EditorID> - <FormID>_<Master>.esp.yaml' convention. Spriggit will rename it on the next serialize."
        }
    }

    # --- ESL FormID range ---
    $header = Get-PluginHeader -PluginRoot $pluginRoot
    if ($header.IsEsl -and $header.ModKey) {
        if ($raw -match '(?m)^FormKey:\s*([0-9A-Fa-f]{6}):(.+?)\s*$') {
            $fid    = $Matches[1]
            $master = $Matches[2].Trim()
            if ($master -eq $header.ModKey) {
                $val = [Convert]::ToInt32($fid, 16)
                if ($val -lt 0x800 -or $val -gt 0xFFF) {
                    Add-Finding $FilePath 1 'error' ("FormID 0x{0} is outside the ESL range 0x800-0xFFF, and '{1}' is Small-flagged. The record will not load correctly." -f $fid.ToUpper(), $header.ModKey)
                }
            }
        }
    }
}

# ---- Input resolution -------------------------------------------------------
$targets = @()

if ($FromHook) {
    $payloadRaw = [Console]::In.ReadToEnd()
    if (-not $payloadRaw) { exit 0 }
    try { $payload = $payloadRaw | ConvertFrom-Json } catch { exit 0 }
    $hookFile = $null
    if ($payload.PSObject.Properties.Name -contains 'tool_input' -and $payload.tool_input) {
        if ($payload.tool_input.PSObject.Properties.Name -contains 'file_path') {
            $hookFile = $payload.tool_input.file_path
        }
    }
    if (-not $hookFile) { exit 0 }
    if (-not ($hookFile.ToLower().EndsWith('.yaml') -or $hookFile.ToLower().EndsWith('.yml'))) { exit 0 }
    if (-not (Test-Path $hookFile)) { exit 0 }
    $targets = @((Resolve-Path $hookFile).Path)
}
elseif (-not $Path -or $Path.Count -eq 0) {
    # Default: ask git for the YAML it tracks (plus new, not-yet-ignored files).
    # Do NOT walk the repo root - reference/ and modlist/ are gitignored and can hold hundreds of
    # gigabytes of decompiled masters and an entire MO2 instance, so a naive recursive scan hangs.
    Push-Location $RepoRoot
    try {
        $gitFiles = @(& git ls-files --cached --others --exclude-standard -- '*.yaml' 2>$null)
        if ($LASTEXITCODE -ne 0 -or $gitFiles.Count -eq 0) {
            throw "Could not list YAML via git (not a git repo, or no YAML tracked). Pass -Path explicitly."
        }
        $targets = @($gitFiles | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path $_ })
    }
    finally { Pop-Location }
}
else {
    foreach ($p in $Path) {
        if (-not (Test-Path $p)) { throw "Path not found: $p" }
        $item = Get-Item $p
        if ($item.PSIsContainer) {
            $targets += @(Get-ChildItem $p -Recurse -Filter *.yaml -File | ForEach-Object { $_.FullName })
        }
        else {
            $targets += $item.FullName
        }
    }
}

foreach ($t in $targets) { Test-RecordFile -FilePath $t }

# ---- Report -----------------------------------------------------------------
$errors   = @($script:Findings | Where-Object { $_.Severity -eq 'error' })
$warnings = @($script:Findings | Where-Object { $_.Severity -eq 'warning' })

if ($script:Findings.Count -eq 0) {
    if (-not $FromHook) {
        Write-Host "Checked $($targets.Count) file(s) - no issues." -ForegroundColor Green
    }
    exit 0
}

$sb = [System.Text.StringBuilder]::new()
foreach ($f in ($errors + $warnings)) {
    [void]$sb.AppendLine("[$($f.Severity)] $($f.File):$($f.Line) - $($f.Message)")
}
$reportText = $sb.ToString().TrimEnd()

if ($FromHook) {
    # Exit 2 puts stderr in front of the agent so it can fix the file it just wrote.
    # Warnings alone are not worth interrupting for.
    if ($errors.Count -gt 0) {
        [Console]::Error.WriteLine("Spriggit record YAML problems in the file you just edited:")
        [Console]::Error.WriteLine($reportText)
        exit 2
    }
    exit 0
}

Write-Host $reportText
Write-Host ""
Write-Host "$($errors.Count) error(s), $($warnings.Count) warning(s) across $($targets.Count) file(s)."
if ($errors.Count -gt 0) { exit 1 }
exit 0
