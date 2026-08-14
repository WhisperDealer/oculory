<#
.SYNOPSIS
  Build this workspace's release archives from Spriggit YAML + committed .pex.

.DESCRIPTION
  Data-driven by build/manifest.json - the script contains no mod-specific names. build/staging/<release>/
  is a committed tree: only its fomod/ subfolder is source (checked into git); the rest is derived and
  regenerated on every run. For each release:
    1. verifies the committed build/staging/<release>/fomod/ exists (does not touch it)
    2. deserializes each plugin's YAML -> <release>/<dest>.esp via the Spriggit CLI (overwriting any stale copy)
    3. copies the release's committed compiled .pex into its Scripts/ folder (overwriting any stale copy)
    4. compresses build/staging/<release>/ -> build/dist/<archiveName>.7z
  Then writes a markdown build report to arch-docs/build-report.md.

  Runs both locally (Spriggit CLI path auto-resolved from .claude/config/tools.json) and in
  GitHub Actions (pass -SpriggitCli explicitly). It never invokes the Papyrus compiler - the
  .pex are expected to be committed and current (recompile + commit when a .psc changes).

.PARAMETER SpriggitCli
  Path to Spriggit.CLI.exe. Defaults to $Tools.spriggitCli from tools.json when available.

.PARAMETER CheckFomod
  Only verify manifest <-> fomod/ModuleConfig.xml parity, then exit (no build).
#>
[CmdletBinding()]
param(
    [string]$SpriggitCli,
    [string]$OutDir      = 'build/staging',
    [string]$ArchiveDir  = 'build/dist',
    [string]$Report      = 'arch-docs/build-report.md',
    [switch]$CheckFomod
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $RepoRoot

function Resolve-SpriggitCli {
    param([string]$Explicit)
    if ($Explicit) {
        if (-not (Test-Path $Explicit)) { throw "Spriggit CLI not found at: $Explicit" }
        return $Explicit
    }
    $toolsPs1 = Join-Path $RepoRoot '.claude/config/tools.ps1'
    if (Test-Path $toolsPs1) {
        . $toolsPs1
        if ($Tools.spriggitCli -and (Test-Path $Tools.spriggitCli)) { return $Tools.spriggitCli }
    }
    throw "Spriggit CLI path not supplied and not resolvable from tools.json. Pass -SpriggitCli <path>."
}

function Resolve-SevenZip {
    $cmd = Get-Command '7z' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe'
    )
    foreach ($c in $candidates) { if (Test-Path $c) { return $c } }
    throw "7z.exe not found (needed for archiving). Install 7-Zip or add it to PATH."
}

function Get-PluginMasters {
    param([string]$YamlSrc)
    $header = Join-Path $YamlSrc 'RecordData.yaml'
    if (-not (Test-Path $header)) { return '(unknown)' }
    $lines = Get-Content $header
    $masters = @()
    $inMasters = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*MasterReferences:') { $inMasters = $true; continue }
        if ($inMasters) {
            if ($line -match '^\s*-?\s*Master:\s*(.+?)\s*$') { $masters += $Matches[1].Trim() }
            elseif ($line -match '^\S') { break }   # dedented to a new top-level key
        }
    }
    if ($masters.Count -eq 0) { return '(none)' }
    return ($masters -join ', ')
}

