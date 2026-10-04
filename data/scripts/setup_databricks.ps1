<#
Gummi Data Lead: one-time Databricks setup from Windows. A HUMAN runs this, because step 1 opens a browser to log in.

Before the first run, install the Databricks CLI and open a NEW PowerShell window:
    winget install Databricks.DatabricksCLI

Run from the repo root (the folder that holds data\ and docs\):
    powershell -ExecutionPolicy Bypass -File data\scripts\setup_databricks.ps1 -WorkspaceUrl https://<your-workspace-url>
    powershell -ExecutionPolicy Bypass -File data\scripts\setup_databricks.ps1 -WorkspaceUrl https://<your-workspace-url> -Catalog <catalog>
    ... -Catalog <catalog> -Spike        (also runs the streaming spike job, decision D-21)

Every step is safe to re-run:
  1. Checks the CLI, logs in to CLI profile "gummi" if needed (browser), prints who you are       (D-02)
  2. With -Catalog "": lists the catalogs and stops, so you can pick one (default: workspace, D-07)
  3. Creates schemas gummi_data and gummi_ml, volumes raw_bigideas, landing, artifacts             (CONTRACT.md section 10)
  4. Uploads data\raw\bigideas_1.1.3 (about 240 MB) to /Volumes/<catalog>/gummi_data/raw_bigideas/bigideas_1.1.3
  5. Deploys the gummi-data bundle and runs the job gummi_data_load_train (expected 5 to 10 minutes on serverless)
  6. With -Spike: runs the job gummi_stream_spike (sample events -> landing -> gummi_stream pipeline -> checks)
Paste the whole window output back to the Data agent when it finishes or stops.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$WorkspaceUrl,
    [string]$Catalog = "workspace",
    [string]$CliProfile = "gummi",
    [switch]$SkipUpload,
    [switch]$SkipJob,
    [switch]$Spike
)

$DataDir = Split-Path -Parent $PSScriptRoot
$Raw = Join-Path $DataDir "raw\bigideas_1.1.3"

function Step([string]$Message) {
    Write-Host ""
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Stop-Here([string]$Message) {
    Write-Host ""
    Write-Host "STOPPED: $Message" -ForegroundColor Red
    Write-Host "Paste this whole window to the Data agent."
    exit 1
}

# Runs the Databricks CLI with the profile, prints its output, returns $true on success.
# "already exists" counts as success so every step can be re-run.
function Invoke-Db {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)
    $out = & databricks @CliArgs --profile $CliProfile 2>&1 | Out-String
    $code = $LASTEXITCODE
    if ($out.Trim()) { Write-Host $out.TrimEnd() }
    return (($code -eq 0) -or ($out -match "already exists|ALREADY_EXISTS"))
}

# Same, but streams output live (for long commands such as bundle run).
function Invoke-DbLive {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)
    & databricks @CliArgs --profile $CliProfile
    return ($LASTEXITCODE -eq 0)
}

Step "1. Databricks CLI and login (profile $CliProfile)"
if (-not (Get-Command databricks -ErrorAction SilentlyContinue)) {
    Write-Host "The Databricks CLI is not installed. Run this, open a NEW PowerShell window, then run this script again:" -ForegroundColor Yellow
    Write-Host "    winget install Databricks.DatabricksCLI"
    exit 1
}
& databricks --version
$me = & databricks current-user me -o json --profile $CliProfile 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not logged in yet. A browser window will open: sign in and approve." -ForegroundColor Yellow
    & databricks auth login --host $WorkspaceUrl --profile $CliProfile
    $me = & databricks current-user me -o json --profile $CliProfile 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Write-Host $me; Stop-Here "login did not work." }
}
try { Write-Host ("Logged in as " + ($me | ConvertFrom-Json).userName + " on " + $WorkspaceUrl) -ForegroundColor Green }
catch { Write-Host $me }

if (-not $Catalog) {
    Step "2. Catalogs you can see (decision D-07)"
    & databricks catalogs list --profile $CliProfile
    Write-Host ""
    Write-Host "Pick a catalog you can create schemas in (not 'system' or 'samples'), tell the Data agent which one," -ForegroundColor Yellow
    Write-Host "then run this script again with -Catalog <name>." -ForegroundColor Yellow
    exit 0
}

Step "3. Schemas and volumes in catalog $Catalog"
$ok = $true
$ok = (Invoke-Db schemas create gummi_data $Catalog) -and $ok
$ok = (Invoke-Db schemas create gummi_ml $Catalog) -and $ok
$ok = (Invoke-Db volumes create $Catalog gummi_data raw_bigideas MANAGED) -and $ok
$ok = (Invoke-Db volumes create $Catalog gummi_data landing MANAGED) -and $ok
$ok = (Invoke-Db volumes create $Catalog gummi_ml artifacts MANAGED) -and $ok
if (-not $ok) { Stop-Here "creating a schema or volume failed (catalog name or permissions)." }
Write-Host "schemas and volumes ready" -ForegroundColor Green

if (-not $SkipUpload) {
    Step "4. Upload BIG IDEAs files (about 240 MB)"
    if (-not (Test-Path (Join-Path $Raw "SHA256SUMS.txt"))) {
        Stop-Here "missing $Raw. Run first: python data\scripts\download_bigideas.py"
    }
    $dest = "dbfs:/Volumes/$Catalog/gummi_data/raw_bigideas/bigideas_1.1.3"
    if (-not (Invoke-DbLive fs cp -r $Raw $dest --overwrite)) { Stop-Here "upload failed." }
    Write-Host "uploaded. Folder 001 in the volume now holds:" -ForegroundColor Green
    Invoke-Db fs ls "$dest/001" | Out-Null
}

if (-not $SkipJob) {
    Step "5. Deploy the gummi-data bundle and run gummi_data_load_train (5 to 10 minutes)"
    Push-Location $DataDir
    try {
        $var = "--var=catalog=$Catalog"
        if (-not (Invoke-Db bundle validate $var)) { Stop-Here "bundle validate failed." }
        if (-not (Invoke-Db bundle deploy $var)) { Stop-Here "bundle deploy failed." }
        if (-not (Invoke-DbLive bundle run gummi_data_load_train $var)) { Stop-Here "the job gummi_data_load_train failed." }
        Write-Host "gummi_data_load_train finished" -ForegroundColor Green
        if ($Spike) {
            Step "6. Streaming spike: sample events -> landing -> gummi_stream (triggered) -> checks"
            if (-not (Invoke-DbLive bundle run gummi_stream_spike $var)) { Stop-Here "the job gummi_stream_spike failed." }
            Write-Host "gummi_stream_spike finished. Open the run's 'check' task output for counts and lag." -ForegroundColor Green
        }
    }
    finally { Pop-Location }
}

Write-Host ""
Write-Host "DONE. Paste this whole window to the Data agent." -ForegroundColor Green
