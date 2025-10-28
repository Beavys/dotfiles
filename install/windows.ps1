param(
    [switch]$DryRun
)

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
|                                                       |
+-------------------------------------------------------+
'@

function Write-Success($msg) { Write-Host $msg -ForegroundColor Green }
function Write-WarningMsg($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-ErrorMsg($msg) { Write-Host $msg -ForegroundColor Red }
function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }

# Ensure errors from PowerShell cmdlets stop execution within the current function scopes
$ErrorActionPreference = 'Stop'

function Get-WingetPath {
    # Try to resolve winget from PATH first
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Path) { return $cmd.Path }
    # Fallback to default App Installer location without modifying PATH
    $candidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $candidate) { return $candidate }
    return $null
}

function Ensure-Winget {
    Write-Info "Checking for winget..."
    $wingetPath = Get-WingetPath
    if ($null -ne $wingetPath) { return $wingetPath }

    Write-Info "Checking if App Installer is already installed..."
    $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    if ($null -eq $appInstaller) {
        if ($DryRun) {
            Write-Info "[DryRun] Would download and install App Installer from https://aka.ms/getwinget"
            return $null
        }
        Write-WarningMsg "App Installer not found. Attempting to install from Microsoft Store package..."
        try {
            $appInstallerUrl = "https://aka.ms/getwinget"
            $installerPath = Join-Path $env:TEMP 'AppInstaller.appxbundle'
            Write-Info "Downloading App Installer..."
            Invoke-WebRequest -Uri $appInstallerUrl -OutFile $installerPath
            Write-Info "Installing App Installer..."
            Add-AppxPackage -Path $installerPath
            Remove-Item $installerPath -ErrorAction SilentlyContinue
            Write-Success "App Installer installed."
        } catch {
            Write-ErrorMsg "Automatic installation failed: $($_.Exception.Message). Please install App Installer from Microsoft Store (Microsoft.DesktopAppInstaller)."
            return $null
        }
    } else {
        Write-Info "App Installer is already installed."
    }

    # Re-resolve winget without touching PATH
    $wingetPath = Get-WingetPath
    if ($null -eq $wingetPath) {
        Write-WarningMsg "winget not resolved in this session. Restart the terminal. If still missing, ensure '%LOCALAPPDATA%\\Microsoft\\WindowsApps' is in your USER PATH."
        return $null
    }
    return $wingetPath
}

function Test-PackageInstalled($wingetCmd, $id) {
    # Uses 'winget list' to determine if a package with exact Id is installed
    try {
        $tmpFile = [System.IO.Path]::GetTempFileName()
        $args = @('list','--id', $id, '--exact','--accept-source-agreements','--disable-interactivity')
        $p = Start-Process -FilePath $wingetCmd -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $tmpFile
        $output = Get-Content $tmpFile -Raw -ErrorAction SilentlyContinue
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
        if ($p.ExitCode -eq 0 -and $output -match [regex]::Escape($id)) { return $true }
    } catch { }
    return $false
}

function Install-PackageList($packages, $wingetCmd) {
    $allSuccess = $true
    foreach ($pkg in $packages) {
        # If winget is not available, skip loop
        if (-not $wingetCmd) { $allSuccess = $false; break }

        if (Test-PackageInstalled -wingetCmd $wingetCmd -id $pkg.id) {
            Write-Info "Already installed: $($pkg.id). Skipping."
            continue
        }
        if ($DryRun) {
            Write-Info "[DryRun] Would run: `"$wingetCmd install --id $($pkg.id) --exact --accept-package-agreements --accept-source-agreements --disable-interactivity --silent`""
            continue
        }
        Write-Info "Installing $($pkg.id)..."
        $args = @('install','--id',$pkg.id,'--exact','--accept-package-agreements','--accept-source-agreements','--disable-interactivity','--silent')
        try {
            $proc = Start-Process -FilePath $wingetCmd -ArgumentList $args -NoNewWindow -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Success "$($pkg.name) installed."
            } else {
                Write-ErrorMsg "Failed to install $($pkg.name). ExitCode=$($proc.ExitCode)"
                $allSuccess = $false
            }
        } catch {
            Write-ErrorMsg "Error installing $($pkg.name): $($_.Exception.Message)"
            $allSuccess = $false
        }
    }
    return $allSuccess
}

function Resolve-CommandPath($name) {
    # Prefer real applications over aliases
    $cmd = Get-Command -Name $name -CommandType Application -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Path) { return $cmd.Path }
    return $null
}

function Find-WinGetPackageBinary($pkg) {
    try {
        $packagesRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (-not (Test-Path $packagesRoot)) { return $null }
        $prefix = "$($pkg.id)_Microsoft.Winget.Source_"
        $dirs = Get-ChildItem -Path $packagesRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$prefix*" }
        foreach ($d in $dirs) {
            $exe = Join-Path $d.FullName ("{0}.exe" -f $pkg.name)
            if (Test-Path $exe) { return $exe }
            # Some packages put binaries under a nested bin folder
            $exe2 = Join-Path (Join-Path $d.FullName 'bin') ("{0}.exe" -f $pkg.name)
            if (Test-Path $exe2) { return $exe2 }
            # Fallback: search shallowly for the exe
            $found = Get-ChildItem -Path $d.FullName -Filter ("{0}.exe" -f $pkg.name) -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { return $found.FullName }
        }
    } catch {}
    return $null
}

# List of required packages with command names
$basePackages = @(
    @{ id = "Git.Git"; name = "git" },
    @{ id = "curl.curl"; name = "curl" },
    @{ id = "twpayne.chezmoi"; name = "chezmoi" }
)

Write-Info "Checking for required dependencies: winget, git, curl, chezmoi..."
$winget = Ensure-Winget
if ($null -eq $winget) {
    Write-WarningMsg "winget is unavailable in this session. Package installation will be skipped."
} else {
    Install-PackageList $basePackages $winget | Out-Null
}

# Post-installation checks
Write-Info "Checking installations..."
foreach ($pkg in $basePackages) {
    $resolved = Resolve-CommandPath -name $pkg.name
    if ($resolved) {
        Write-Success ("{0} is available at {1}" -f $pkg.name, $resolved)
        continue
    }
    $wingetExePath = Find-WinGetPackageBinary -pkg $pkg
    if ($wingetExePath) {
        Write-WarningMsg ("{0} executable found at {1}, but it's not on PATH. Consider adding its directory to PATH or reopen the terminal." -f $pkg.name, $wingetExePath)
    } else {
        Write-ErrorMsg ("{0} is NOT available. The package may have failed to install or the binary location is unknown." -f $pkg.name)
    }
}

Write-Success "Minimal setup complete! You can now use chezmoi to initialize and apply your dotfiles."
Write-Info "Example: chezmoi init --apply https://github.com/MeekoLab/dotfiles"
Write-Info ("Resolved winget path: " + ($(if ($winget) { $winget } else { '<not resolved>' })))