function Get-RecordCount {
    param([string]$YamlSrc)
    # Every .yaml is a record EXCEPT the plugin header (the root RecordData.yaml) and the
    # GroupRecordData.yaml files that mark cell/worldspace grouping levels. Note that *nested*
    # RecordData.yaml files ARE records - they are the leaf of a cell/worldspace record folder -
    # so only the one at the root is excluded.
    $rootHeader = (Join-Path $YamlSrc 'RecordData.yaml')
    $all = @(Get-ChildItem $YamlSrc -Recurse -Filter *.yaml -File -ErrorAction SilentlyContinue)
    $count = @($all | Where-Object {
        $_.Name -ne 'GroupRecordData.yaml' -and $_.FullName -ne (Resolve-Path $rootHeader -ErrorAction SilentlyContinue).Path
    }).Count
    return $count
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Write-Report {
    param($Path, $Plugins, $Archives, $Scripts)
    # Resolve the commit for the report header. Must not throw: a brand-new clone of this template
    # has no commits yet, and `git rev-parse HEAD` then writes to stderr, which $ErrorActionPreference
    # = 'Stop' would otherwise promote into a terminating NativeCommandError and fail the build.
    $sha = $null
    try {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        $sha = (& git rev-parse HEAD 2>$null | Select-Object -First 1)
        $ErrorActionPreference = $prev
    }
    catch { $sha = $null }
    if (-not $sha -or $sha -notmatch '^[0-9a-f]{40}$') { $sha = $env:GITHUB_SHA }
    $ref  = $env:GITHUB_REF_NAME
    $when = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') + ' UTC'
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Build Report')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('> Auto-generated by `build/build.ps1`. Do not edit by hand.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("- **Built:** $when")
    if ($sha) { [void]$sb.AppendLine("- **Commit:** ``$sha``") }
    if ($ref) { [void]$sb.AppendLine("- **Ref:** ``$ref``") }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Archives')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Archive | Size | SHA-256 |')
    [void]$sb.AppendLine('|---|---|---|')
    foreach ($a in $Archives) {
        [void]$sb.AppendLine("| $($a.Name) | $(Format-Size $a.Bytes) | ``$($a.Sha256)`` |")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## Plugins')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Release | Plugin | Records | Masters |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($p in $Plugins) {
        [void]$sb.AppendLine("| $($p.Release) | $($p.Dest) | $($p.Records) | $($p.Masters) |")
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("## Scripts - $(@($Scripts).Count) .pex")
    [void]$sb.AppendLine('')
    foreach ($s in $Scripts) { [void]$sb.AppendLine("- $s") }
    [void]$sb.AppendLine('')
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    # Write UTF-8 *without* a BOM explicitly. `Set-Content -Encoding UTF8` means BOM on Windows
    # PowerShell 5.1 but no BOM on pwsh 7, so this file would flip encoding depending on whether it
    # was built locally or in CI - and since CI commits it, that is pure diff churn.
    [System.IO.File]::WriteAllText($Path, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  report -> $Path"
}

# ---- Load manifest ---------------------------------------------------------
$manifestPath = Join-Path $PSScriptRoot 'manifest.json'
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

# ---- FOMOD parity check ----------------------------------------------------
function Get-JpegEncoding {
    param([string]$Path)
    # Returns 'baseline' | 'progressive' | 'unknown', or $null when the file is not a JPEG.
    # Walks the marker segments rather than grepping for FFC2: every marker ahead of the SOS
    # entropy-coded data carries its own length, so we can step over payloads exactly. A naive
    # byte search would false-positive on compressed scan data that happens to contain FF C2.
    try { $bytes = [System.IO.File]::ReadAllBytes($Path) } catch { return $null }
    if ($bytes.Length -lt 4) { return $null }
    if ($bytes[0] -ne 0xFF -or $bytes[1] -ne 0xD8) { return $null }   # no SOI => not a JPEG
    $i = 2
    while ($i -lt $bytes.Length - 1) {
        if ($bytes[$i] -ne 0xFF) { return 'unknown' }
        $marker = $bytes[$i + 1]
        if ($marker -eq 0xFF) { $i++; continue }                                    # fill byte
        if ($marker -ge 0xD0 -and $marker -le 0xD9) { $i += 2; continue }           # standalone
        if ($marker -eq 0xDA) { return 'unknown' }                                  # reached scan data
        if ($marker -eq 0xC0 -or $marker -eq 0xC1) { return 'baseline' }            # SOF0 / SOF1
        if ($marker -eq 0xC2) { return 'progressive' }                              # SOF2
        if ($i + 3 -ge $bytes.Length) { return 'unknown' }
        $len = ($bytes[$i + 2] -shl 8) -bor $bytes[$i + 3]
        if ($len -lt 2) { return 'unknown' }
        $i += 2 + $len
    }
    return 'unknown'
}

function Test-FomodParity {
    $ok = $true
    foreach ($rel in $manifest.releases) {
        # A release may opt out of a FOMOD entirely with "fomod": false - there is nothing to check.
        if (($rel.PSObject.Properties.Name -contains 'fomod') -and (-not $rel.fomod)) { continue }
        $fomod = Join-Path $RepoRoot (Join-Path (Join-Path 'build/staging' $rel.name) 'fomod/ModuleConfig.xml')
        if (-not (Test-Path $fomod)) { Write-Warning "No ModuleConfig.xml for '$($rel.name)'"; continue }
        [xml]$xml = Get-Content $fomod -Raw
        $fomodEsps = $xml.SelectNodes('//file') |
            ForEach-Object { $_.source } |
            Where-Object { $_ -and $_.ToLower().EndsWith('.esp') } |
            ForEach-Object { $_.Replace('\','/') } | Sort-Object -Unique
        $manifestDests = @($rel.plugins | ForEach-Object { $_.dest.Replace('\','/') })
        foreach ($f in $fomodEsps) {
            if ($manifestDests -notcontains $f) {
                Write-Host "  [MISSING IN MANIFEST] $($rel.name): fomod references '$f'" -ForegroundColor Red
                $ok = $false
            }
        }
        # A plugin the manifest builds but the FOMOD never installs is usually an oversight (a patch
        # added to the manifest and forgotten in ModuleConfig.xml). It is only a warning, because a
        # release may legitimately stage a plugin that its installer references indirectly - set
        # "allowUnreferencedPlugins": true on the release to silence it.
        $allowUnreferenced = $false
        if ($rel.PSObject.Properties.Name -contains 'allowUnreferencedPlugins') {
            $allowUnreferenced = [bool]$rel.allowUnreferencedPlugins
        }
        if (-not $allowUnreferenced) {
            foreach ($d in $manifestDests) {
                if ($fomodEsps -notcontains $d) {
                    Write-Host "  [NOT IN FOMOD] $($rel.name): manifest builds '$d' but fomod never installs it" -ForegroundColor Yellow
                }
            }
        }

        # Installer images. A bad image reference breaks nothing detectable: the archive builds, the
        # wizard opens, and MO2 just renders a blank banner - so it costs a full install cycle to
        # notice. Both failure modes below have actually shipped from this repo. The rest of the
        # recipe (needing an <installSteps> block at all) is in CLAUDE.md under
        # "FOMOD images that actually render in MO2".
        $stageDir = Split-Path -Parent (Split-Path -Parent $fomod)
        $imageNodes = @($xml.SelectNodes('//moduleImage')) + @($xml.SelectNodes('//image'))
        # Distinct paths only: one image is typically referenced by both <moduleImage> and every
        # plugin's <image>, and repeating an identical complaint per node buries the real list.
        $imagePaths = @($imageNodes | ForEach-Object { $_.GetAttribute('path') } |
            Where-Object { $_ } | Sort-Object -Unique)
        foreach ($imgPath in $imagePaths) {
            # path= is relative to the ARCHIVE ROOT, so it must carry the "fomod/" prefix itself.
            $relPath = $imgPath.Replace('\', '/').TrimStart('/')
            $abs = Join-Path $stageDir $relPath
            if (-not (Test-Path $abs)) {
                Write-Host "  [IMAGE NOT FOUND] $($rel.name): path=`"$imgPath`" resolves to nothing" -ForegroundColor Red
                # The overwhelmingly likely cause: the "fomod/" prefix was omitted, because the path
                # looks right sitting inside fomod/ModuleConfig.xml. Say so instead of just failing.
                if (Test-Path (Join-Path (Join-Path $stageDir 'fomod') $relPath)) {
                    Write-Host "                   -> did you mean `"fomod\$($relPath.Replace('/','\'))`"? path= is relative to the archive root, not to fomod/." -ForegroundColor Red
                }
                $ok = $false
                continue
            }
            if ($imgPath.Contains('/')) {
                Write-Host "  [IMAGE PATH SEP] $($rel.name): '$imgPath' uses forward slashes; known-working configs use backslashes" -ForegroundColor Yellow
            }
            if ((Get-JpegEncoding $abs) -eq 'progressive') {
                Write-Host "  [PROGRESSIVE JPEG] $($rel.name): '$imgPath' is a progressive JPEG; re-encode as baseline or PNG" -ForegroundColor Red
                $ok = $false
            }
        }
    }
    return $ok
}

if ($CheckFomod) {
    Write-Host "Checking manifest <-> FOMOD parity..." -ForegroundColor Cyan
    if (Test-FomodParity) { Write-Host "FOMOD parity OK." -ForegroundColor Green; exit 0 }
    else { Write-Error "FOMOD parity check failed."; exit 1 }
}

# ---- Build -----------------------------------------------------------------
$spriggit = Resolve-SpriggitCli -Explicit $SpriggitCli
$sevenZip = Resolve-SevenZip
Write-Host "Spriggit CLI : $spriggit"
Write-Host "7-Zip        : $sevenZip"

$stagingAbs = Join-Path $RepoRoot $OutDir
$distAbs    = Join-Path $RepoRoot $ArchiveDir
New-Item -ItemType Directory -Force $stagingAbs | Out-Null
Remove-Item $distAbs -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $distAbs    | Out-Null

$reportPlugins = @()
$reportArchives = @()
$scriptFiles = @()

foreach ($rel in $manifest.releases) {
    Write-Host "`n=== Release: $($rel.name) ===" -ForegroundColor Cyan
    $stageDir = Join-Path $stagingAbs $rel.name

    # 1. verify the committed fomod/ is in place (it lives directly in build/staging and is never
    #    wiped by this script - only the derived parts below are regenerated).
    #
    #    A release may opt out with "fomod": false in the manifest and ship a plain archive instead.
    #    That is the right shape whenever the install has nothing to ask - a single .esp with no
    #    options. Without a committed fomod/ the stage dir is not tracked by git (it holds only
    #    derived files), so create it here.
    $wantsFomod = $true
    if ($rel.PSObject.Properties.Name -contains 'fomod') { $wantsFomod = [bool]$rel.fomod }
    $fomodDir = Join-Path $stageDir 'fomod'
    if ($wantsFomod) {
        if (-not (Test-Path $fomodDir)) { throw "Missing committed fomod/ for '$($rel.name)' at $fomodDir" }
    } else {
        if (Test-Path $fomodDir) { throw "'$($rel.name)' sets fomod: false but $fomodDir still exists - delete it" }
        New-Item -ItemType Directory -Force $stageDir | Out-Null
    }

    # Clear everything else in the stage dir (previous run's .esp/.pex) so stale derived files
    # from a renamed dest/script never survive into the new archive - fomod/ is left untouched.
    Get-ChildItem $stageDir -Force | Where-Object { $_.Name -ne 'fomod' } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # 2. deserialize each plugin
    foreach ($p in $rel.plugins) {
        $yamlSrc = Join-Path $RepoRoot $p.yamlSource
        $meta    = Join-Path $yamlSrc 'spriggit-meta.json'
        if (-not (Test-Path $meta)) { throw "Not a Spriggit YAML folder (no spriggit-meta.json): $yamlSrc" }
        $outEsp  = Join-Path $stageDir $p.dest
        New-Item -ItemType Directory -Force (Split-Path -Parent $outEsp) | Out-Null

        Write-Host "  deserialize $($p.yamlSource) -> $($p.dest)"
        & $spriggit deserialize --InputPath $yamlSrc --OutputPath $outEsp
        if ($LASTEXITCODE -ne 0) { throw "Spriggit deserialize failed for $($p.yamlSource) (exit $LASTEXITCODE)" }
        if (-not (Test-Path $outEsp)) { throw "Spriggit produced no output at $outEsp" }

        $reportPlugins += [pscustomobject]@{
            Release = $rel.name
            Dest    = $p.dest
            Masters = (Get-PluginMasters $yamlSrc)
            Records = (Get-RecordCount $yamlSrc)
        }

        # optional per-plugin scripts (a patch that ships its own committed .pex)
        if ($p.PSObject.Properties.Name -contains 'scripts' -and $p.scripts) {
            foreach ($s in $p.scripts) {
                $sFrom = Join-Path $RepoRoot $s.from
                if (-not (Test-Path $sFrom)) {
                    throw "Plugin script missing: $sFrom. Recompile (.psc -> .pex) and commit it (see README 'CI build')."
                }
                $sTo = Join-Path $stageDir $s.to
                New-Item -ItemType Directory -Force $sTo | Out-Null
                Copy-Item $sFrom $sTo -Force
                $scriptFiles = @($scriptFiles + (Split-Path -Leaf $sFrom)) | Sort-Object -Unique
                Write-Host "    + script $(Split-Path -Leaf $sFrom) -> $($s.to)/"
            }
        }
    }

    # 3. copy committed .pex (addon only)
    if ($rel.PSObject.Properties.Name -contains 'scripts' -and $rel.scripts) {
        $pexSrc = Join-Path $RepoRoot $rel.scripts.from
        $pexDst = Join-Path $stageDir $rel.scripts.to
        if (-not (Test-Path $pexSrc)) {
            throw "Compiled scripts folder missing: $pexSrc. Recompile (.psc -> .pex) and commit them (see README 'CI build')."
        }
        $pex = @(Get-ChildItem $pexSrc -Filter *.pex -File -ErrorAction SilentlyContinue)
        if (-not $pex -or $pex.Count -eq 0) {
            throw "No .pex found in $pexSrc. Recompile and commit them before building."
        }
        New-Item -ItemType Directory -Force $pexDst | Out-Null
        Copy-Item (Join-Path $pexSrc '*.pex') $pexDst -Force
        # Accumulate: a plain assignment here would discard the per-plugin script entries
        # collected above, and every release after the first would clobber the previous one.
        $scriptFiles = @($scriptFiles + $pex.Name) | Sort-Object -Unique
        Write-Host "  copied $($pex.Count) .pex -> $($rel.scripts.to)/"
    }

    # 4. archive
    $archivePath = Join-Path $distAbs ("{0}.7z" -f $rel.archiveName)
    Remove-Item $archivePath -Force -ErrorAction SilentlyContinue
    Write-Host "  archiving -> $($rel.archiveName).7z"
    Push-Location $stageDir
    try {
        & $sevenZip a -t7z -mx=9 -bso0 -bsp0 $archivePath '*' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "7z failed for $($rel.name) (exit $LASTEXITCODE)" }
    } finally { Pop-Location }

    $fi = Get-Item $archivePath
    $reportArchives += [pscustomobject]@{
        Name   = $fi.Name
        Bytes  = $fi.Length
        Sha256 = (Get-FileHash $archivePath -Algorithm SHA256).Hash
    }
}

Write-Report -Path (Join-Path $RepoRoot $Report) -Plugins $reportPlugins -Archives $reportArchives -Scripts $scriptFiles
Write-Host "`nBuild complete. Archives in $ArchiveDir, report at $Report." -ForegroundColor Green
