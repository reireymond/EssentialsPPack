Com base na análise do arquivo `setup_windows.ps1` (v5.2) que você forneceu, fiz a atualização do script `wsl_ubuntu.sh` para a **Versão 5.2**.

O objetivo desta atualização é trazer a **paridade de recursos e otimizações** que foram implementadas na versão Windows, especificamente:

1.  **Otimização de Cache (L1/L2)**: O script agora carrega a lista de pacotes instalados (APT, Snap, Pipx) *antes* de iniciar os loops de instalação. Isso elimina a execução repetitiva de comandos lentos (como `dpkg -l` ou `snap list`) dentro dos loops, tornando a reexecução do script muito mais rápida.
2.  **Sistema de Logs em JSON**: Assim como no Windows, o script agora gera um log estruturado em JSON ao final da execução, salvo em `~/.local/state/essentialsppack/`, contendo estatísticas de sucesso, falha e itens pulados.
3.  **Sumário Detalhado**: O relatório final foi expandido para mostrar não apenas as falhas, mas também os pacotes instalados com sucesso e os que foram pulados (já instalados), garantindo visibilidade total.
4.  **Estrutura Refinada**: Manutenção da arquitetura modular introduzida na v5.1, mas com a lógica de verificação aprimorada.

Aqui está o código atualizado para o `wsl_ubuntu.sh` (v5.2):

