#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(HelpMessage = "Run in simulation mode without making system changes")]
    [switch]$DryRun,
    
    [Parameter(HelpMessage = "Force reinstallation of packages even if already installed")]
    [switch]$Force,
    
    [Parameter(HelpMessage = "Skip winget installation and use alternative methods")]
    [switch]$SkipWinget
)

# Script metadata
$script:ScriptVersion = "2.0.0"
$script:LogFile = Join-Path $env:TEMP "dotfiles-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Error handling
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

#region Logging Functions
function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to log file
    Add-Content -Path $script:LogFile -Value $logMessage -ErrorAction SilentlyContinue
    
    # Write to console with colors
    switch ($Level) {
        'Info'    { Write-Host $Message -ForegroundColor Cyan }
        'Warning' { Write-Host $Message -ForegroundColor Yellow }
        'Error'   { Write-Host $Message -ForegroundColor Red }
        'Success' { Write-Host $Message -ForegroundColor Green }
    }
}

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
|                     Version 2.0.0                    |
+-------------------------------------------------------+
'@ -ForegroundColor Magenta
}
#endregion

#region System Information
function Get-SystemInfo {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $info = @{
            OS = $os.Caption
            Version = $os.Version
            Architecture = $os.OSArchitecture
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            ExecutionPolicy = Get-ExecutionPolicy
            IsAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        }
        return $info
    }
    catch {
        Write-Log "Failed to get system information: $($_.Exception.Message)" -Level Error
        return $null
    }
}
#endregion

#region WinGet Management
function Test-WinGetAvailable {
    try {
        # Method 1: Check if winget command is available
        $wingetCmd = Get-Command -Name winget -CommandType Application -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            Write-Log "WinGet found via PATH: $($wingetCmd.Source)" -Level Info
            return $wingetCmd.Source
        }
        
        # Method 2: Check common installation paths
        $commonPaths = @(
            "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe",
            "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller*\winget.exe"
        )
        
        foreach ($path in $commonPaths) {
            if ($path -like "*`**") {
                $resolved = Get-ChildItem -Path (Split-Path $path) -Filter (Split-Path $path -Leaf) -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($resolved) {
                    Write-Log "WinGet found at: $($resolved.FullName)" -Level Info
                    return $resolved.FullName
                }
            }
            elseif (Test-Path $path) {
                Write-Log "WinGet found at: $path" -Level Info
                return $path
            }
        }
        
        Write-Log "WinGet not found in any common locations" -Level Warning
        return $null
    }
    catch {
        Write-Log "Error checking for WinGet: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Restore-WinGetAccess {
    Write-Log "Attempting to restore WinGet access..." -Level Info
    
    try {
        # Method 1: Reset App Installer package
        Write-Log "Resetting App Installer package..." -Level Info
        $appPackage = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -AllUsers -ErrorAction SilentlyContinue
        
        if ($appPackage) {
            Reset-AppxPackage -Package $appPackage.PackageFullName -ErrorAction SilentlyContinue
            Write-Log "App Installer package reset completed" -Level Info
        }
        
        # Method 2: Ensure WindowsApps is in user PATH
        $windowsAppsPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps"
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        
        if ($userPath -notlike "*$windowsAppsPath*") {
            Write-Log "Adding WindowsApps to user PATH..." -Level Info
            $newPath = "$userPath;$windowsAppsPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            Write-Log "WindowsApps added to user PATH. Restart terminal to take effect." -Level Warning
        }
        
        # Method 3: Try alternative WinGet sources
        $githubReleaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $storeUrl = "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
        
        Write-Log "Alternative installation options:" -Level Info
        Write-Log "1. Download from GitHub: https://github.com/microsoft/winget-cli/releases/latest" -Level Info
        Write-Log "2. Install from Microsoft Store: $storeUrl" -Level Info
        Write-Log "3. Use PowerShell commands to reinstall:" -Level Info
        Write-Log "   Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe" -Level Info
        
        return Test-WinGetAvailable
    }
    catch {
        Write-Log "Error during WinGet restoration: $($_.Exception.Message)" -Level Error
        return $null
    }
}

