$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-Banner {
    Write-Host @'
+-------------------------------------------------------+
| $$\      $$\                     $$\                  |
| $$$\    $$$ |                    $$ |                 |
| $$$$\  $$$$ | $$$$$$\   $$$$$$\  $$ |  $$\  $$$$$$\   |
| $$\$$\$$ $$ |$$  __$$\ $$  __$$\ $$ | $$  |$$  __$$\  |
| $$ \$$$  $$ |$$$$$$$$ |$$$$$$$$ |$$$$$$  / $$ /  $$ | |
| $$ |\$  /$$ |$$   ____|$$   ____|$$  _$$<  $$ |  $$ | |
| $$ | \_/ $$ |\$$$$$$$\ \$$$$$$$\ $$ | \$$\ \$$$$$$  | |
| \__|     \__| \_______| \_______|\__|  \__| \______/  |
|                                                       |
|                  @MeekoLab/dotfiles                   |
+-------------------------------------------------------+
'@ -ForegroundColor Magenta
}

function Get-WinGetPath {
    # Try to find winget in PATH
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Try common locations
    $candidates = @(
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Install-WinGet {
    Write-Host "Installing winget (App Installer) from GitHub releases..." -ForegroundColor Cyan
    $api = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $release = Invoke-RestMethod -Uri $api -UseBasicParsing
    $bundle = ($release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1).browser_download_url
    if (-not $bundle) { throw 'Could not locate winget .msixbundle in latest release' }

    $tmpBundle = Join-Path $env:TEMP 'winget-latest.msixbundle'
    Invoke-WebRequest -Uri $bundle -OutFile $tmpBundle -UseBasicParsing

    # Try to install optional dependency packages if present (best-effort)
    $depsZip = ($release.assets | Where-Object { $_.name -match 'Dependencies' } | Select-Object -First 1).browser_download_url
    if ($depsZip) {
        try {
            $tmpZip = Join-Path $env:TEMP 'winget-deps.zip'
            $depsDir = Join-Path $env:TEMP 'winget-deps'
            Invoke-WebRequest -Uri $depsZip -OutFile $tmpZip -UseBasicParsing
            Expand-Archive -Path $tmpZip -DestinationPath $depsDir -Force
            Get-ChildItem $depsDir -Recurse -Include *.appx,*.msix | ForEach-Object {
                try { Add-AppxPackage -Path $_.FullName -ErrorAction SilentlyContinue } catch {}
            }
            Remove-Item $tmpZip,$depsDir -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }

    Add-AppxPackage -Path $tmpBundle -ForceApplicationShutdown
    Remove-Item $tmpBundle -Force -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 3
    return (Get-WinGetPath)
}

function Install-WithWinget {
    param(
        [Parameter(Mandatory)] [string]$WingetPath,
        [Parameter(Mandatory)] [string]$Id,
        [string]$Name
    )

    $n = if ($Name) { $Name } else { $Id }
    Write-Host "Installing $n via winget..." -ForegroundColor Cyan
    $args = @(
        'install','--id', $Id,
        '--exact','--silent',
        '--accept-package-agreements','--accept-source-agreements',
        '--disable-interactivity'
    )
    $p = Start-Process -FilePath $WingetPath -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Write-Host "$n install returned exit code $($p.ExitCode)" -ForegroundColor Yellow }
}

# Main
Write-Banner

$winget = Get-WinGetPath
if (-not $winget) { $winget = Install-WinGet }
if (-not $winget) {
    Write-Host "winget is not available. Please install 'App Installer' from Microsoft Store and re-run." -ForegroundColor Red
    exit 1
}

# Install required tools (order: chezmoi, curl, git)
Install-WithWinget -WingetPath $winget -Id 'twpayne.chezmoi' -Name 'chezmoi'
Install-WithWinget -WingetPath $winget -Id 'cURL.cURL' -Name 'curl'
Install-WithWinget -WingetPath $winget -Id 'Git.Git' -Name 'git'

# Quick verification
Write-Host ""; Write-Host "Verification:" -ForegroundColor Green
try { & git --version 2>$null | Select-Object -First 1 | ForEach-Object { Write-Host "git: $_" } } catch { Write-Host "git: not available" -ForegroundColor Yellow }
try { & curl.exe --version 2>$null | Select-Object -First 1 | ForEach-Object { Write-Host "curl: $_" } } catch { Write-Host "curl: not available" -ForegroundColor Yellow }
try { & chezmoi --version 2>$null | Select-Object -First 1 | ForEach-Object { Write-Host "chezmoi: $_" } } catch { Write-Host "chezmoi: not available" -ForegroundColor Yellow }

Write-Host ""; Write-Host "Done." -ForegroundColor Green