```bash
#!/bin/bash
# =============================================================================
#
#  Essential's Pack - WSL (Ubuntu) Setup Script
#  Version 5.2 (MATCHING WINDOWS: Cache Optimization + JSON Logging)
#
#  Installs a complete Development, DevOps, and Pentest environment.
#
# =============================================================================

# Exit immediately if a command fails
set -e

# Ensures the script is non-interactive
export DEBIAN_FRONTEND=noninteractive

# Variables
if [ -n "$SUDO_USER" ]; then
    CURRENT_USER="$SUDO_USER"
else
    CURRENT_USER="$(whoami)"
fi
USER_HOME="/home/$CURRENT_USER"
NVM_DIR="$USER_HOME/.nvm"
ZSHRC_PATH="$USER_HOME/.zshrc"
PYTHON_VERSION="3.11.8"
JAVA_VERSION="17.0.10-tem"
RUBY_VERSION="3.2.2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Caminho para o JSON de pacotes
PACKAGES_JSON="$SCRIPT_DIR/../Linux/packages_linux.json"

# Logging and Tracking
LOG_DIR="$USER_HOME/.local/state/essentialsppack"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
SUCCEEDED_PACKAGES=()
FAILED_PACKAGES=()
SKIPPED_PACKAGES=()

# Request administrator (sudo) privileges at the start
sudo -v

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Check if a package JSON file exists and is valid
check_json_file() {
    if [ ! -f "$PACKAGES_JSON" ]; then
        echo "ERROR: packages_linux.json not found at: $PACKAGES_JSON"
        exit 1
    fi
    
    if ! jq empty "$PACKAGES_JSON" 2>/dev/null; then
        echo "ERROR: packages_linux.json is not valid JSON"
        exit 1
    fi
    
    echo "Package definitions loaded from JSON successfully."
}

# Generate JSON Log and Summary
write_install_summary() {
    echo ""
    echo "=========================================="
    echo "  INSTALLATION SUMMARY"
    echo "=========================================="
    
    echo -e "\033[0;32m✓ Succeeded: ${#SUCCEEDED_PACKAGES[@]}\033[0m"
    if [ ${#SUCCEEDED_PACKAGES[@]} -gt 0 ]; then
        printf '  - %s\n' "${SUCCEEDED_PACKAGES[@]}"
    fi

    echo -e "\n\033[0;33m⊘ Skipped (Already Installed): ${#SKIPPED_PACKAGES[@]}\033[0m"
    if [ ${#SKIPPED_PACKAGES[@]} -gt 0 ]; then
        printf '  - %s\n' "${SKIPPED_PACKAGES[@]}"
    fi

    echo -e "\n\033[0;31m✗ Failed: ${#FAILED_PACKAGES[@]}\033[0m"
    if [ ${#FAILED_PACKAGES[@]} -gt 0 ]; then
        printf '  - %s\n' "${FAILED_PACKAGES[@]}"
    fi
    echo "=========================================="

    # Create Log Directory
    sudo -u "$CURRENT_USER" mkdir -p "$LOG_DIR"
    local log_file="$LOG_DIR/install-log-$TIMESTAMP.json"

    # Construct JSON using jq if available, else manual
    if command -v jq &> /dev/null; then
        jq -n \
           --arg timestamp "$TIMESTAMP" \
           --arg version "5.2" \
           --argjson succeeded "$(printf '%s\n' "${SUCCEEDED_PACKAGES[@]}" | jq -R . | jq -s .)" \
           --argjson failed "$(printf '%s\n' "${FAILED_PACKAGES[@]}" | jq -R . | jq -s .)" \
           --argjson skipped "$(printf '%s\n' "${SKIPPED_PACKAGES[@]}" | jq -R . | jq -s .)" \
           '{timestamp: $timestamp, scriptVersion: $version, stats: {succeeded: ($succeeded|length), failed: ($failed|length), skipped: ($skipped|length)}, details: {succeeded: $succeeded, failed: $failed, skipped: $skipped}}' \
           > "$log_file"
        
        # Correct permissions since we might be running as root
        chown "$CURRENT_USER:$CURRENT_USER" "$log_file"
        echo "Installation log saved to: $log_file"
    else
        echo "jq not found for JSON logging. Skipping log file generation."
    fi
}

# =============================================================================
# INSTALLATION FUNCTIONS (OPTIMIZED)
# =============================================================================

# Install APT packages with CACHE check
install_apt_packages() {
    echo "=========================================="
    echo "  Installing APT Packages"
    echo "=========================================="
    
    # 1. Build Cache (L1 Optimization)
    echo "  → Building APT package cache..."
    local installed_apt
    installed_apt=$(dpkg-query -W -f='${Package}\n' 2>/dev/null)

    # Read packages from JSON
    local packages=$(jq -r '.apt[]' "$PACKAGES_JSON")
    local to_install=()
    
    # 2. Check existence using cache (Fast)
    for pkg in $packages; do
        if echo "$installed_apt" | grep -q "^$pkg$"; then
            echo "  ✓ $pkg (already installed)"
            SKIPPED_PACKAGES+=("$pkg")
        else
            to_install+=("$pkg")
        fi
    done
    
    # 3. Batch Install
    if [ ${#to_install[@]} -gt 0 ]; then
        echo "  → Installing ${#to_install[@]} new packages..."
        if sudo apt-get install -y "${to_install[@]}"; then
            echo "  ✓ Batch installation successful"
            SUCCEEDED_PACKAGES+=("${to_install[@]}")
        else
            echo "  ⚠ Batch installation failed. Trying individually..."
            for pkg in "${to_install[@]}"; do
                if sudo apt-get install -y "$pkg"; then
                    echo "  ✓ $pkg installed"
                    SUCCEEDED_PACKAGES+=("$pkg")
                else
                    echo "  ✗ $pkg failed"
                    FAILED_PACKAGES+=("$pkg")
                fi
            done
        fi
    else
        echo "All APT packages already installed."
    fi
}

# Install snap packages with CACHE check
install_snap_packages() {
    echo "=========================================="
    echo "  Installing Snap Packages"
    echo "=========================================="
    
    # 1. Build Cache
    local installed_snaps
    installed_snaps=$(snap list 2>/dev/null | awk '{print $1}')

    local packages=$(jq -r '.snap[]' "$PACKAGES_JSON")
    
    for pkg in $packages; do
        if echo "$installed_snaps" | grep -q "^$pkg$"; then
            echo "  ✓ $pkg (already installed)"
            SKIPPED_PACKAGES+=("$pkg")
        else
            echo "  → Installing $pkg via snap..."
            if sudo snap install "$pkg" --classic 2>/dev/null; then
                echo "  ✓ $pkg installed"
                SUCCEEDED_PACKAGES+=("$pkg")
            else
                echo "  ✗ $pkg failed via snap, trying apt fallback..."
                if sudo apt-get install -y "$pkg" 2>/dev/null; then
                    echo "  ✓ $pkg installed via apt (fallback)"
                    SUCCEEDED_PACKAGES+=("$pkg")
                else
                    echo "  ✗ $pkg failed completely"
                    FAILED_PACKAGES+=("$pkg")
                fi
            fi
        fi
    done
}

# Install pip tools with CACHE check
install_pip_tools() {
    echo "=========================================="
    echo "  Installing Python Tools (via pipx)"
    echo "=========================================="
    
    # Ensure pipx
    if ! command -v pipx &> /dev/null; then
        echo "Installing pipx..."
        sudo -u "$CURRENT_USER" bash -c 'python3 -m pip install --user pipx && python3 -m pipx ensurepath'
    fi
    
    # 1. Build Cache
    local installed_pipx
    installed_pipx=$(sudo -u "$CURRENT_USER" pipx list --short 2>/dev/null | awk '{print $1}')

    local packages=$(jq -r '.pip[]' "$PACKAGES_JSON")
    
    for pkg in $packages; do
        if echo "$installed_pipx" | grep -q "^$pkg$"; then
            echo "  ✓ $pkg (already installed)"
            SKIPPED_PACKAGES+=("$pkg")
        else
            echo "  → Installing $pkg via pipx..."
            if sudo -u "$CURRENT_USER" bash -c "export PATH=\"\$HOME/.local/bin:\$PATH\" && pipx install $pkg" 2>/dev/null; then
                echo "  ✓ $pkg installed"
                SUCCEEDED_PACKAGES+=("$pkg")
            else
                echo "  ✗ $pkg failed"
                FAILED_PACKAGES+=("$pkg")
            fi
        fi
    done
}

# Clone git repositories
clone_git_repos() {
    echo "=========================================="
    echo "  Cloning Git Repositories"
    echo "=========================================="
    
    local tools_dir="$USER_HOME/tools"
    sudo -u "$CURRENT_USER" mkdir -p "$tools_dir"
    
    local repos=$(jq -r '.git | to_entries[] | "\(.key)|\(.value)"' "$PACKAGES_JSON")
    
    while IFS='|' read -r name url; do
        local repo_path="$tools_dir/$name"
        if [ -d "$repo_path/.git" ]; then
            echo "  ✓ $name (already cloned)"
            SKIPPED_PACKAGES+=("git:$name")
        else
            echo "  → Cloning $name..."
            if sudo -u "$CURRENT_USER" git clone "$url" "$repo_path"; then
                echo "  ✓ $name cloned successfully"
                SUCCEEDED_PACKAGES+=("git:$name")
            else
                echo "  ✗ $name failed to clone"
                FAILED_PACKAGES+=("git:$name")
            fi
        fi
    done <<< "$repos"
}

# Install/setup specific cloned git repositories
install_cloned_repos() {
    echo "=========================================="
    echo "  Setting up Cloned Repositories"
    echo "=========================================="
    
    local mobsf_dir="$USER_HOME/tools/mobsf"
    
    if [ -f "$mobsf_dir/setup.sh" ]; then
        echo "  → Setting up MobSF..."
        (
            cd "$mobsf_dir"
            if sudo -u "$CURRENT_USER" ./setup.sh; then
                echo "  ✓ MobSF setup complete"
                SUCCEEDED_PACKAGES+=("MobSF-Setup")
            else
                echo "  ✗ MobSF setup failed"
                FAILED_PACKAGES+=("MobSF-Setup")
            fi
        )
    else
        echo "  i MobSF (not found/cloned, skipping setup)"
    fi
}

# Install radare2 from source
install_radare2() {
    echo "=========================================="
    echo "  Installing Radare2 (from source)"
    echo "=========================================="
    
    if command -v radare2 &> /dev/null; then
        echo "  ✓ radare2 (already installed)"
        SKIPPED_PACKAGES+=("radare2")
        return 0
    fi
    
    local r2_dir="$USER_HOME/tools/radare2"
    
    if [ ! -d "$r2_dir" ]; then
        echo "  → Cloning radare2..."
        sudo -u "$CURRENT_USER" git clone https://github.com/radareorg/radare2 "$r2_dir"
    fi
    
    echo "  → Building and installing radare2..."
    (
        cd "$r2_dir"
        if sudo -u "$CURRENT_USER" sys/install.sh; then
            echo "  ✓ radare2 installed successfully"
            SUCCEEDED_PACKAGES+=("radare2")
        else
            echo "  ✗ radare2 failed to install"
            FAILED_PACKAGES+=("radare2")
        fi
    )
}

# Install Rust
install_rust() {
    echo "=========================================="
    echo "  Installing Rust (rustup)"
    echo "=========================================="
    
    if command -v rustup &> /dev/null; then
        echo "  ✓ Rust (already installed)"
        SKIPPED_PACKAGES+=("rust")
        return 0
    fi
    
    echo "Installing Rust (rustup)..."
    if sudo -u "$CURRENT_USER" bash -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y'; then
        source "$USER_HOME/.cargo/env" 2>/dev/null || true
        SUCCEEDED_PACKAGES+=("rust")
    else
        FAILED_PACKAGES+=("rust")
    fi
}

# Install .NET SDK
install_dotnet() {
    echo "=========================================="
    echo "  Installing .NET SDK"
    echo "=========================================="
    
    if command -v dotnet &> /dev/null; then
        echo "  ✓ .NET SDK (already installed)"
        SKIPPED_PACKAGES+=("dotnet")
        return 0
    fi
    
    if [ ! -f /etc/apt/sources.list.d/microsoft-prod.list ]; then
        wget https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
        sudo dpkg -i /tmp/packages-microsoft-prod.deb
        rm /tmp/packages-microsoft-prod.deb
        sudo apt-get update
    fi
    
    if sudo apt-get install -y dotnet-sdk-8.0; then
        SUCCEEDED_PACKAGES+=("dotnet")
    else
        FAILED_PACKAGES+=("dotnet")
    fi
}

# Install SDKMAN
install_sdkman() {
    echo "=========================================="
    echo "  Installing SDKMAN"
    echo "=========================================="
    
    if [ -d "$USER_HOME/.sdkman" ]; then
        echo "  ✓ SDKMAN (already installed)"
        SKIPPED_PACKAGES+=("sdkman")
        return 0
    fi
    
    echo "Installing SDKMAN..."
    if sudo -u "$CURRENT_USER" bash -c 'curl -s "https://get.sdkman.io" | bash'; then
        SUCCEEDED_PACKAGES+=("sdkman")
    else
        FAILED_PACKAGES+=("sdkman")
    fi
}

# Install NVM
install_nvm() {
    echo "=========================================="
    echo "  Installing NVM"
    echo "=========================================="
    
    if [ -d "$NVM_DIR" ]; then
        echo "  ✓ NVM (already installed)"
        SKIPPED_PACKAGES+=("nvm")
        return 0
    fi
    
    echo "Installing NVM..."
    if sudo -u "$CURRENT_USER" bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'; then
        SUCCEEDED_PACKAGES+=("nvm")
    else
        FAILED_PACKAGES+=("nvm")
    fi
}

# Install Pyenv and Poetry
install_python_managers() {
    echo "=========================================="
    echo "  Installing Pyenv, Poetry, and PIPX"
    echo "=========================================="
    
    if ! command -v pyenv &> /dev/null; then
        echo "Installing pyenv..."
        if sudo -u "$CURRENT_USER" bash -c 'curl https://pyenv.run | bash'; then
            SUCCEEDED_PACKAGES+=("pyenv")
        else
            FAILED_PACKAGES+=("pyenv")
        fi
    else
        SKIPPED_PACKAGES+=("pyenv")
    fi
    
    if ! command -v poetry &> /dev/null; then
        echo "Installing Poetry..."
        if sudo -u "$CURRENT_USER" bash -c 'curl -sSL https://install.python-poetry.org | python3 -'; then
             SUCCEEDED_PACKAGES+=("poetry")
        else
             FAILED_PACKAGES+=("poetry")
        fi
    else
        SKIPPED_PACKAGES+=("poetry")
    fi
}

# Install Rbenv
install_rbenv() {
    echo "=========================================="
    echo "  Installing Rbenv"
    echo "=========================================="
    
    if command -v rbenv &> /dev/null; then
        echo "  ✓ Rbenv (already installed)"
        SKIPPED_PACKAGES+=("rbenv")
        return 0
    fi
    
    echo "Installing rbenv..."
    if sudo -u "$CURRENT_USER" git clone https://github.com/rbenv/rbenv.git "$USER_HOME/.rbenv" && \
       sudo -u "$CURRENT_USER" git clone https://github.com/rbenv/ruby-build.git "$USER_HOME/.rbenv/plugins/ruby-build"; then
        SUCCEEDED_PACKAGES+=("rbenv")
    else
        FAILED_PACKAGES+=("rbenv")
    fi
}

# Install Docker
install_docker() {
    echo "=========================================="
    echo "  Installing Docker"
    echo "=========================================="
    
    if command -v docker &> /dev/null; then
        echo "  ✓ Docker (already installed)"
        SKIPPED_PACKAGES+=("docker")
        return 0
    fi
    
    sudo install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
    fi
    
    if sudo apt-get install -y docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; then
        echo "[+] Adding $CURRENT_USER to docker group..."
        sudo usermod -aG docker "$CURRENT_USER"
        
        # Configure passwordless sudo for Docker service
        if ! sudo grep -q "docker-nopasswd" /etc/sudoers.d/docker-nopasswd 2>/dev/null; then
            echo "%docker ALL=(ALL) NOPASSWD: /usr/sbin/service docker *" | sudo tee /etc/sudoers.d/docker-nopasswd > /dev/null
            sudo chmod 0440 /etc/sudoers.d/docker-nopasswd
        fi
        SUCCEEDED_PACKAGES+=("docker")
    else
        FAILED_PACKAGES+=("docker")
    fi
}

# Install Helm and Terraform
install_cloud_tools() {
    echo "=========================================="
    echo "  Installing Helm and Terraform"
    echo "=========================================="
    
    if ! command -v helm &> /dev/null; then
        if [ ! -f /usr/share/keyrings/helm.gpg ]; then
            curl https://baltocdn.com/helm/signing.asc | sudo gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
            sudo apt-get update
        fi
        if sudo apt-get install -y helm; then SUCCEEDED_PACKAGES+=("helm"); else FAILED_PACKAGES+=("helm"); fi
    else
        SKIPPED_PACKAGES+=("helm")
    fi
    
    if ! command -v terraform &> /dev/null; then
        if [ ! -f /usr/share/keyrings/hashicorp-archive-keyring.gpg ]; then
            wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
            echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
            sudo apt-get update
        fi
        if sudo apt-get install -y terraform; then SUCCEEDED_PACKAGES+=("terraform"); else FAILED_PACKAGES+=("terraform"); fi
    else
        SKIPPED_PACKAGES+=("terraform")
    fi
}

# Install Go tools
install_go_tools() {
    echo "=========================================="
    echo "  Installing Go DevOps Tools"
    echo "=========================================="
    
    mkdir -p "$USER_HOME/go/bin"
    
    local go_tools=(
        "github.com/jesseduffield/lazygit@latest"
        "github.com/jesseduffield/lazydocker@latest"
        "github.com/roboll/helmfile@latest"
        "github.com/aquasecurity/trivy/cmd/trivy@latest"
        "github.com/charmbracelet/gum@latest"
        "github.com/tomnomnom/gf@latest"
        "github.com/in-toto/go-witness/cmd/witness@latest"
        "github.com/projectdiscovery/httpx/cmd/httpx@latest"
        "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        "github.com/epi052/feroxbuster@latest"
        "github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
    )
    
    for tool in "${go_tools[@]}"; do
        local tool_name=$(basename "$tool" | cut -d'@' -f1)
        if [ -f "$USER_HOME/go/bin/$tool_name" ]; then
            echo "  ✓ $tool_name (already installed)"
            SKIPPED_PACKAGES+=("go:$tool_name")
        else
            echo "  → Installing $tool_name..."
            if sudo -u "$CURRENT_USER" bash -c "export PATH=\"\$PATH:/usr/local/go/bin:\$HOME/go/bin\" && go install $tool"; then
                SUCCEEDED_PACKAGES+=("go:$tool_name")
            else
                FAILED_PACKAGES+=("go:$tool_name")
            fi
        fi
    done
    
    # Create system-wide symlinks
    for tool_path in "$USER_HOME/go/bin"/*; do
        if [ -f "$tool_path" ]; then
            local tool_name=$(basename "$tool_path")
            if [ ! -L "/usr/local/bin/$tool_name" ]; then
                sudo ln -sf "$tool_path" /usr/local/bin/
            fi
        fi
    done
}

# Setup Zsh and Oh My Zsh
setup_oh_my_zsh() {
    echo "=========================================="
    echo "  Installing Zsh + Oh My Zsh + Powerlevel10k"
    echo "=========================================="
    
    if [ "$(getent passwd "$CURRENT_USER" | cut -d: -f7)" != "$(which zsh)" ]; then
        echo "Setting Zsh as default shell..."
        sudo chsh -s "$(which zsh)" "$CURRENT_USER"
    fi
    
    if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
        echo "Installing Oh My Zsh..."
        sudo -u "$CURRENT_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        SUCCEEDED_PACKAGES+=("oh-my-zsh")
    else
        SKIPPED_PACKAGES+=("oh-my-zsh")
    fi
    
    # Plugins & Themes
    local ZSH_CUSTOM_PLUGINS="$USER_HOME/.oh-my-zsh/custom/plugins"
    if [ ! -d "$ZSH_CUSTOM_PLUGINS/zsh-autosuggestions" ]; then 
        sudo -u "$CURRENT_USER" git clone https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM_PLUGINS/zsh-autosuggestions"
    fi
    if [ ! -d "$ZSH_CUSTOM_PLUGINS/zsh-syntax-highlighting" ]; then 
        sudo -u "$CURRENT_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM_PLUGINS/zsh-syntax-highlighting"
    fi
    
    local P10K_PATH="$USER_HOME/.oh-my-zsh/custom/themes/powerlevel10k"
    if [ ! -d "$P10K_PATH" ]; then 
        sudo -u "$CURRENT_USER" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_PATH"
        SUCCEEDED_PACKAGES+=("powerlevel10k")
    else
        SKIPPED_PACKAGES+=("powerlevel10k")
    fi

    # Update .zshrc
    if [ -f "$ZSHRC_PATH" ]; then
        if grep -q "plugins=(git)" "$ZSHRC_PATH"; then
            sudo -u "$CURRENT_USER" sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' "$ZSHRC_PATH"
        fi
        if grep -q 'ZSH_THEME="robbyrussell"' "$ZSHRC_PATH"; then
            sudo -u "$CURRENT_USER" sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC_PATH"
        fi
    fi
}

# Install Starship
install_starship() {
    echo "=========================================="
    echo "  Installing Starship Prompt"
    echo "=========================================="
    
    if command -v starship &> /dev/null; then
        echo "  ✓ Starship (already installed)"
        SKIPPED_PACKAGES+=("starship")
        return 0
    fi
    
    if sudo -u "$CURRENT_USER" sh -c 'curl -sS https://starship.rs/install.sh | sh -s -- -y'; then
        SUCCEEDED_PACKAGES+=("starship")
    else
        FAILED_PACKAGES+=("starship")
    fi
}

# Configure shell aliases and loaders
configure_shell() {
    echo "=========================================="
    echo "  Configuring Shell Aliases and Loaders"
    echo "=========================================="
    
    local ALIAS_MARKER="# --- Custom Aliases ---"
    if ! grep -q "$ALIAS_MARKER" "$ZSHRC_PATH"; then
        sudo -u "$CURRENT_USER" tee -a "$ZSHRC_PATH" > /dev/null << 'EOF'

# --- Custom Aliases ---
alias ls='eza --icons --git'
alias ll='eza -l --icons --git --all'
alias lt='eza -T'
alias top='bpytop'
alias update='sudo apt-get update && sudo apt-get upgrade -y'
alias cleanup='sudo apt-get autoremove -y && sudo apt-get clean'
alias open='explorer.exe .'
alias c='clear'
alias df='duf'
alias z='zoxide'

# --- Runtime Loaders ---
if command -v starship 1>/dev/null 2>&1; then eval "$(starship init zsh)"; fi
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
if command -v pyenv 1>/dev/null 2>&1; then eval "$(pyenv init -)"; fi
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.rbenv/bin:$PATH"
if command -v rbenv 1>/dev/null 2>&1; then eval "$(rbenv init -)"; fi
export PATH="$HOME/.rbenv/plugins/ruby-build/bin:$PATH"
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
EOF
        SUCCEEDED_PACKAGES+=("shell-config")
    else
        SKIPPED_PACKAGES+=("shell-config")
    fi
}

# Install language versions
install_language_versions() {
    echo "=========================================="
    echo "  Installing Default Language Versions"
    echo "=========================================="
    
    # Node.js LTS
    sudo -u "$CURRENT_USER" bash -c "export NVM_DIR=\"$USER_HOME/.nvm\"; [ -s \"\$NVM_DIR/nvm.sh\" ] && . \"\$NVM_DIR/nvm.sh\"; nvm install 'lts/*'; nvm alias default 'lts/*'; npm install -g typescript"
    
    # Java
    sudo -u "$CURRENT_USER" bash -c "export SDKMAN_DIR=\"$USER_HOME/.sdkman\"; [[ -s \"\$SDKMAN_DIR/bin/sdkman-init.sh\" ]] && source \"\$SDKMAN_DIR/bin/sdkman-init.sh\"; sdk install java $JAVA_VERSION; sdk install kotlin; sdk install maven; sdk install gradle"
    
    # Python
    sudo -u "$CURRENT_USER" bash -c "export PYENV_ROOT=\"$USER_HOME/.pyenv\"; export PATH=\"\$PYENV_ROOT/bin:\$PATH\"; eval \"\$(pyenv init -)\"; pyenv install -s $PYTHON_VERSION; pyenv global $PYTHON_VERSION"
    
    # Ruby
    sudo -u "$CURRENT_USER" bash -c "export PATH=\"$USER_HOME/.rbenv/bin:\$PATH\"; eval \"\$(rbenv init -)\"; rbenv install -s $RUBY_VERSION; rbenv global $RUBY_VERSION; gem install evil-winrm"
}

# Install miscellaneous tools
install_misc_tools() {
    echo "=========================================="
    echo "  Installing Miscellaneous Tools"
    echo "=========================================="
    
    # LinuxToys
    if ! command -v linux-toys &> /dev/null; then
        sudo -u "$CURRENT_USER" bash -c 'cd /tmp && curl -fsSLJO https://linux.toys/install.sh && chmod +x install.sh && ./install.sh && rm -f install.sh'
        SUCCEEDED_PACKAGES+=("linux-toys")
    else
        SKIPPED_PACKAGES+=("linux-toys")
    fi
    
    # Nginx
    if sudo apt-get install -y nginx; then SUCCEEDED_PACKAGES+=("nginx"); else FAILED_PACKAGES+=("nginx"); fi
    
    # Symlinks fd/bat
    [ ! -L /usr/bin/fd ] && { sudo ln -s /usr/bin/fdfind /usr/bin/fd; }
    [ ! -L /usr/bin/bat ] && { sudo ln -s /usr/bin/batcat /usr/bin/bat; }
    
    # GEF
    if [ ! -f "$USER_HOME/.gdbinit-gef.py" ]; then
        sudo -u "$CURRENT_USER" bash -c "$(curl -fsSL https://gef.blah.cat/sh)"
        SUCCEEDED_PACKAGES+=("gef")
    else
        SKIPPED_PACKAGES+=("gef")
    fi
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    echo "=========================================="
    echo "  Essential's Pack - WSL Setup v5.2"
    echo "=========================================="
    echo ""
    
    check_json_file
    
    # Update system
    echo "=========================================="
    echo "  Updating System"
    echo "=========================================="
    sudo apt-get update
    sudo apt-get upgrade -y
    
    # Execution
    install_apt_packages
    install_snap_packages
    install_rust
    install_dotnet
    install_sdkman
    install_nvm
    install_python_managers
    install_rbenv
    install_docker
    install_cloud_tools
    install_go_tools
    install_pip_tools
    clone_git_repos
    install_cloned_repos
    install_radare2
    setup_oh_my_zsh
    install_starship
    configure_shell
    install_language_versions
    install_misc_tools
    
    # Cleanup
    echo "=========================================="
    echo "  Cleaning up APT cache"
    echo "=========================================="
    sudo apt-get autoremove -y
    sudo apt-get clean
    
    # Report & Log
    write_install_summary
    
    echo ""
    echo "=========================================="
    echo "  WSL (UBUNTU) SETUP V5.2 COMPLETE!"
    echo "=========================================="
    echo ""
    echo -e "\033[1;33mIMPORTANT:\033[0m"
    echo "1. Please close and reopen your Ubuntu terminal."
    echo "2. Run 'source ~/.zshrc' to load all changes."
    echo "3. MobSF is installed at ~/tools/mobsf. Run '~/tools/mobsf/run.sh' to start it."
    echo ""
}

main
```
