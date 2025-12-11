#!/bin/bash
# =============================================================================
#
#  Essential's Pack - Native Linux Setup (Cybersecurity Edition)
#  Version 5.2 (Parity with Windows/WSL - Custom Language Versions)
#
# =============================================================================

set -e
export DEBIAN_FRONTEND=noninteractive

# --- Variáveis de Versão (EDITÁVEIS) ---
# Altere aqui para as versões que você deseja usar no Linux Nativo
PYTHON_VERSION="3.12.2"
JAVA_VERSION="25.0.0-tem"   # Verifique a disponibilidade exata no SDKMAN
RUBY_VERSION="3.3.0"
NODE_VERSION="lts/*"         # 'node' para a última versão, ou 'lts/*' para LTS

# --- Variáveis de Ambiente ---
if [ -n "$SUDO_USER" ]; then CURRENT_USER="$SUDO_USER"; else CURRENT_USER="$(whoami)"; fi
USER_HOME="/home/$CURRENT_USER"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_JSON="$SCRIPT_DIR/packages_linux.json"
FAILED_PACKAGES=()

sudo -v

# --- Funções Auxiliares ---

check_json_file() {
    if [ ! -f "$PACKAGES_JSON" ]; then
        echo "ERROR: packages_linux.json not found."
        exit 1
    fi
}

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
    
    sudo apt-get update
    
    local packages=$(jq -r '.apt[]' "$PACKAGES_JSON")
    local to_install=()
    
    for pkg in $packages; do
        if dpkg -l | grep -q "^ii  $pkg "; then
            echo "  ✓ $pkg (already installed)"
        else
            to_install+=("$pkg")
        fi
    done
    
    if [ ${#to_install[@]} -gt 0 ]; then
        echo "Installing: ${to_install[*]}"
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
    echo "  Installing Snap Packages"
    echo "=========================================="
    local packages=$(jq -r '.snap[]' "$PACKAGES_JSON")
    for pkg in $packages; do
        if snap list 2>/dev/null | grep -q "^$pkg "; then
            echo "  ✓ $pkg (already installed)"
        else
            echo "  → Installing $pkg..."
            sudo snap install "$pkg" --classic || FAILED_PACKAGES+=("$pkg")
        fi
    done
}

# --- Funções de Linguagem (Portadas do WSL) ---

install_sdkman() {
    echo "=========================================="
    echo "  Installing SDKMAN (Java $JAVA_VERSION)"
    echo "=========================================="
    
    if [ ! -d "$USER_HOME/.sdkman" ]; then
        echo "Installing SDKMAN..."
        sudo -u "$CURRENT_USER" bash -c 'curl -s "https://get.sdkman.io" | bash'
    fi
    
    # Instalar Java e ferramentas JVM
    echo "Installing Java $JAVA_VERSION and JVM tools..."
    sudo -u "$CURRENT_USER" bash -c "
        export SDKMAN_DIR=\"$USER_HOME/.sdkman\"
        [[ -s \"\$SDKMAN_DIR/bin/sdkman-init.sh\" ]] && source \"\$SDKMAN_DIR/bin/sdkman-init.sh\"
        sdk install java $JAVA_VERSION || echo 'Warning: Java version not found'
        sdk install kotlin
        sdk install maven
        sdk install gradle
    "
}

install_nvm() {
    echo "=========================================="
    echo "  Installing NVM & Node.js ($NODE_VERSION)"
    echo "=========================================="
    
    if [ ! -d "$USER_HOME/.nvm" ]; then
        echo "Installing NVM..."
        sudo -u "$CURRENT_USER" bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
    fi
    
    echo "Installing Node.js..."
    sudo -u "$CURRENT_USER" bash -c "
        export NVM_DIR=\"$USER_HOME/.nvm\"
        [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"
        nvm install '$NODE_VERSION'
        nvm alias default '$NODE_VERSION'
        npm install -g typescript
    "
}

install_python_managers() {
    echo "=========================================="
    echo "  Installing Pyenv (Python $PYTHON_VERSION)"
    echo "=========================================="
    
    # Dependências de build do Python (importante no Linux nativo)
    sudo apt-get install -y make build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev wget curl llvm \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
    
    if ! command -v pyenv &> /dev/null; then
        echo "Installing pyenv..."
        sudo -u "$CURRENT_USER" bash -c 'curl https://pyenv.run | bash'
    fi
    
    echo "Installing Python $PYTHON_VERSION..."
    sudo -u "$CURRENT_USER" bash -c "
        export PYENV_ROOT=\"$USER_HOME/.pyenv\"
        export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
        eval \"\$(pyenv init -)\"
        pyenv install -s $PYTHON_VERSION
        pyenv global $PYTHON_VERSION
    "
    
    # Instalar Pipx para ferramentas globais
    if ! command -v pipx &> /dev/null; then
        sudo -u "$CURRENT_USER" bash -c "export PATH=\"\$HOME/.pyenv/shims:\$PATH\" && python3 -m pip install --user pipx && python3 -m pipx ensurepath"
    fi
}

install_pip_tools_via_pipx() {
    echo "=========================================="
    echo "  Installing Security Tools (via pipx)"
    echo "=========================================="
    # Recarrega PATH para garantir que pipx seja encontrado
    export PATH="$USER_HOME/.local/bin:$PATH"
    
    local packages=$(jq -r '.pip[]' "$PACKAGES_JSON")
    for pkg in $packages; do
        if sudo -u "$CURRENT_USER" pipx list 2>/dev/null | grep -q "package $pkg "; then
            echo "  ✓ $pkg (already installed)"
        else
            echo "  → Installing $pkg..."
            # Força o uso do python do pyenv ou do sistema
            sudo -u "$CURRENT_USER" bash -c "export PATH=\"\$HOME/.local/bin:\$PATH\" && pipx install \"$pkg\"" || FAILED_PACKAGES+=("$pkg")
        fi
    done
}

clone_git_repos() {
    echo "=========================================="
    echo "  Cloning Security Repositories"
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
    echo "Starting Native Linux Setup (v5.2)..."
    check_json_file
    
    setup_security_repos
    install_apt_packages
    install_snap_packages
    
    # Novas chamadas para gerenciadores de versão
    install_sdkman        # Instala Java 25 (ou definido)
    install_nvm           # Instala Node.js
    install_python_managers # Instala Python 3.12+
    
    install_pip_tools_via_pipx
    clone_git_repos
    
    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        echo "Failures: ${FAILED_PACKAGES[*]}"
    fi
    echo "Setup Complete! Please restart your terminal."
}

main
