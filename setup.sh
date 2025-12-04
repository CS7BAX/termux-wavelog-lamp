#!/bin/bash

export DEBIAN_FRONTEND=noninteractive

ok()   { echo -e "\033[1;32m[OK]\033[0m $1"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $1"; }
err()  { echo -e "\033[1;31m[ERR]\033[0m $1"; }

# --- Check installed packages ---
check_installed() {
    if dpkg -l | grep -q "$1"; then
        ok "$1 installed."
    else
        warn "$1 NOT installed."
    fi
}

# --- Check generic services ---
check_service() {
    if pgrep -f "$1" > /dev/null; then
        ok "Service $1 running."
    else
        warn "Service $1 NOT running."
    fi
}

# --- Specific check for MariaDB ---
check_service_mariadb() {
    if pgrep -f "mariadbd" > /dev/null || pgrep -f "mysqld" > /dev/null; then
        ok "MariaDB running."
    else
        warn "MariaDB NOT running."
    fi
}

# --- Install optimized LAMP stack ---
install_lamp() {
    echo "[+] Updating packages..."
    apt update && apt upgrade -y

    echo "[+] Installing dependencies..."
    apt install -y apt-transport-https lsb-release ca-certificates wget gnupg2 curl nano unzip git net-tools

    echo "[+] Adding sury.org repository..."
    wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    apt update

    echo "[+] Installing Apache, PHP 8.2 and modules..."
    apt install -y apache2 libapache2-mod-php8.2 php8.2 php8.2-cli php8.2-common \
        php8.2-mysql php8.2-curl php8.2-xml php8.2-mbstring php8.2-zip php8.2-gd

    echo "[+] Installing MariaDB..."
    apt install -y mariadb-server mariadb-client

    echo "[+] Adjusting Apache to port 8080..."
    sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf
    sed -i 's/<VirtualHost \*:80>/<VirtualHost \*:8080>/' /etc/apache2/sites-available/000-default.conf

    echo "[+] Enabling Apache modules..."
    a2enmod deflate expires headers rewrite
    a2dismod mpm_event || true
    a2enmod mpm_prefork
    a2enmod php8.2

    echo "[+] Adjusting KeepAlive..."
    sed -i 's/^KeepAlive .*/KeepAlive On/' /etc/apache2/apache2.conf
    sed -i 's/^MaxKeepAliveRequests .*/MaxKeepAliveRequests 100/' /etc/apache2/apache2.conf
    sed -i 's/^KeepAliveTimeout .*/KeepAliveTimeout 2/' /etc/apache2/apache2.conf

    echo "[+] Enabling opcache and tuning PHP limits..."
    PHP_INI="/etc/php/8.2/apache2/php.ini"
    sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "$PHP_INI"
    sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=256/' "$PHP_INI"
    sed -i 's/^;opcache.interned_strings_buffer=.*/opcache.interned_strings_buffer=16/' "$PHP_INI"
    sed -i 's/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=10000/' "$PHP_INI"
    sed -i 's/^;opcache.revalidate_freq=.*/opcache.revalidate_freq=2/' "$PHP_INI"

    sed -i 's/^max_execution_time = .*/max_execution_time = 600/' "$PHP_INI"
    sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/' "$PHP_INI"
    sed -i 's/^post_max_size = .*/post_max_size = 64M/' "$PHP_INI"
    sed -i 's/^memory_limit = .*/memory_limit = 512M/' "$PHP_INI"

    echo "[+] Optimized MariaDB configuration..."
    cat > /etc/mysql/mariadb.conf.d/99-custom.cnf <<EOF
[mysqld]
skip-networking=0
bind-address=127.0.0.1
innodb_buffer_pool_size=512M
innodb_log_file_size=128M
max_connections=100
query_cache_size=64M
query_cache_type=1
slow_query_log=1
slow_query_log_file=/var/log/mysql/slow.log
long_query_time=2
log_error=/var/log/mysql/error.log
EOF

    echo "<?php phpinfo(); ?>" > /var/www/html/index.php

    mkdir -p /root
    create_aux_scripts

    ok "Installation complete. Apache listening on port 8080 with optimizations."
    echo "-> Test at http://localhost:8080"
}

# --- Create auxiliary scripts ---
create_aux_scripts() {
    echo "[+] Creating auxiliary scripts (cron.sh, start.sh, stop.sh) in /root..."

    # cron.sh (watchdog)
    cat > /root/cron.sh <<'EOF'
#!/bin/bash
LOCKFILE=/tmp/wavelog-cron.lock
exec 200>$LOCKFILE
flock -n 200 || exit 1

HOST="127.0.0.1"
PORT=8080
BASE_URL="http://$HOST:$PORT"

LOGFILE=/var/log/wavelog-cron.log
MAXSIZE=10485760 # 10 MB

mkdir -p /var/log
touch "$LOGFILE"

rotate_log() {
    TS=$(date +%s)
    if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE") -gt $MAXSIZE ]; then
        mv "$LOGFILE" "$LOGFILE.$TS.bak"
        gzip "$LOGFILE.$TS.bak" 2>/dev/null || true
    fi
}

classify_code() {
    local CODE=$1
    if [ "$CODE" -eq 200 ]; then
        echo "OK"
    elif [ "$CODE" -ge 300 ] && [ "$CODE" -lt 400 ]; then
        echo "Redirect"
    elif [ "$CODE" -ge 400 ] && [ "$CODE" -lt 500 ]; then
        echo "Client Error"
    elif [ "$CODE" -ge 500 ]; then
        echo "Server Error"
    else
        echo "Unknown"
    fi
}

try_curl() {
    local URL=$1
    local CODE=000
    for i in {1..3}; do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" -A "Wavelog Watchdog" "$URL")
        [ "$CODE" -ne 000 ] && break
        sleep 2
    done
    echo $CODE
}

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    CODE_RUN=$(try_curl "$BASE_URL/index.php/cron/run")
    STATUS_RUN=$(classify_code $CODE_RUN)

    rotate_log
    echo "[$TIMESTAMP] watchdog -> /cron/run -> HTTP $CODE_RUN ($STATUS_RUN)" >> $LOGFILE

    if [ "$CODE_RUN" -ne 200 ]; then
        CODE_CRON=$(try_curl "$BASE_URL/index.php/cron")
        STATUS_CRON=$(classify_code $CODE_CRON)

        rotate_log
        echo "[$TIMESTAMP] watchdog -> /cron -> HTTP $CODE_CRON ($STATUS_CRON)" >> $LOGFILE
    fi

    if [ "$CODE_RUN" -eq 000 ] || [ "$CODE_CRON" -eq 000 ]; then
        echo "[$TIMESTAMP] [RECOVERY] Failure detected, attempting to restart services..." >> $LOGFILE

        if command -v apachectl >/dev/null; then
            apachectl restart >> $LOGFILE 2>&1
        elif command -v service >/dev/null; then
            service apache2 restart >> $LOGFILE 2>&1
        else
            echo "[$TIMESTAMP] [ERROR] Apache restart command not found" >> $LOGFILE
        fi

	if command -v mysqld_safe >/dev/null; then
        mkdir -p /var/run/mysqld
        chown mysql:mysql /var/run/mysqld 2>/dev/null || true
        nohup mysqld_safe --datadir=/var/lib/mysql \
                          --socket=/var/run/mysqld/mysqld.sock \
                          --log-error=/var/log/mysql/error.log \
                          --skip-syslog >> "$LOGFILE" 2>&1 &
        else
        echo "[$TIMESTAMP] [ERROR] mysqld_safe not found" >> "$LOGFILE"
        
        fi

        sleep 5

        # Post-restart verification
        if ! pgrep -x apache2 >/dev/null; then
            echo "[$TIMESTAMP] [ERROR] Apache did not start" >> $LOGFILE
        fi
        if ! pgrep -x mysqld >/dev/null; then
            echo "[$TIMESTAMP] [ERROR] MariaDB did not start" >> $LOGFILE
        fi
    fi

    sleep 30
done
EOF
    chmod +x /root/cron.sh


    # start.sh
    cat > /root/start.sh <<'EOF'
#!/bin/bash
echo "[+] Starting Apache, MariaDB and watchdog..."
apachectl start
mkdir -p /var/run/mysqld /var/log/mysql
chown -R mysql:mysql /var/run/mysqld /var/log/mysql /var/lib/mysql
rm -f /var/run/mysqld/mysqld.sock
pkill -9 mysqld || true
pkill -9 mariadbd || true
pkill -9 mysqld_safe || true
mysqld_safe --datadir=/var/lib/mysql --socket=/var/run/mysqld/mysqld.sock --log-error=/var/log/mysql/error.log --skip-syslog &
sleep 2
nohup /root/cron.sh &
echo "[OK] Services started."
EOF
    chmod +x /root/start.sh

    # stop.sh
    cat > /root/stop.sh <<'EOF'
#!/bin/bash
echo "[+] Stopping Apache, MariaDB and watchdog..."
apachectl stop
pkill -9 mysqld || true
pkill -9 mariadbd || true
pkill -9 mysqld_safe || true
pkill -f /root/cron.sh || true
echo "[OK] Services stopped."
EOF
    chmod +x /root/stop.sh

    ok "Auxiliary scripts created in /root/"
}

# --- Download Wavelog ---
download_wavelog() {
    echo "[+] Downloading Wavelog..."
    cd /var/www/html || { err "Directory /var/www/html not found"; return; }

    rm -rf /var/www/html/*

    git clone https://github.com/wavelog/wavelog.git /var/www/html

    chown -R www-data:www-data /var/www/html
    chmod -R 755 /var/www/html

    ok "Wavelog downloaded into /var/www/html"
    echo "[+] Access via http://<IP>:8080 to configure."
}

# --- Fix base_url in config.php ---
fix_ip() {
    echo "[+] Fixing base_url in config.php..."
    CONFIG_FILE="/var/www/html/application/config/config.php"
    BACKUP_FILE="${CONFIG_FILE}.bak"

    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"

        # MESMA linha que funciona na linha de comando
        if sed -i "s|^\$config\['base_url'\].*|\$config['base_url'] = 'http://' . \$_SERVER['SERVER_NAME'] . ':' . \$_SERVER['SERVER_PORT'] . '/';|" "$CONFIG_FILE"; then
            # Verifica se a linha esperada está mesmo escrita
            if grep -q "=\s*'http://' . \$_SERVER\['SERVER_NAME'\] . ':' . \$_SERVER\['SERVER_PORT'\] . '/';" "$CONFIG_FILE"; then
                ok "base_url updated with SERVER_NAME + SERVER_PORT"
            else
                err "Pattern not found after sed. Restoring backup..."
                cp "$BACKUP_FILE" "$CONFIG_FILE"
            fi
        else
            err "sed failed. Restoring backup..."
            cp "$BACKUP_FILE" "$CONFIG_FILE"
        fi
    else
        err "File config.php not found at $CONFIG_FILE"
    fi
}


# --- Create database ---
create_db() {
    echo "[+] Creating database and user..."
    mysql -u root <<EOF
DROP DATABASE IF EXISTS wavelog;
CREATE DATABASE wavelog CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS 'wavelog'@'localhost';
CREATE USER 'wavelog'@'localhost' IDENTIFIED BY 'wavelog';
GRANT ALL PRIVILEGES ON wavelog.* TO 'wavelog'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF
    ok "Database and user created."
}

# --- Start services ---
start_services() {
    echo "[+] Starting Apache and MariaDB..."
    apachectl start
    mkdir -p /var/run/mysqld /var/log/mysql
    chown -R mysql:mysql /var/run/mysqld /var/log/mysql /var/lib/mysql
    rm -f /var/run/mysqld/mysqld.sock
    pkill -9 mysqld || true
    pkill -9 mariadbd || true
    pkill -9 mysqld_safe || true
    mysqld_safe --datadir=/var/lib/mysql \
                --socket=/var/run/mysqld/mysqld.sock \
                --log-error=/var/log/mysql/error.log \
                --skip-syslog &
    echo "[...] Waiting for MariaDB to start (up to 20s)..."
    for i in {1..10}; do
        sleep 2
        if [ -S /var/run/mysqld/mysqld.sock ]; then
            ok "MariaDB started and socket available."
            start_watchdog
            return
        fi
    done
    warn "MariaDB did not start. Check /var/log/mysql/error.log"
}

# --- Stop services ---
stop_services() {
    echo "[+] Stopping Apache, MariaDB and watchdog..."

    # Apache: desligar de forma limpa
    apachectl -k graceful-stop 2>/dev/null || apachectl stop 2>/dev/null || true

    # MariaDB: desligar de forma limpa
    mysqladmin -u root shutdown 2>/dev/null || \
    service mariadb stop 2>/dev/null || \
    service mysql stop 2>/dev/null || true

    # Watchdog
    pkill -f /root/cron.sh >/dev/null 2>&1 || true

    # Espera um pouco para tudo desligar
    sleep 3

    # Último recurso: matar processos teimosos
    pkill -9 mysqld >/dev/null 2>&1 || true
    pkill -9 mariadbd >/dev/null 2>&1 || true
    pkill -9 mysqld_safe >/dev/null 2>&1 || true

    # Verificação final
    if pgrep -x apache2 >/dev/null || pgrep -x mysqld >/dev/null || pgrep -x mariadbd >/dev/null; then
        warn "Some services are still running."
    else
        ok "All services stopped."
    fi
}



# --- Watchdog control ---
start_watchdog() {
    echo "[+] Starting WaveLog watchdog..."
    nohup /root/cron.sh >/dev/null 2>&1 </dev/null &
    ok "Watchdog started (runs every 30s on 127.0.0.1:8080)."
}

stop_watchdog() {
    echo "[+] Stopping WaveLog watchdog..."
    pkill -f /root/cron.sh || true
    ok "Watchdog stopped."
}

# --- Status check ---
status_services() {
    echo "[+] Checking service status..."
    check_service apache2
    check_service_mariadb
    if pgrep -f "/root/cron.sh" > /dev/null; then
        ok "WaveLog watchdog is running."
    else
        warn "WaveLog watchdog is NOT running."
    fi
}

# --- Check MariaDB socket ---
check_socket() {
    echo "[+] Checking MariaDB socket..."
    if [ -S /var/run/mysqld/mysqld.sock ]; then
        ok "MariaDB socket found at /var/run/mysqld/mysqld.sock"
    else
        warn "MariaDB socket not found."
    fi
}

# --- Show MariaDB logs ---
show_logs() {
    echo "[+] Last 20 MariaDB errors:"
    if [ -f /var/log/mysql/error.log ]; then
        tail -n 20 /var/log/mysql/error.log
    else
        warn "Log file not found /var/log/mysql/error.log"
    fi
}

# --- Install Adminer ---
install_adminer() {
    echo "[+] Installing Adminer..."
    mkdir -p /var/www/html/adminer
    cd /var/www/html/adminer || { err "Directory /var/www/html/adminer not found"; return; }

    # Download last Adminer (PHP file)
    wget -O index.php https://www.adminer.org/latest.php || {
        err "Failed to download Adminer"
        return
    }

    chown -R www-data:www-data /var/www/html/adminer
    chmod -R 755 /var/www/html/adminer

    ok "Adminer installed. Access: http://<IP>:8080/adminer/"
}

# --- Install phpSysInfo ---
install_phpsysinfo() {
    echo "[+] Installing phpSysInfo..."
    cd /var/www/html || { err "Directory /var/www/html not found"; return; }

    # Remove instalação antiga
    rm -rf phpsysinfo

    # Download da versão principal
    wget https://github.com/phpsysinfo/phpsysinfo/archive/master.zip -O phpsysinfo.zip || {
        err "Failed to download phpSysInfo"
        return
    }

    unzip -q phpsysinfo.zip
    rm phpsysinfo.zip

    # Descobrir o diretório extraído (phpsysinfo-qualquercoisa)
    EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "phpsysinfo-*" | head -n 1)

    if [ -z "$EXTRACTED_DIR" ]; then
        err "Could not find extracted phpSysInfo directory"
        return
    fi

    mv "$EXTRACTED_DIR" phpsysinfo

    # Copiar config de exemplo
    if [ -f phpsysinfo/phpsysinfo.ini.new ]; then
        cp phpsysinfo/phpsysinfo.ini.new phpsysinfo/phpsysinfo.ini
    elif [ -f phpsysinfo/phpsysinfo.ini.new.php ]; then
        cp phpsysinfo/phpsysinfo.ini.new.php phpsysinfo/phpsysinfo.ini
    fi

    chown -R www-data:www-data phpsysinfo
    chmod -R 755 phpsysinfo

    ok "phpSysInfo installed. Access: http://<IP>:8080/phpsysinfo/"
}


# --- Create Termux launcher script ---
create_termux_launcher() {
    echo "[+] Creating Termux launcher command (wave)..."

    TERMUX_BIN="/data/data/com.termux/files/usr/bin"
    LAUNCHER="$TERMUX_BIN/wave"

    if [ ! -d "$TERMUX_BIN" ]; then
        warn "Termux bin ($TERMUX_BIN) not found. Are you running inside Termux?"
        return
    fi

    cat > "$LAUNCHER" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Keep device awake
termux-wake-lock || true

# Atualizar IP (se existir helper)
if [ -x "$HOME/wavelog-ip.sh" ]; then
    "$HOME/wavelog-ip.sh"
fi

# Comando a correr dentro do Debian
DEBIAN_CMD="cd /root && ./setup.sh"

# Correr dentro/fóra de tmux
if [ -t 0 ] && [ -t 1 ]; then
    if command -v tmux >/dev/null 2>&1; then
        if [ -n "$TMUX" ]; then
            exec proot-distro login debian -- bash -lc "$DEBIAN_CMD"
        else
            exec tmux new-session -A -s wavelog "proot-distro login debian -- bash -lc '$DEBIAN_CMD'"
        fi
    else
        echo "[WARN] tmux not installed. Running without tmux."
        exec proot-distro login debian -- bash -lc "$DEBIAN_CMD"
    fi
else
    exec proot-distro login debian -- bash -lc "$DEBIAN_CMD"
fi

# Libertar wakelock ao sair
termux-wake-unlock || true
EOF

    chmod +x "$LAUNCHER"
    ok "Launcher created as 'wave' (run it from Termux with: wave)."
}




# --- Create Termux IP helper script ---
create_wavelog_ip_script() {
    echo "[+] Creating Termux IP helper script (wavelog-ip.sh)..."

    TERMUX_HOME="/data/data/com.termux/files/home"
    SCRIPT="$TERMUX_HOME/wavelog-ip.sh"

    if [ ! -d "$TERMUX_HOME" ]; then
        warn "Termux home ($TERMUX_HOME) not found. Are you running inside Termux/proot-distro?"
        return
    fi

    cat > "$SCRIPT" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash

OUT="$HOME/wavelog_ip.txt"

# Limpa ficheiro
> "$OUT"

LAST_IP=""

# Apanha todos os IPv4 não‑loopback do ifconfig
for IP in $(ifconfig 2>/dev/null \
              | awk '/inet / && $2 != "127.0.0.1" {print $2}'); do
    # Primeiro octeto (antes do ponto)
    FIRST_OCTET=${IP%%.*}

    # Ignora 100, 110 e 111
    if [ "$FIRST_OCTET" = "100" ] || [ "$FIRST_OCTET" = "110" ] || [ "$FIRST_OCTET" = "111" ]; then
        continue
    fi

    # Guarda sempre o IP atual (no fim fica o último válido)
    LAST_IP="$IP"
done

# Se encontrou algum IP válido, grava-o; senão, fallback
if [ -n "$LAST_IP" ]; then
    echo "$LAST_IP" > "$OUT"
else
    echo "127.0.0.1" > "$OUT"
fi

echo "Saved IP(s): $(cat "$OUT")"


EOF

    chmod +x "$SCRIPT"
    ok "IP helper script created at $SCRIPT (run it from Termux when IP changes)."
}


get_access_url() {
    FILE="/data/data/com.termux/files/home/wavelog_ip.txt"

    if [ -f "$FILE" ]; then
        # usa apenas o primeiro IP do ficheiro
        IP=$(head -n1 "$FILE")
    else
        IP="127.0.0.1"
    fi

    echo "Access Wavelog at http://$IP:8080"
}





# --- Menu ---
while true; do
    echo "┌──────────────────────────────────────────────┐"
    echo "│                LAMP CONTROL                  │"
    echo "├──────────────────── LAMP ────────────────────┤"
    echo "│  1) Start services (Apache + MariaDB + wd)   │"
    echo "│  2) Stop services  (Apache + MariaDB + wd)   │"
    echo "│  3) Check running services                   │"
    echo "│  4) Exit                                     │"
    echo "├──────────── Install LAMP + Wavelog ──────────┤"
    echo "│  5) Install LAMP                             │"
    echo "│  6) Start services (Apache + MariaDB + wd)   │"
    echo "│  7) Create DB and user wavelog               │"
    echo "│  8) Download Wavelog & config WEB PAGE NOW   │"
    echo "│  9) Fix IP                                   │"
    echo "│ 10) Create Termux launcher (start-wavelog)   │"
    echo "│ 11) Create Termux IP helper (wavelog-ip)     │"
    echo "├────────────────── Extras ────────────────────┤"
    echo "│ 12) Install Adminer                          │"
    echo "│ 13) Install phpSysinfo                       │"
    echo "├──────────────────────────────────────────────┤"
    echo "│ 14) Exit                                     │"
    echo "└──────────────────────────────────────────────┘"
   



    # Linhas de status por baixo do menu
    check_installed apache2
    check_installed php8.2
    check_installed mariadb-server
    status_services
    
    echo ""
    get_access_url
    echo ""
    
    read -p "Choose option: " opt

    case $opt in
        1) start_services ;;
        2) stop_services ;;
        3) status_services ;;
        4) stop_services; echo "Leaving..."; break ;;
        5) install_lamp ;;
        6) start_services ;;
        7) create_db ;; 
        8) download_wavelog ;;
        9) fix_ip ;;
       10) create_termux_launcher ;;
       11) create_wavelog_ip_script ;;
       12) install_adminer ;;
       13) install_phpsysinfo ;;
       14) stop_services; echo "Leaving..."; break ;;
        *) err "Invalid Option." ;;
    esac
    echo ""
done
