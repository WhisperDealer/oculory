# Dot-source from the repo root to load workspace tool paths:
#     . ".claude/config/tools.ps1"
#     & $Tools.spriggitCli serialize ...
#
# Reads .claude/config/tools.json (machine-specific, gitignored). Falls back to
# tools.example.json so a fresh clone still resolves. Populate/refresh tools.json
# with the `modlist-install` skill.

$cfgDir = Split-Path -Parent $PSCommandPath
$cfgPath = Join-Path $cfgDir 'tools.json'
if (-not (Test-Path $cfgPath)) {
    $cfgPath = Join-Path $cfgDir 'tools.example.json'
    Write-Warning "tools.json not found; using tools.example.json. Run the modlist-install skill to generate tools.json."
}
$Tools = Get-Content -Raw -LiteralPath $cfgPath | ConvertFrom-Json

# Verify the tools an operation needs before relying on them. Usage:
#     Assert-Tool $Tools.papyrusCompiler 'papyrusCompiler'
function Assert-Tool {
    param([string]$Path, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Config key '$Name' is empty in $cfgPath. Set it (modlist-install skill) and retry."
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "'$Name' points at a missing path: $Path  (config: $cfgPath)"
    }
    return $Path
}
