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

function Ensure-Winget {
    Write-Info "Checking for winget..."
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Info "Checking if App Installer is already installed..."
        $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
        if ($null -eq $appInstaller) {
            Write-WarningMsg "App Installer not found. Attempting to install from Microsoft Store..."
            try {
                $appInstallerUrl = "https://aka.ms/getwinget"
                $installerPath = "$env:TEMP\AppInstaller.appxbundle"
                Write-Info "Downloading App Installer..."
                Invoke-WebRequest -Uri $appInstallerUrl -OutFile $installerPath
                Write-Info "Installing App Installer..."
                Add-AppxPackage -Path $installerPath
                Remove-Item $installerPath -ErrorAction SilentlyContinue
                Write-Success "App Installer installed. Attempting to reload winget..."
            } catch {
                Write-ErrorMsg "Automatic installation failed. Please install App Installer manually from Microsoft Store."
                exit 1
            }
        } else {
            Write-Info "App Installer is already installed."
        }

        $wingetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
        if ($env:PATH -notlike "*$wingetPath*") {
            $env:PATH += ";$wingetPath"
            Write-Info "PATH updated with WindowsApps directory."
        }

        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-ErrorMsg "winget still not found. Please restart your terminal or log out and log in again to update PATH."
            exit 1
        }
    }
}

function Install-PackageList($packages) {
    $allSuccess = $true
    foreach ($pkg in $packages) {
        Write-Info "Installing $pkg.id..."
        try {
            winget install --id $pkg.id --silent --accept-package-agreements --accept-source-agreements
            Write-Success "$($pkg.name) installed."
        } catch {
            Write-ErrorMsg "Error installing $($pkg.name): $_"
            $allSuccess = $false
        }
    }
    return $allSuccess
}

# List of required packages with command names
$basePackages = @(
    @{ id = "Git.Git"; name = "git" },
    @{ id = "curl.curl"; name = "curl" },
    @{ id = "twpayne.chezmoi"; name = "chezmoi" }
)

Write-Info "Checking for required dependencies: winget, git, curl, chezmoi..."
Ensure-Winget

Install-PackageList $basePackages

# Post-installation checks
Write-Info "Checking installations..."
foreach ($pkg in $basePackages) {
    if (Get-Command $pkg.name -ErrorAction SilentlyContinue) {
        Write-Success "$($pkg.name) is available."
    } else {
        Write-ErrorMsg "$($pkg.name) is NOT available. Please check installation."
    }
}

Write-Success "Minimal setup complete! You can now use chezmoi to initialize and apply your dotfiles."
Write-Info "Example: chezmoi init --apply https://github.com/MeekoLab/dotfiles"