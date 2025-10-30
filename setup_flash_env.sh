#!/usr/bin/env bash
# setup_python3_env.sh
#
# Automated environment setup + optional flashing for ESP32 BTC MicroMiner project.
# Place this script in the repository root (esptool_microminer) and run:
#   chmod +x setup_python3_env.sh
#   ./setup_python3_env.sh [--repo-dir PATH] [--port /dev/ttyUSB0] [--no-flash] [--yes-flash] [--skip-sudo]
#
# Behaviour:
#  - Creates a repo-local virtualenv at .venv (or re-uses it)
#  - Installs esptool + dependencies into the venv
#  - Adds the current user to dialout (if sudo available)
#  - Optionally runs the flashing sequence using the venv python (deterministic)
#  - Always invokes the venv python explicitly (no reliance on "source" activation)
#
# Notes:
#  - Avoid running the flash step with sudo. Prefer to add your user to the dialout group
#    and run the script as your user. If you must run as root, the script still calls the
#    venv python binary directly so installed packages are used.
#  - Edit the firmware filename variables below if your repo uses different names.
#  - This script is conservative: it prompts before flashing unless --yes-flash is used.
set -euo pipefail

# ---------- Configuration (edit if filenames/paths differ) ----------
REPO_DIR="$(pwd)"
VENV_DIR="$REPO_DIR/.venv"
ESPCMD_SCRIPT="$REPO_DIR/esptool.py"    # local esptool.py (if present)
ESPMODULE="esptool"                     # python -m esptool

BOOTLOADER_BIN="0x1000_bootloader.bin"
PARTITIONS_BIN="0x8000_partitions.bin"
FIRMWARE_BIN="0x10000_firmware.bin"
BOOT_APP_BIN="0xe000_boot_app0.bin"

# ---------- CLI args ----------
DO_FLASH=1
FLASH_YES=0
SKIP_SUDO=0
SERIAL_PORT=""

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  --repo-dir PATH    Path to repo (default: current dir)
  --no-flash         Only setup environment; skip flashing
  --yes-flash        Non-interactive flash (requires --port)
  --port DEVICE      Serial device for flashing (e.g. /dev/ttyUSB0)
  --skip-sudo        Don't use sudo for apt or usermod
  -h, --help         Show this help
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir) REPO_DIR="$2"; shift 2 ;;
    --no-flash) DO_FLASH=0; shift ;;
    --yes-flash) FLASH_YES=1; DO_FLASH=1; shift ;;
    --port) SERIAL_PORT="$2"; shift 2 ;;
    --skip-sudo) SKIP_SUDO=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1"; usage ;;
  esac
done

# Validate repo dir
if [[ ! -d "$REPO_DIR" ]]; then
  echo "Repository directory does not exist: $REPO_DIR"
  exit 1
fi
cd "$REPO_DIR"
echo "Working in repo: $REPO_DIR"

