#!/bin/bash
set -e
cd "$(dirname "$0")"

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

if [ "$EUID" -ne 0 ]; then
  echo "Пожалуйста, запускайте скрипт с sudo."
  exit 1
fi

REPO_URL="https://github.com/OnisOris/pion_camera"
REPO_NAME="pion_camera"

REAL_USER=$(logname)
REAL_HOME=$(eval echo "~$REAL_USER")
REAL_PATH="$REAL_HOME/.local/bin:$PATH"

INSTALL_DIR="$REAL_HOME/$REPO_NAME"
VENV_DIR="$INSTALL_DIR/.venv"
UV_BIN="$REAL_HOME/.local/bin/uv"

JSTREAMER_RUN="/usr/local/bin/jstreamer-run.sh"
CAMERA_RUN="/usr/local/bin/pion-camera-run.sh"

# --- Функции ---
install_pkg() {
  local pkg="$1"
  if dpkg -s "$pkg" &>/dev/null; then
    echo "✅ $pkg уже установлен."
  else
    echo "🔧 Устанавливаем $pkg..."
    apt-get update -y
    apt-get install -y "$pkg"
  fi
}

install_pkg curl
install_pkg git
install_pkg python3-dev

echo "Пользователь: $REAL_USER"
echo "Домашняя директория: $REAL_HOME"

GST_PKGS=(
  libgstreamer1.0-dev
  libgstreamer-plugins-base1.0-dev
  libgstreamer-plugins-bad1.0-dev
  gstreamer1.0-plugins-base
  gstreamer1.0-plugins-good
  gstreamer1.0-plugins-bad
  gstreamer1.0-plugins-ugly
  gstreamer1.0-libav
  gstreamer1.0-tools
  gstreamer1.0-x
  gstreamer1.0-alsa
  gstreamer1.0-gl
  gstreamer1.0-gtk3
  gstreamer1.0-qt5
  gstreamer1.0-pulseaudio
)

echo "🔎 Проверяем наличие jstreamer (gst-launch-1.0)..."
if sudo -u "$REAL_USER" env PATH="$REAL_PATH" bash -c 'command -v gst-launch-1.0 &>/dev/null'; then
  echo "✅ gst-launch-1.0 найден — GStreamer установлен."
else
  echo "📦 Устанавливаем пакеты GStreamer (jstreamer)..."
  apt-get update -y
  apt-get install -y "${GST_PKGS[@]}"
fi

if sudo -u "$REAL_USER" env PATH="$REAL_PATH" bash -c 'command -v uv &>/dev/null'; then
  echo "✅ uv уже установлен."
else
  echo "🔧 Устанавливаю uv..."
  sudo -u "$REAL_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
fi

echo "🔒 Добавляем $INSTALL_DIR в безопасные директории Git..."
sudo -u "$REAL_USER" git config --global --add safe.directory "$INSTALL_DIR" || true

if [ -d "$INSTALL_DIR/.git" ]; then
  echo "🔄 Обновляем существующий репозиторий..."
  cd "$INSTALL_DIR"
  sudo -u "$REAL_USER" git reset --hard
  sudo -u "$REAL_USER" git clean -fd
  sudo -u "$REAL_USER" git checkout main || sudo -u "$REAL_USER" git checkout -B main
  sudo -u "$REAL_USER" git pull --rebase
  chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR"
  cd -
else
  echo "⏬ Клонируем репозиторий..."
  sudo -u "$REAL_USER" git clone "$REPO_URL" "$INSTALL_DIR"
  chown -R "$REAL_USER:$REAL_USER" "$INSTALL_DIR"
fi

# --- Создание venv на Python 3.13 через uv ---
if [ -d "$VENV_DIR" ]; then
  echo "🗑️ Удаляем старое виртуальное окружение..."
  rm -rf "$VENV_DIR"
fi

mkdir -p "$VENV_DIR"
chown -R "$REAL_USER:$REAL_USER" "$VENV_DIR"

echo "🐍 Создаём uv venv (Python 3.13)..."
sudo -u "$REAL_USER" env PATH="$REAL_PATH" bash -c "\"$UV_BIN\" venv --python 3.13 \"$VENV_DIR\""

# --- Установка проекта в venv ---
echo "📦 Устанавливаем pion_camera в venv (editable)..."
sudo -u "$REAL_USER" env PATH="$REAL_PATH" bash -c "source \"$VENV_DIR/bin/activate\" && \"$UV_BIN\" pip install -U pip setuptools wheel && \"$UV_BIN\" pip install -e \"$INSTALL_DIR\""

# --- Скрипт запуска jstreamer ---
echo "📝 Создаём скрипт запуска jstreamer: $JSTREAMER_RUN"
cat > "$JSTREAMER_RUN" << 'EOF'
#!/bin/bash
set -e
exec gst-launch-1.0 udpsrc port=9000 caps=application/x-rtp ! queue ! rtph264depay ! h264parse ! avdec_h264 ! videoconvert ! queue ! autovideosink sync=false
EOF
chmod +x "$JSTREAMER_RUN"

# --- Скрипт запуска Python-сервера (опционально; можно вызывать бинарь прямо) ---
echo "📝 Создаём скрипт запуска сервера камеры: $CAMERA_RUN"
cat > "$CAMERA_RUN" << EOF
#!/bin/bash
set -e
cd "$INSTALL_DIR"
exec "$VENV_DIR/bin/start_server_radxa"
EOF
chmod +x "$CAMERA_RUN"

# --- systemd unit: jstreamer.service ---
echo "⚙️ Создаём systemd unit /etc/systemd/system/jstreamer.service..."
cat > /etc/systemd/system/jstreamer.service << EOF
[Unit]
Description=JStreamer (GStreamer UDP H264 viewer)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$JSTREAMER_RUN
Restart=always
RestartSec=3
User=$REAL_USER
StandardOutput=journal
StandardError=journal
WorkingDirectory=$REAL_HOME

[Install]
WantedBy=multi-user.target
EOF

# --- systemd unit: pion-camera.service ---
echo "⚙️ Создаём systemd unit /etc/systemd/system/pion-camera.service..."
cat > /etc/systemd/system/pion-camera.service << EOF
[Unit]
Description=Pion Camera Python Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$CAMERA_RUN
Restart=always
RestartSec=3
User=$REAL_USER
StandardOutput=journal
StandardError=journal
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$VENV_DIR/bin:$REAL_PATH

[Install]
WantedBy=multi-user.target
EOF

# --- Перезапуск systemd и запуск сервисов ---
echo "🔄 Перезагружаем systemd и запускаем сервисы..."
systemctl daemon-reload
systemctl enable jstreamer.service
systemctl enable pion-camera.service
systemctl restart jstreamer.service
systemctl restart pion-camera.service

echo "✅ Установка завершена."
echo "ℹ️ Проверка статуса:"
echo "   systemctl status jstreamer.service"
echo "   systemctl status pion-camera.service"