function Install-WinGet {
    if ($DryRun) {
        Write-Log "[DryRun] Would install WinGet from GitHub releases" -Level Info
        return $null
    }
    
    try {
        Write-Log "Installing WinGet from GitHub releases..." -Level Info
        
        # Get latest release info
        $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $downloadUrl = ($release.assets | Where-Object { $_.name -like "*.msixbundle" }).browser_download_url
        
        if (-not $downloadUrl) {
            throw "Could not find WinGet download URL"
        }
        
        $tempPath = Join-Path $env:TEMP "winget-latest.msixbundle"
        Write-Log "Downloading WinGet from: $downloadUrl" -Level Info
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing
        
        # Install dependencies first
        $depsUrl = ($release.assets | Where-Object { $_.name -like "*Dependencies*" }).browser_download_url
        if ($depsUrl) {
            $depsPath = Join-Path $env:TEMP "winget-deps.zip"
            Invoke-WebRequest -Uri $depsUrl -OutFile $depsPath -UseBasicParsing
            
            # Extract and install dependencies
            $extractPath = Join-Path $env:TEMP "winget-deps"
            Expand-Archive -Path $depsPath -DestinationPath $extractPath -Force
            
            Get-ChildItem -Path $extractPath -Filter "*.appx" -Recurse | ForEach-Object {
                try {
                    Add-AppxPackage -Path $_.FullName -ErrorAction SilentlyContinue
                    Write-Log "Installed dependency: $($_.Name)" -Level Info
                }
                catch {
                    Write-Log "Failed to install dependency $($_.Name): $($_.Exception.Message)" -Level Warning
                }
            }
            
            Remove-Item $depsPath, $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-Log "Installing WinGet package..." -Level Info
        Add-AppxPackage -Path $tempPath -ForceApplicationShutdown
        
        Remove-Item $tempPath -ErrorAction SilentlyContinue
        
        # Wait and verify installation
        Start-Sleep -Seconds 5
        $wingetPath = Test-WinGetAvailable
        
        if ($wingetPath) {
            Write-Log "WinGet successfully installed" -Level Success
            return $wingetPath
        }
        else {
            # Try restoration methods
            return Restore-WinGetAccess
        }
    }
    catch {
        Write-Log "Failed to install WinGet: $($_.Exception.Message)" -Level Error
        return Restore-WinGetAccess
    }
}

function Get-WinGetPath {
    $wingetPath = Test-WinGetAvailable
    
    if (-not $wingetPath -and -not $SkipWinget) {
        Write-Log "WinGet not found. Attempting installation and restoration..." -Level Warning
        $wingetPath = Install-WinGet
    }
    
    return $wingetPath
}
#endregion

#region Package Management
function Test-PackageInstalled {
    param(
        [string]$WinGetPath,
        [string]$PackageId
    )
    
    if (-not $WinGetPath -or -not (Test-Path $WinGetPath)) {
        return $false
    }
    
    try {
        $output = & $WinGetPath list --id $PackageId --exact --accept-source-agreements 2>&1
        return $LASTEXITCODE -eq 0 -and ($output -join ' ') -match [regex]::Escape($PackageId)
    }
    catch {
        Write-Log "Error checking if package $PackageId is installed: $($_.Exception.Message)" -Level Warning
        return $false
    }
}

function Install-Package {
    param(
        [string]$WinGetPath,
        [hashtable]$Package
    )
    
    if (-not $WinGetPath) {
        Write-Log "Cannot install $($Package.name) - WinGet not available" -Level Error
        return $false
    }
    
    if ((Test-PackageInstalled -WinGetPath $WinGetPath -PackageId $Package.id) -and -not $Force) {
        Write-Log "$($Package.name) is already installed (use -Force to reinstall)" -Level Info
        return $true
    }
    
    if ($DryRun) {
        Write-Log "[DryRun] Would install: $($Package.id)" -Level Info
        return $true
    }
    
    try {
        Write-Log "Installing $($Package.name)..." -Level Info
        
        $arguments = @(
            'install',
            '--id', $Package.id,
            '--exact',
            '--silent',
            '--accept-package-agreements',
            '--accept-source-agreements',
            '--disable-interactivity'
        )
        
        $process = Start-Process -FilePath $WinGetPath -ArgumentList $arguments -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Log "$($Package.name) installed successfully" -Level Success
            return $true
        }
        else {
            Write-Log "$($Package.name) installation failed with exit code: $($process.ExitCode)" -Level Error
            return $false
        }
    }
    catch {
        Write-Log "Error installing $($Package.name): $($_.Exception.Message)" -Level Error
        return $false
    }
}

