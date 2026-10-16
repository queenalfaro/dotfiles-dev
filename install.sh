#!/usr/bin/env bash
set -e

echo "--------------------------------------------------------"
echo "🚀 [DOTFILES] Настройка персонального окружения..."
echo "--------------------------------------------------------"

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_PI_DIR="$HOME/.pi/agent"
LOCAL_BIN="$HOME/.local/bin"
mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

# Определение архитектуры процессора (x86_64 или arm64/Apple Silicon)
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64)
    OP_ARCH="amd64"
    NODE_ARCH="x64"
    ;;
  aarch64|arm64)
    OP_ARCH="arm64"
    NODE_ARCH="arm64"
    ;;
  *)
    echo "Неподдерживаемая архитектура: $ARCH"
    exit 1
    ;;
esac

# 1. Установка 1Password CLI (если не установлен)
if ! command -v op &> /dev/null; then
    echo "📦 [DOTFILES] Установка 1Password CLI (${OP_ARCH})..."
    OP_VERSION="v2.30.0"
    curl -fsSL "https://cache.agilebits.com/dist/1P/op2/pkg/${OP_VERSION}/op_linux_${OP_ARCH}_${OP_VERSION}.zip" -o /tmp/op.zip
    unzip -o /tmp/op.zip op -d "$LOCAL_BIN" > /dev/null
    chmod +x "$LOCAL_BIN/op"
    rm -f /tmp/op.zip
fi

# 2. Проверка и установка Node.js 22+ (необходим для Pi Coding Agent)
NEED_NODE=false
if ! command -v node &> /dev/null; then
    NEED_NODE=true
else
    NODE_MAJOR="$(node -v | cut -d'.' -f1 | tr -d 'v')"
    if [ "$NODE_MAJOR" -lt 22 ]; then
        NEED_NODE=true
    fi
fi

if [ "$NEED_NODE" = true ]; then
    echo "📦 [DOTFILES] Установка автономного Node.js (v22.x)..."
    NODE_DIR="$HOME/.local/node"
    mkdir -p "$NODE_DIR"
    curl -fsSL "https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt" -o /tmp/node-shasums.txt
    NODE_FILE=$(awk -v suffix="-linux-${NODE_ARCH}.tar.xz" '$2 ~ suffix { print $2; exit }' /tmp/node-shasums.txt)
    rm -f /tmp/node-shasums.txt
    if [ -n "$NODE_FILE" ]; then
        curl -fsSL "https://nodejs.org/dist/latest-v22.x/${NODE_FILE}" -o "/tmp/${NODE_FILE}"
        tar -xf "/tmp/${NODE_FILE}" -C "$NODE_DIR" --strip-components=1
        rm -f "/tmp/${NODE_FILE}"
        ln -sf "$NODE_DIR/bin/"* "$LOCAL_BIN/"
        export PATH="$NODE_DIR/bin:$PATH"
    else
        echo "⚠️  [DOTFILES] Не удалось определить архив Node.js"
    fi
fi

# 3. Установка Pi Coding Agent (если не установлен)
if ! command -v pi &> /dev/null; then
    echo "🤖 [DOTFILES] Установка Pi Coding Agent..."
    curl -fsSL https://pi.dev/install.sh | sh
fi

export PATH="$LOCAL_BIN:$HOME/.local/node/bin:$HOME/.pi/bin:$PATH"

# 4. Подготовка директорий и линковка скилов
echo "🔗 [DOTFILES] Линковка настроек и скилов Pi..."
mkdir -p "$TARGET_PI_DIR"

# Симлинк для settings.json
if [ -f "$DOTFILES_DIR/.pi/agent/settings.json" ]; then
    ln -sf "$DOTFILES_DIR/.pi/agent/settings.json" "$TARGET_PI_DIR/settings.json"
fi

# Симлинк для models.json (кастомные LLM провайдеры)
if [ -f "$DOTFILES_DIR/.pi/agent/models.json" ]; then
    ln -sf "$DOTFILES_DIR/.pi/agent/models.json" "$TARGET_PI_DIR/models.json"
fi

# Симлинк для папки со скилами
if [ -d "$DOTFILES_DIR/.pi/agent/skills" ]; then
    rm -rf "$TARGET_PI_DIR/skills"
    ln -s "$DOTFILES_DIR/.pi/agent/skills" "$TARGET_PI_DIR/skills"
fi

# 5. Получение секретов из 1Password
if [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    echo "🔐 [DOTFILES] Получение ключей провайдеров из 1Password..."
    ITEM_JSON=$(op item get Pi-Agent --vault Dev --format json 2>/dev/null || true)
    if [ -n "$ITEM_JSON" ]; then
        echo "$ITEM_JSON" | jq '
          [ .fields[]? 
            | select(.label != null and .value != null and .value != "" and .label != "notesPlain" and .label != "notes")
            | if .label == "auth_json" and (.value | startswith("{")) then
                (.value | fromjson | to_entries[])
              else
                { key: .label, value: { type: "api_key", key: .value } }
              end
          ] | from_entries
        ' > "$TARGET_PI_DIR/auth.json"
        chmod 600 "$TARGET_PI_DIR/auth.json"
        echo "✅ [DOTFILES] Ключи успешно записаны в auth.json!"
    else
        echo "⚠️  [DOTFILES] Не удалось получить данные из заметки Pi-Agent в 1Password"
    fi
else
    echo "⚠️  [DOTFILES] Переменная OP_SERVICE_ACCOUNT_TOKEN не найдена. Пропуск авторизации."
fi

# 6. Прописываем пути в PATH шелла контейнера
ENV_PATH_LINE='export PATH="$HOME/.local/bin:$HOME/.local/node/bin:$HOME/.pi/bin:$PATH"'
for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ]; then
        grep -qxF "$ENV_PATH_LINE" "$rc" || echo "$ENV_PATH_LINE" >> "$rc"
    fi
done

echo "--------------------------------------------------------"
echo "✨ [DOTFILES] Окружение полностью готово к работе!"
echo "--------------------------------------------------------"