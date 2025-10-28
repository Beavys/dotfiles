# This script will be executed automatically by chezmoi on Windows after applying dotfiles
# Installs essential programs via winget

function Write-Success($msg) { Write-Host $msg -ForegroundColor Green }
function Write-WarningMsg($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-ErrorMsg($msg) { Write-Host $msg -ForegroundColor Red }
function Write-Info($msg) { Write-Host $msg -ForegroundColor Cyan }

Write-Info "Installing essential Windows programs via winget..."

$packages = @(
    "Git.Git",                     # Version control system
    "curl.curl",                   # Network utility
    "Microsoft.VisualStudioCode",  # Code editor
    "Microsoft.WindowsTerminal",   # Terminal
    "Google.Chrome",               # Web browser
    "qBittorrent.qBittorrent",     # Torrent client
    "Rem0o.FanControl",            # Fan control utility
    "FilesCommunity.Files ",       # Modern file explorer (Files app)
    "Logitech.GHUB",               # Logitech device manager
    "Valve.Steam",                 # Game platform
    "9NKSQGP7F2NH",                # WhatsApp desktop
    "Telegram.TelegramDesktop"     # Telegram desktop
    "EpicGames.EpicGamesLauncher", # Epic Games Launcher
    "Meta.Oculus",                 # Meta Oculus software
    "Discord.Discord",             # Discord
    "DeepCool.DeepCool",           # DeepCool
    "Notion.Notion",               # Notion
    "VirtualDesktop.Streamer",     # Virtual Desktop Streamer
)

foreach ($pkg in $packages) {
    Write-Info "Installing $pkg..."
    try {
        winget install --id $pkg --silent --accept-package-agreements --accept-source-agreements
        Write-Success "$pkg installed."
    } catch {
        Write-ErrorMsg "Error installing $pkg: $_"
    }
}

Write-Success "All essential programs installed!"