function Test-CommandAvailable {
    param([string]$CommandName)
    
    try {
        $command = Get-Command -Name $CommandName -CommandType Application -ErrorAction SilentlyContinue
        return $null -ne $command
    }
    catch {
        return $false
    }
}
#endregion

#region Alternative Installation Methods
function Install-GitAlternative {
    if ($DryRun) {
        Write-Log "[DryRun] Would install Git from git-scm.com" -Level Info
        return
    }
    
    try {
        Write-Log "Installing Git from git-scm.com..." -Level Info
        $gitUrl = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.42.0.2-64-bit.exe"
        $tempPath = Join-Path $env:TEMP "git-installer.exe"
        
        Invoke-WebRequest -Uri $gitUrl -OutFile $tempPath -UseBasicParsing
        Start-Process -FilePath $tempPath -ArgumentList "/SILENT" -Wait
        Remove-Item $tempPath -ErrorAction SilentlyContinue
        
        Write-Log "Git installed via alternative method" -Level Success
    }
    catch {
        Write-Log "Failed to install Git via alternative method: $($_.Exception.Message)" -Level Error
    }
}

function Install-CurlAlternative {
    if ($DryRun) {
        Write-Log "[DryRun] Would install cURL from curl.se" -Level Info
        return
    }
    
    try {
        Write-Log "Installing cURL from curl.se..." -Level Info
        # Modern Windows 10/11 should have curl built-in
        if (Test-Path "$env:SystemRoot\System32\curl.exe") {
            Write-Log "System cURL found at $env:SystemRoot\System32\curl.exe" -Level Success
            return
        }
        
        Write-Log "Consider using built-in Windows cURL or download from https://curl.se/windows/" -Level Info
    }
    catch {
        Write-Log "Failed to check for alternative cURL: $($_.Exception.Message)" -Level Error
    }
}

function Install-ChezmoiAlternative {
    if ($DryRun) {
        Write-Log "[DryRun] Would install chezmoi from GitHub releases" -Level Info
        return
    }
    
    try {
        Write-Log "Installing chezmoi from GitHub releases..." -Level Info
        $chezmoiUrl = "https://github.com/twpayne/chezmoi/releases/latest/download/chezmoi_windows_amd64.zip"
        $tempPath = Join-Path $env:TEMP "chezmoi.zip"
        $extractPath = Join-Path $env:TEMP "chezmoi"
        $installPath = "$env:LOCALAPPDATA\Programs\chezmoi"
        
        New-Item -ItemType Directory -Path $installPath -Force | Out-Null
        
        Invoke-WebRequest -Uri $chezmoiUrl -OutFile $tempPath -UseBasicParsing
        Expand-Archive -Path $tempPath -DestinationPath $extractPath -Force
        
        Copy-Item -Path "$extractPath\chezmoi.exe" -Destination "$installPath\chezmoi.exe" -Force
        
        # Add to user PATH if not present
        $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($userPath -notlike "*$installPath*") {
            $newPath = "$userPath;$installPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
            Write-Log "Added chezmoi to user PATH. Restart terminal to take effect." -Level Warning
        }
        
        Remove-Item $tempPath, $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log "Chezmoi installed to $installPath" -Level Success
    }
    catch {
        Write-Log "Failed to install chezmoi via alternative method: $($_.Exception.Message)" -Level Error
    }
}
#endregion

#region Main Installation Logic
function Install-RequiredPackages {
    param([string]$WinGetPath)
    
    $packages = @(
        @{ id = "Git.Git"; name = "Git"; alternative = { Install-GitAlternative } },
        @{ id = "cURL.cURL"; name = "cURL"; alternative = { Install-CurlAlternative } },
        @{ id = "twpayne.chezmoi"; name = "Chezmoi"; alternative = { Install-ChezmoiAlternative } }
    )
    
    $results = @{}
    
    foreach ($package in $packages) {
        if ($WinGetPath) {
            $success = Install-Package -WinGetPath $WinGetPath -Package $package
            $results[$package.name] = $success
            
            # If WinGet failed and we have alternative method, try it
            if (-not $success -and $package.alternative) {
                Write-Log "Trying alternative installation method for $($package.name)..." -Level Warning
                & $package.alternative
            }
        }
        elseif ($package.alternative) {
            Write-Log "Using alternative installation method for $($package.name)..." -Level Info
            & $package.alternative
            $results[$package.name] = $true
        }
        else {
            Write-Log "No installation method available for $($package.name)" -Level Error
            $results[$package.name] = $false
        }
    }
    
    return $results
}

