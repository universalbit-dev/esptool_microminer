# 🚀 setup_flash_env.sh — Full documentation

A friendly, complete guide to the repository-local environment setup and optional flashing helper script.

This script automates creating a Python virtual environment, installing esptool and dependencies, configuring access to serial devices, and (optionally) flashing an ESP32 device with the project firmware.

> 📌 Note: The script is intended to be run from the repository root (the same directory as the firmware binaries).

---

## 📚 Table of contents

- Overview
- Quick start (recommended: sudo one-time setup)
- Features
- Safety & prerequisites
- Installation location & naming
- Usage (consistent sudo guidance)
- Command-line options
- Environment & editable variables
- What the script does (step-by-step)
- Flashing sequence details
- Failure modes & troubleshooting
- Examples
- Security & best practices
- Credits / License

---

## 🔎 Overview

This bash script:

- ✅ Creates (or re-uses) a repository-local Python virtual environment at `.venv`.
- ✅ Installs Python packages required to flash ESP32 firmware: `esptool`, `intelhex`, `pyserial`, `cryptography`.
- ⚙️ Optionally installs minimal system packages via `apt` (if `sudo` is available).
- 👤 Optionally adds the current user to the `dialout` group so the user can access USB serial devices without sudo.
- 🔁 Optionally performs a deterministic, explicit flashing sequence using the venv Python interpreter via:
  - `python -m esptool` (preferred), or
  - a local `esptool.py` script if present in the repo.
- 🧭 Always invokes the venv python explicitly — it does not rely on the caller "sourcing" the venv.

The script is conservative about destructive actions: flashing requires user confirmation unless run with `--yes-flash`.

---

## ⚡ Quick start

If you prefer the convenient "one password" flow — run the script under sudo to allow it to install system packages and add your user to the dialout group. This is the recommended path if you cannot access the created venv without sudo.

From the repository root:
```
chmod +x setup_flash_env.sh
```
**Run the script**
```   
sudo ./setup_flash_env.sh
```
What this does:
- Installs system prerequisites via apt (if available).
- Creates or reuses a repo-local virtualenv at `.venv`.
- Installs required Python packages into the venv.
- Attempts to add your user to the `dialout` group (may require logout/login to take full effect).

Important:
- Running the initial setup with sudo is acceptable and convenient if you need elevated privileges to install system packages and the venv. The script always calls the venv python directly, so installed packages are used.

---

## ✨ Features

- Local virtualenv to avoid global package changes.
- Optional system-level installs to help new machines get ready quickly.
- Deterministic flashing using the precise venv Python binary.
- Interactive prompts by default (safe), with non-interactive option for automation.
- Auto-detects candidate serial devices when `--port` is not provided.

---

## 🧭 Command-line options

- --repo-dir PATH  
  Path to the repository root. Default: current working directory.

- --no-flash  
  Only perform environment setup; skip flashing.

- --yes-flash  
  Non-interactive flash (skips the "Type 'YES' to continue" confirmation). Requires `--port`.

- --port DEVICE  
  Serial device to use for flashing, e.g. `/dev/ttyUSB0` or `/dev/ttyACM0`. If omitted the script lists candidate devices and prompts.

- --skip-sudo  
  Do not attempt `sudo apt` installs or run `usermod`. Use this if you cannot or do not want to use `sudo`.

- -h, --help  
  Show usage help and exit.

---


## 🧪 Examples:

- One-time setup + interactive flash:
```
chmod +x setup_flash_env.sh
sudo ./setup_flash_env.sh
```
- Setup only (perform installs and venv setup, skip flashing):
```
sudo ./setup_flash_env.sh --no-flash
```
- Non-interactive flash (provide port; runs under sudo if necessary):
```
sudo ./setup_flash_env.sh --yes-flash --port /dev/ttyUSB0
```

- Run with explicit repo path:
```
sudo ./setup_flash_env.sh --repo-dir /home/user/projects/esptool_microminer
```
- Manage system packages and permissions yourself:
```
./setup_flash_env.sh --skip-sudo
```

---

## 🔐 Security & best practices

- Running initial setup with sudo is a practical choice on systems where you lack permissions; it will prompt for your password once. Prefer to avoid doing repeated flashing as root—fix device permissions or use `dialout` group membership where possible.
- Always validate firmware files before flashing.
- Consider pinning Python package versions in a requirements.txt to avoid surprise upgrades.
- Keep the script under version control if you customize offsets or filenames.

---

## 🧾 Credits / License

- Script source: `esptool_microminer` repository (universalbit-dev).  
- This documentation is provided to help local developers set up and flash devices safely and reproducibly.

---
