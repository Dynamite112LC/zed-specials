# Notes which leaflets each shop lists today and pushes that list to the
# "data" branch, where the scheduled GitHub job reads it.
#
# Why: Shoprite's main site refuses GitHub's servers but answers an
# ordinary home connection. This script runs on such a computer once a day
# (see README, "Daily run on your own computer"), asks each shop's specials
# page once, and takes a few seconds. Reading the leaflets and publishing
# the feed stay with the GitHub job.
#
#   pwsh -File tool/update-leaflet-lists.ps1
#
# The data/ folder is managed by this script: each run resets it to what is
# on GitHub before writing, so do not keep other work in it.

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$data = Join-Path $project 'data'
$lists = Join-Path $data 'last-scrape.json'
$logDir = Join-Path $project '.cache'
$log = Join-Path $logDir 'leaflet-lists.log'

New-Item -ItemType Directory -Force $logDir | Out-Null

function Write-Log([string]$message) {
  $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $message"
  Add-Content -Path $log -Value $line
  Write-Host $line
}

# Runs a program, logs what it printed, and stops the script if it failed.
function Invoke-Step([string]$what, [scriptblock]$command) {
  $output = & $command 2>&1 | ForEach-Object { "$_" }
  if ($LASTEXITCODE -ne 0) {
    foreach ($l in $output) { Write-Log "    $l" }
    throw "$what failed (exit code $LASTEXITCODE)"
  }
  return $output
}

function Get-LeafletIds {
  if (-not (Test-Path $lists)) { return @() }
  $json = Get-Content $lists -Raw | ConvertFrom-Json
  return @($json.PSObject.Properties | ForEach-Object { $_.Value.catalogues.id } | Where-Object { $_ })
}

try {
  Set-Location $project
  # Native programs report failure through their exit code, checked above.
  $ErrorActionPreference = 'Continue'

  if (-not (Test-Path (Join-Path $data '.git'))) {
    Write-Log 'Setting up data/ as a checkout of the "data" branch'
    Invoke-Step 'git fetch' { git fetch origin data } | Out-Null
    Invoke-Step 'git worktree add' { git worktree add -B data data origin/data } | Out-Null
  }

  $pushed = $false
  $newIds = @()
  foreach ($attempt in 1..3) {
    # Start from what is on GitHub, so this never collides with the commits
    # the scheduled job makes there.
    Invoke-Step 'git fetch' { git -C $data fetch origin data } | Out-Null
    Invoke-Step 'git reset' { git -C $data reset --hard FETCH_HEAD } | Out-Null
    $before = Get-LeafletIds

    $summary = Invoke-Step 'The feed builder' { dart run tool/update_feed.dart --lists-only }
    foreach ($l in $summary) {
      if ($l -match 'leaflets listed|could not be reached|failed') { Write-Log "  $l" }
    }
    $newIds = @(Get-LeafletIds | Where-Object { $before -notcontains $_ })

    Invoke-Step 'git add' { git -C $data add last-scrape.json } | Out-Null
    git -C $data diff --cached --quiet
    if ($LASTEXITCODE -eq 0) {
      Write-Log 'Lists unchanged since the last run today; nothing to push'
      $pushed = $true
      break
    }
    Invoke-Step 'git commit' {
      git -C $data commit -m "Leaflet lists on $(Get-Date -Format 'yyyy-MM-dd'), from a home connection"
    } | Out-Null

    git -C $data push origin HEAD:data 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Log 'Pushed the lists to the data branch'
      $pushed = $true
      break
    }
    Write-Log "Push was refused (attempt $attempt): GitHub's copy changed meanwhile. Trying again."
    Start-Sleep -Seconds 5
  }
  if (-not $pushed) { throw 'Could not push the lists after 3 attempts' }

  if ($newIds.Count -gt 0) {
    Write-Log "New leaflets: $($newIds -join ', ')"
    # Have the GitHub job read them now instead of at its next scheduled run.
    if (Get-Command gh -ErrorAction SilentlyContinue) {
      gh workflow run update-feed.yml --ref main 2>&1 | Out-Null
      if ($LASTEXITCODE -eq 0) {
        Write-Log 'Asked the GitHub job to rebuild the feed'
      } else {
        Write-Log 'Could not start the GitHub job; it will pick the leaflets up at its next scheduled run'
      }
    }
  }
  exit 0
} catch {
  Write-Log "FAILED: $($_.Exception.Message)"
  exit 1
}