function Test-InstallationResults {
    $commands = @(
        @{ name = "Git"; command = "git" },
        @{ name = "cURL"; command = "curl" },
        @{ name = "Chezmoi"; command = "chezmoi" }
    )
    
    Write-Log "Verifying installations..." -Level Info
    
    foreach ($cmd in $commands) {
        if (Test-CommandAvailable -CommandName $cmd.command) {
            try {
                $version = & $cmd.command --version 2>&1 | Select-Object -First 1
                Write-Log "$($cmd.name) is available - $version" -Level Success
            }
            catch {
                Write-Log "$($cmd.name) is available but version check failed" -Level Warning
            }
        }
        else {
            Write-Log "$($cmd.name) is NOT available in PATH" -Level Warning
            Write-Log "You may need to restart your terminal or add the program to your PATH manually" -Level Info
        }
    }
}
#endregion

#region Main Function
function Invoke-DotfilesSetup {
    try {
        Write-Banner
        
        Write-Log "Starting dotfiles setup - Version $script:ScriptVersion" -Level Info
        Write-Log "Log file: $script:LogFile" -Level Info
        
        if ($DryRun) {
            Write-Log "Running in DRY RUN mode - no changes will be made" -Level Warning
        }
        
        # System checks
        $systemInfo = Get-SystemInfo
        if ($systemInfo) {
            Write-Log "System: $($systemInfo.OS) $($systemInfo.Architecture)" -Level Info
            Write-Log "PowerShell: $($systemInfo.PowerShellVersion)" -Level Info
            Write-Log "Execution Policy: $($systemInfo.ExecutionPolicy)" -Level Info
            Write-Log "Running as Administrator: $($systemInfo.IsAdmin)" -Level Info
        }
        
        # Get WinGet
        if (-not $SkipWinget) {
            $wingetPath = Get-WinGetPath
            
            if ($wingetPath) {
                Write-Log "WinGet is available at: $wingetPath" -Level Success
                
                # Test WinGet functionality
                try {
                    $testOutput = & $wingetPath --version 2>&1
                    Write-Log "WinGet version: $testOutput" -Level Info
                }
                catch {
                    Write-Log "WinGet found but not functional: $($_.Exception.Message)" -Level Warning
                    $wingetPath = $null
                }
            }
            else {
                Write-Log "WinGet is not available after restoration attempts" -Level Error
                Write-Log "Will proceed with alternative installation methods" -Level Warning
            }
        }
        else {
            Write-Log "WinGet installation skipped as requested" -Level Warning
            $wingetPath = $null
        }
        
        # Install packages
        $results = Install-RequiredPackages -WinGetPath $wingetPath
        
        # Display results
        Write-Log "Installation Summary:" -Level Info
        foreach ($result in $results.GetEnumerator()) {
            $status = if ($result.Value) { "SUCCESS" } else { "FAILED" }
            $level = if ($result.Value) { "Success" } else { "Error" }
            Write-Log "  $($result.Key): $status" -Level $level
        }
        
        # Verify installations
        Test-InstallationResults
        
        # Final instructions
        Write-Log "" -Level Info
        Write-Log "Setup completed!" -Level Success
        Write-Log "Next steps:" -Level Info
        Write-Log "1. Restart your terminal to ensure all PATH changes take effect" -Level Info
        Write-Log "2. Initialize your dotfiles with: chezmoi init --apply https://github.com/MeekoLab/dotfiles" -Level Info
        Write-Log "3. Check the log file for detailed information: $script:LogFile" -Level Info
        
        if (-not $wingetPath) {
            Write-Log "" -Level Warning
            Write-Log "WinGet Recovery Instructions:" -Level Warning
            Write-Log "1. Open Microsoft Store and install 'App Installer'" -Level Info
            Write-Log "2. Or download from: https://github.com/microsoft/winget-cli/releases/latest" -Level Info
            Write-Log "3. Ensure %LOCALAPPDATA%\\Microsoft\\WindowsApps is in your PATH" -Level Info
        }
        
    }
    catch {
        Write-Log "Unexpected error during setup: $($_.Exception.Message)" -Level Error
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
        throw
    }
}
#endregion

# Script entry point
try {
    Invoke-DotfilesSetup
}
catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" -Level Error
    exit 1
}

Write-Log "Script execution completed successfully" -Level Success
exit 0
