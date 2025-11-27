#!/bin/bash
# =============================================================================
#
#  Essential's Pack - Native Linux Setup (Cybersecurity Edition)
#  Version 5.1
#
# =============================================================================

set -e
export DEBIAN_FRONTEND=noninteractive

# --- Variáveis ---
if [ -n "$SUDO_USER" ]; then CURRENT_USER="$SUDO_USER"; else CURRENT_USER="$(whoami)"; fi
USER_HOME="/home/$CURRENT_USER"
PACKAGES_JSON="$(dirname "${BASH_SOURCE[0]}")/packages_linux.json"
FAILED_PACKAGES=()

sudo -v

# --- Funções Auxiliares ---

check_json_file() {
    if [ ! -f "$PACKAGES_JSON" ]; then
        echo "ERROR: packages_linux.json not found."
        exit 1
    fi
}

# Adiciona repositórios necessários para ferramentas de hacking no Ubuntu/Debian
setup_security_repos() {
    echo "=========================================="
    echo "  Configuring Security Repositories"
    echo "=========================================="
    
    # Metasploit (Rapid7)
    if ! command -v msfconsole &> /dev/null; then
        echo "  -> Adding Metasploit repository..."
        curl https://raw.githubusercontent.com/rapid7/metasploit-omnibus/master/config/templates/metasploit-framework-wrappers/msfupdate.erb > msfinstall && chmod 755 msfinstall && ./msfinstall
        rm msfinstall
    fi
}

install_apt_packages() {
    echo "=========================================="
    echo "  Installing APT Packages"
    echo "=========================================="
    
    # Atualiza lista antes de instalar
    sudo apt-get update
    
    local packages=$(jq -r '.apt[]' "$PACKAGES_JSON")
    local to_install=()
    
    for pkg in $packages; do
        # Verifica se já está instalado (evita reinstalação lenta)
        if dpkg -l | grep -q "^ii  $pkg "; then
            echo "  ✓ $pkg (already installed)"
        else
            to_install+=("$pkg")
        fi
    done
    
    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing: ${to_install[*]}"
        # Tenta instalar em lote
        if ! sudo apt-get install -y "${to_install[@]}"; then
             echo "  ⚠ Batch installation failed. Trying individually..."
             for pkg in "${to_install[@]}"; do
                sudo apt-get install -y "$pkg" || FAILED_PACKAGES+=("$pkg")
             done
        fi
    fi
}

install_snap_packages() {
    echo "=========================================="
    echo "  Installing Snap Packages (VSCode, etc)"
    echo "=========================================="
    local packages=$(jq -r '.snap[]' "$PACKAGES_JSON")
    for pkg in $packages; do
        if snap list 2>/dev/null | grep -q "^$pkg "; then
            echo "  ✓ $pkg (already installed)"
        else
            echo "  → Installing $pkg..."
            # --classic é necessário para o VS Code e ferramentas de dev
            sudo snap install "$pkg" --classic || FAILED_PACKAGES+=("$pkg")
        fi
    done
}

install_pip_tools() {
    echo "=========================================="
    echo "  Installing Python Security Tools (pipx)"
    echo "=========================================="
    if ! command -v pipx &> /dev/null; then
        sudo -u "$CURRENT_USER" python3 -m pip install --user pipx && sudo -u "$CURRENT_USER" python3 -m pipx ensurepath
    fi
    local packages=$(jq -r '.pip[]' "$PACKAGES_JSON")
    for pkg in $packages; do
        if sudo -u "$CURRENT_USER" pipx list 2>/dev/null | grep -q "package $pkg "; then
            echo "  ✓ $pkg (already installed)"
        else
            echo "  → Installing $pkg..."
            sudo -u "$CURRENT_USER" pipx install "$pkg" || FAILED_PACKAGES+=("$pkg")
        fi
    done
}

clone_git_repos() {
    echo "=========================================="
    echo "  Cloning Security Repositories (tools/)"
    echo "=========================================="
    local tools_dir="$USER_HOME/tools"
    sudo -u "$CURRENT_USER" mkdir -p "$tools_dir"
    
    local repos=$(jq -r '.git | to_entries[] | "\(.key)|\(.value)"' "$PACKAGES_JSON")
    while IFS='|' read -r name url; do
        local repo_path="$tools_dir/$name"
        if [ -d "$repo_path/.git" ]; then
            echo "  ✓ $name (already cloned)"
        else
            echo "  → Cloning $name..."
            sudo -u "$CURRENT_USER" git clone "$url" "$repo_path" || FAILED_PACKAGES+=("$name")
        fi
    done <<< "$repos"
}

# --- Execução Principal ---
main() {
    check_json_file
    
    setup_security_repos
    install_apt_packages
    install_snap_packages
    install_pip_tools
    clone_git_repos
    
    # (Opcional) Instalar Rust/Go/Node se necessário, reutilizando funções anteriores
    
    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        echo "Failures: ${FAILED_PACKAGES[*]}"
    fi
    echo "Setup Complete!"
}

main
