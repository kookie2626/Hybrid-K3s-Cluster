#!/usr/bin/env bash
# =============================================================================
# ollama-imac-setup.sh
# macOS host script — installs Ollama natively on iMac M1 (Apple Silicon),
# pulls the qwen2.5-coder:14b model, and registers a launchd service so
# Ollama starts automatically at login.
#
# Ollama runs directly on macOS to leverage Metal GPU acceleration (far faster
# than running inside a Lima VM).  A Kubernetes ExternalName-style Service in
# manifests/ollama/ollama-service.yaml makes the endpoint available to other
# pods in the K3s cluster.
#
# Usage:
#   chmod +x ollama-imac-setup.sh
#   ./ollama-imac-setup.sh
#
# Environment variables (optional):
#   OLLAMA_HOST   Bind address for Ollama server (default: 0.0.0.0:11434)
#                 Set to "127.0.0.1:11434" to restrict access to localhost only.
#   MODEL         Model to pull after installation (default: qwen2.5-coder:14b)
# =============================================================================

set -euo pipefail

# --------------------------------------------------------------------------- #
# 0. Helpers
# --------------------------------------------------------------------------- #
info()  { echo -e "\033[0;34m[INFO]\033[0m  $*"; }
ok()    { echo -e "\033[0;32m[OK]\033[0m    $*"; }
warn()  { echo -e "\033[0;33m[WARN]\033[0m  $*"; }
die()   { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Must run on macOS
[[ "$(uname -s)" == "Darwin" ]] || die "This script must be run on macOS."

OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:11434}"
MODEL="${MODEL:-qwen2.5-coder:14b}"
PLIST_DIR="${HOME}/Library/LaunchAgents"
PLIST_FILE="${PLIST_DIR}/io.ollama.server.plist"

# --------------------------------------------------------------------------- #
# 1. Check / install Homebrew
# --------------------------------------------------------------------------- #
info "Checking for Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
    info "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
ok "Homebrew is available."

# --------------------------------------------------------------------------- #
# 2. Install Ollama
# --------------------------------------------------------------------------- #
info "Installing / upgrading Ollama..."
brew install ollama
ok "Ollama $(ollama --version) installed."

# --------------------------------------------------------------------------- #
# 3. Register Ollama as a launchd user service
#    This ensures Ollama starts automatically at login and binds to
#    OLLAMA_HOST so the K3s cluster can reach it.
# --------------------------------------------------------------------------- #
info "Registering Ollama as a launchd service (${PLIST_FILE})..."

OLLAMA_BIN="$(command -v ollama)"

mkdir -p "${PLIST_DIR}"

cat > "${PLIST_FILE}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.ollama.server</string>

    <key>ProgramArguments</key>
    <array>
        <string>${OLLAMA_BIN}</string>
        <string>serve</string>
    </array>

    <!-- Bind on all interfaces so the K3s Lima VM and other cluster nodes
         can reach Ollama over the LAN.
         Change to 127.0.0.1:11434 if you only need local access. -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>OLLAMA_HOST</key>
        <string>${OLLAMA_HOST}</string>
    </dict>

    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/ollama.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/ollama.err</string>
</dict>
</plist>
PLIST

# Reload launchd agent (unload first in case it was already loaded)
launchctl unload "${PLIST_FILE}" 2>/dev/null || true
launchctl load -w "${PLIST_FILE}"

ok "Ollama launchd service loaded and set to start at login."

# --------------------------------------------------------------------------- #
# 4. Wait for Ollama to be ready
# --------------------------------------------------------------------------- #
info "Waiting for Ollama server to become ready..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:11434/" >/dev/null 2>&1; then
        ok "Ollama server is ready."
        break
    fi
    if [[ "${i}" -eq 30 ]]; then
        die "Ollama server did not become ready within 30 seconds. Check /tmp/ollama.err"
    fi
    sleep 1
done

# --------------------------------------------------------------------------- #
# 5. Pull the model
# --------------------------------------------------------------------------- #
info "Pulling model '${MODEL}' — this may take several minutes on first run..."
OLLAMA_HOST="${OLLAMA_HOST}" ollama pull "${MODEL}"
ok "Model '${MODEL}' is ready."

# --------------------------------------------------------------------------- #
# 6. Smoke test
# --------------------------------------------------------------------------- #
info "Running a quick smoke test..."
RESPONSE=$(OLLAMA_HOST="${OLLAMA_HOST}" ollama run "${MODEL}" "Say 'OK' in one word." 2>&1 || true)
ok "Smoke test response: ${RESPONSE}"

# --------------------------------------------------------------------------- #
# 7. Summary
# --------------------------------------------------------------------------- #
IMAC_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "<iMac-IP>")

echo
ok "======================================================"
ok " Ollama setup complete on iMac!"
echo
ok " Model       : ${MODEL}"
ok " Bind address: ${OLLAMA_HOST}"
ok " iMac LAN IP : ${IMAC_IP}"
ok " Logs        : /tmp/ollama.log  /tmp/ollama.err"
echo
ok " API endpoint visible in the cluster:"
ok "   http://${IMAC_IP}:11434"
echo
ok " Apply the K8s service manifest so cluster pods can reach Ollama:"
ok "   kubectl apply -f manifests/ollama/ollama-service.yaml"
echo
ok " (Remember to set OLLAMA_IMAC_IP in the manifest to ${IMAC_IP})"
ok "======================================================"
