#!/usr/bin/env bash
set -e

echo "--------------------------------------------------------"
echo "🚀 [DOTFILES] Настройка персонального окружения..."
echo "--------------------------------------------------------"

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_PI_DIR="$HOME/.pi/agent"

# Определение архитектуры процессора (x86_64 или arm64/Apple Silicon)
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) OP_ARCH="amd64" ;;
  aarch64|arm64) OP_ARCH="arm64" ;;
  *) echo "Неподдерживаемая архитектура: $ARCH"; exit 1 ;;
esac

# 1. Установка 1Password CLI (если не установлен)
if ! command -v op &> /dev/null; then
    echo "📦 [DOTFILES] Установка 1Password CLI (${OP_ARCH})..."
    curl -sS "https://downloads.1password.com/linux/tar/stable/${OP_ARCH}/op-linux-${OP_ARCH}-v2.30.0.tar.gz" -o /tmp/op.tar.gz
    # Распаковываем в ~/.local/bin (не требует прав sudo)
    mkdir -p "$HOME/.local/bin"
    tar -xzf /tmp/op.tar.gz -C "$HOME/.local/bin"
    rm /tmp/op.tar.gz
    export PATH="$HOME/.local/bin:$PATH"
fi

# 2. Установка Pi Coding Agent (если не установлен)
if ! command -v pi &> /dev/null; then
    echo "🤖 [DOTFILES] Установка Pi Coding Agent..."
    curl -fsSL https://pi.dev/install.sh | sh
    export PATH="$HOME/.local/bin:$HOME/.pi/bin:$PATH"
fi

# 3. Подготовка директорий и линковка скилов
echo "🔗 [DOTFILES] Линковка настроек и скилов Pi..."
mkdir -p "$TARGET_PI_DIR"

# Симлинк для settings.json
if [ -f "$DOTFILES_DIR/.pi/agent/settings.json" ]; then
    ln -sf "$DOTFILES_DIR/.pi/agent/settings.json" "$TARGET_PI_DIR/settings.json"
fi

# Симлинк для папки со скилами
if [ -d "$DOTFILES_DIR/.pi/agent/skills" ]; then
    rm -rf "$TARGET_PI_DIR/skills"
    ln -s "$DOTFILES_DIR/.pi/agent/skills" "$TARGET_PI_DIR/skills"
fi

# 4. Получение секретов из 1Password
if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    echo "🔐 [DOTFILES] Получение токенов Pi из 1Password..."
    # Читаем auth.json из нашего сейфа Dev и заметки Pi-Agent
    op read "op://Dev/Pi-Agent/auth_json" > "$TARGET_PI_DIR/auth.json"
    chmod 600 "$TARGET_PI_DIR/auth.json"
    echo "✅ [DOTFILES] Токены успешно записаны в auth.json!"
else
    echo "⚠️  [DOTFILES] Переменная OP_SERVICE_ACCOUNT_TOKEN не найдена. Пропуск авторизации."
fi

# 5. Прописываем ~/.local/bin в PATH шелла контейнера
if [ -f "$HOME/.bashrc" ]; then
    grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
if [ -f "$HOME/.zshrc" ]; then
    grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
fi

echo "--------------------------------------------------------"
echo "✨ [DOTFILES] Окружение полностью готово к работе!"
echo "--------------------------------------------------------"