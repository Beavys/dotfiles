# Dotfiles

This repository contains cross-platform dotfiles and setup scripts for quickly configuring development environments on **macOS**, **Linux** and **Windows 11**

## ⚡ Quick Setup for Windows 11

> 💡 If you want to install Windows 11 without a Microsoft Account (local account), [read the documentation](./docs/install-windows-without-ms-account.md)

To run the setup script directly from Git (make sure to run from **PowerShell as Administrator**):

```powershell
irm https://raw.githubusercontent.com/MeekoLab/dotfiles/main/install/windows.ps1 | iex
```

## 🚀 Initialize chezmoi after setup

After running the setup script, initialize your dotfiles with chezmoi:

```powershell
chezmoi init --apply https://github.com/MeekoLab/dotfiles
```

This will clone and apply your dotfiles from the MeekoLab repository automatically.
