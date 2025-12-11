#!/bin/bash
set -e

# --- Variáveis ---
CURRENT_USER="$(whoami)"
USER_HOME="/home/$CURRENT_USER"
ZSHRC_PATH="$USER_HOME/.zshrc"
ZSH_CUSTOM="$USER_HOME/.oh-my-zsh/custom"

echo "=========================================="
echo "  INICIANDO INSTALAÇÃO VISUAL (RECOMENDADA)"
echo "=========================================="

# 1. Instalar dependências básicas de visual e Zsh
echo ">>> Instalando pacotes base (zsh, eza, bat, fontes)..."
sudo apt-get update
sudo apt-get install -y zsh curl git fonts-powerline eza bat zoxide fzf

# 2. Corrigir link do 'bat' (no Ubuntu ele chama batcat)
if [ ! -L /usr/bin/bat ]; then
    echo ">>> Criando link simbólico para 'bat'..."
    sudo ln -s /usr/bin/batcat /usr/bin/bat || true
fi

# 3. Instalar Oh My Zsh (se não existir)
if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
    echo ">>> Instalando Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo ">>> Oh My Zsh já instalado."
fi

# 4. Instalar Plugins do Zsh (Autosuggestions, Syntax Highlighting, Completions)
echo ">>> Instalando plugins do Zsh..."
mkdir -p "$ZSH_CUSTOM/plugins"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-completions" ]; then
    git clone https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM/plugins/zsh-completions"
fi

# 5. Instalar Tema Powerlevel10k
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
    echo ">>> Instalando tema Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
fi

# 6. Instalar Starship (Prompt Moderno)
if ! command -v starship &> /dev/null; then
    echo ">>> Instalando Starship..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
else
    echo ">>> Starship já instalado."
fi

# 7. Configurar o .zshrc
echo ">>> Configurando o arquivo .zshrc..."

# Backup do antigo
cp "$ZSHRC_PATH" "$ZSHRC_PATH.backup.$(date +%s)"

# Aplica configurações (Ativa plugins e tema P10k)
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' "$ZSHRC_PATH"
sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC_PATH"

# Adiciona Aliases e Inicializadores se não existirem
if ! grep -q "### VISUAL PACK ###" "$ZSHRC_PATH"; then
    cat << 'EOF' >> "$ZSHRC_PATH"

### VISUAL PACK ###
# Aliases Modernos
alias ls='eza --icons --git'
alias ll='eza -l --icons --git --all'
alias lt='eza -T'
alias cat='bat'
alias open='xdg-open .'

# Inicializadores
eval "$(zoxide init zsh)"
if command -v starship 1>/dev/null 2>&1; then eval "$(starship init zsh)"; fi
EOF
fi

# 8. Definir Zsh como padrão
if [ "$SHELL" != "$(which zsh)" ]; then
    echo ">>> Definindo Zsh como shell padrão..."
    sudo chsh -s "$(which zsh)" "$CURRENT_USER"
fi

echo ""
echo "=========================================="
echo "  INSTALAÇÃO VISUAL CONCLUÍDA!"
echo "=========================================="
echo "1. Feche este terminal e abra um novo."
echo "2. Se aparecer a configuração do Powerlevel10k, siga as instruções na tela."
echo "3. Lembre-se de configurar a fonte MesloLGS NF nas preferências do seu terminal."
