# OpenClaw Uninstaller

Complete uninstall scripts for [OpenClaw (龙虾)](https://docs.openclaw.ai) and its predecessor clawdbot.  
Supports **macOS**, **Linux**, and **Windows (PowerShell / WSL2)**.

Each script will:
- Stop and remove the daemon (LaunchAgent / systemd / Scheduled Task)
- Kill any remaining gateway processes
- Uninstall npm global packages (`openclaw` / `clawdbot` / `moltbot`)
- Auto-backup config directories before deleting (default), or purge without backup (`--purge`)
- Clean up crontab / PATH entries
- Print a colored verification summary at the end

---

## 🍎 macOS

### One-liner (recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-macos.sh)
```

### Download and run

```bash
curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-macos.sh -o uninstall-macos.sh
bash uninstall-macos.sh
```

### Keep config (skip deleting `~/.openclaw` / `~/.clawdbot`)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-macos.sh) --keep-config
```

### Purge (delete immediately, no backup)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-macos.sh) --purge
```

---

## 🐧 Linux

### One-liner (recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-linux.sh)
```

### Download and run

```bash
curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-linux.sh -o uninstall-linux.sh
bash uninstall-linux.sh
```

### Keep config

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-linux.sh) --keep-config
```

### Purge (delete immediately, no backup)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-linux.sh) --purge
```

---

## 🪟 Windows (WSL2)

Run inside the WSL2 shell — use the Linux script:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-linux.sh)
```

Purge mode:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-linux.sh) --purge
```

---

## 🪟 Windows (PowerShell, native)

### Download and run

```powershell
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-windows.ps1" -OutFile "uninstall-windows.ps1"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\uninstall-windows.ps1
```

### One-liner

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass; Invoke-Expression (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/memoryza/uninstall-openclaw/main/uninstall-windows.ps1").Content
```

### Keep config

```powershell
.\uninstall-windows.ps1 -KeepConfig
```

### Purge (delete immediately, no backup)

```powershell
.\uninstall-windows.ps1 -Purge
```

---

## Options

| Option | macOS / Linux | Windows | Description |
|--------|--------------|---------|-------------|
| Default | _(no flag)_ | _(no flag)_ | Auto-backup config dirs, then delete |
| Keep config | `--keep-config` | `-KeepConfig` | Skip deleting config dirs entirely |
| Purge | `--purge` | `-Purge` | Delete config dirs immediately, **no backup** |

> `--keep-config` and `--purge` are mutually exclusive.

---

## What gets removed

| Item | macOS | Linux | Windows |
|------|-------|-------|---------|
| LaunchAgent / systemd / Scheduled Task | ✅ | ✅ | ✅ |
| Gateway process | ✅ | ✅ | ✅ |
| npm packages (`openclaw`, `clawdbot`, `moltbot`) | ✅ | ✅ | ✅ |
| `~/.openclaw` config dir | ✅ (backed up) | ✅ (backed up) | ✅ (backed up) |
| `~/.clawdbot` config dir | ✅ (backed up) | ✅ (backed up) | ✅ (backed up) |
| crontab entries | ✅ | ✅ | — |
| user PATH entries | — | — | ✅ |

---

## Reinstalling

After full removal, follow the [OpenClaw installation guide](https://docs.openclaw.ai/start/getting-started) to start fresh.