# sudo helper
SUDO_CMD=""
if [[ "${SKIP_SUDO}" -eq 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO_CMD="sudo"
  else
    echo "sudo not found; continuing without sudo. Some system installs may be skipped."
  fi
fi

echo
echo "=== System package install (optional) ==="
if [[ -n "$SUDO_CMD" ]]; then
  echo "Installing minimal system prerequisites (may prompt for password)..."
  $SUDO_CMD apt update -y || true
  $SUDO_CMD apt install -y python3 python3-venv python3-pip build-essential git pkg-config libffi-dev libssl-dev libusb-1.0-0-dev ca-certificates || true
  $SUDO_CMD apt install -y libfuse2 || true
else
  echo "Skipping apt installs (--skip-sudo or sudo not available). Make sure required packages are present."
fi

# Create or reuse venv inside repo
if [[ -d "$VENV_DIR" ]]; then
  echo "Using existing virtualenv at $VENV_DIR"
else
  echo "Creating virtualenv at $VENV_DIR"
  python3 -m venv "$VENV_DIR"
fi

# Path to venv python and pip
VENV_PY="$VENV_DIR/bin/python"
VENV_PIP="$VENV_DIR/bin/pip"

if [[ ! -x "$VENV_PY" ]]; then
  echo "Error: venv python not found at $VENV_PY"
  exit 1
fi

echo "Upgrading pip/setuptools/wheel in venv..."
"$VENV_PY" -m pip install --upgrade pip setuptools wheel >/dev/null

echo "Installing Python packages into venv: esptool, intelhex, pyserial, cryptography"
"$VENV_PIP" install esptool intelhex pyserial cryptography >/dev/null

# Verify cryptography import (informational)
if ! "$VENV_PY" -c "import cryptography" >/dev/null 2>&1; then
  echo
  echo "Warning: cryptography import failed in venv. If pip built from source, install cargo (Rust) or use system package:"
  echo "  sudo apt install cargo"
  echo "or"
  echo "  sudo apt install python3-cryptography"
  echo
fi

# Add user to dialout for serial access (if possible)
if [[ -n "$SUDO_CMD" ]]; then
  echo "Adding current user '$USER' to dialout group for serial access (may require logout/login)"
  $SUDO_CMD usermod -a -G dialout "$USER" || true
else
  echo "Skipping usermod (no sudo). Ensure you can access /dev/ttyUSB* devices."
fi

# Make esptool.py executable if present
if [[ -f "$ESPCMD_SCRIPT" ]]; then
  chmod +x "$ESPCMD_SCRIPT" || true
fi

echo
echo "=== Environment setup complete ==="
echo "Virtualenv located at: $VENV_DIR"
echo "Activate later with: source \"$VENV_DIR/bin/activate\""
echo

if [[ $DO_FLASH -eq 0 ]]; then
  echo "Flashing step skipped (--no-flash)."
  exit 0
fi

# If serial port not specified, list candidates and prompt
if [[ -z "$SERIAL_PORT" ]]; then
  echo "Detecting candidate serial devices:"
  ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true
  read -r -p "Enter serial port to use for flashing (e.g. /dev/ttyUSB0) or press Enter to cancel: " SERIAL_PORT
  if [[ -z "$SERIAL_PORT" ]]; then
    echo "No serial port provided. Aborting flash step."
    exit 0
  fi
fi

# Confirm flashing unless --yes-flash
if [[ $FLASH_YES -ne 1 ]]; then
  echo
  echo "About to flash device $SERIAL_PORT with these files (ensure they exist in repo root):"
  echo "  bootloader: $BOOTLOADER_BIN"
  echo "  partitions: $PARTITIONS_BIN"
  echo "  firmware:   $FIRMWARE_BIN"
  echo "  boot_app:   $BOOT_APP_BIN"
  read -r -p "Type 'YES' to continue: " CONFIRM
  if [[ "$CONFIRM" != "YES" ]]; then
    echo "Flash cancelled."
    exit 0
  fi
fi

# Verify firmware files exist
for f in "$BOOTLOADER_BIN" "$PARTITIONS_BIN" "$FIRMWARE_BIN" "$BOOT_APP_BIN"; do
  if [[ ! -f "$f" ]]; then
    echo "Error: required file not found: $f"
    echo "Files in repo root:"
    ls -1
    exit 1
  fi
done

# Determine whether esptool module is installed in venv
if "$VENV_PY" -c "import importlib, sys
try:
  importlib.import_module('$ESPMODULE')
  sys.exit(0)
except Exception:
  sys.exit(1)
" >/dev/null 2>&1; then
  USE_MODULE=1
else
  USE_MODULE=0
fi

echo
echo "Beginning flashing sequence (using venv python: $VENV_PY)..."
set +e
FLASH_EXIT=0

if [[ $USE_MODULE -eq 1 ]]; then
  echo "Using esptool module installed in venv (python -m esptool)"
  "$VENV_PY" -m esptool --port "$SERIAL_PORT" erase_flash || FLASH_EXIT=$?
  "$VENV_PY" -m esptool --port "$SERIAL_PORT" write_flash 0x1000 "$BOOTLOADER_BIN" || FLASH_EXIT=$?
  "$VENV_PY" -m esptool --port "$SERIAL_PORT" write_flash 0x8000 "$PARTITIONS_BIN" || FLASH_EXIT=$?
  "$VENV_PY" -m esptool --port "$SERIAL_PORT" write_flash 0x10000 "$FIRMWARE_BIN" || FLASH_EXIT=$?
  "$VENV_PY" -m esptool --port "$SERIAL_PORT" write_flash 0xe000 "$BOOT_APP_BIN" || FLASH_EXIT=$?
else
  if [[ -f "$ESPCMD_SCRIPT" ]]; then
    echo "Using local esptool.py script in repo"
    "$VENV_PY" "$ESPCMD_SCRIPT" --port "$SERIAL_PORT" erase_flash || FLASH_EXIT=$?
    "$VENV_PY" "$ESPCMD_SCRIPT" --port "$SERIAL_PORT" write_flash 0x1000 "$BOOTLOADER_BIN" || FLASH_EXIT=$?
    "$VENV_PY" "$ESPCMD_SCRIPT" --port "$SERIAL_PORT" write_flash 0x8000 "$PARTITIONS_BIN" || FLASH_EXIT=$?
    "$VENV_PY" "$ESPCMD_SCRIPT" --port "$SERIAL_PORT" write_flash 0x10000 "$FIRMWARE_BIN" || FLASH_EXIT=$?
    "$VENV_PY" "$ESPCMD_SCRIPT" --port "$SERIAL_PORT" write_flash 0xe000 "$BOOT_APP_BIN" || FLASH_EXIT=$?
  else
    echo "esptool not available in venv and local esptool.py not found. Cannot flash."
    FLASH_EXIT=2
  fi
fi

set -e

if [[ $FLASH_EXIT -eq 0 ]]; then
  echo "Flashing completed successfully."
else
  echo "Flashing finished with exit code: $FLASH_EXIT. Check output above for errors."
fi

echo
echo "If you were added to 'dialout', logout/login for the group change to take effect."
echo "To reactivate venv later: source \"$VENV_DIR/bin/activate\""
echo "Done."
