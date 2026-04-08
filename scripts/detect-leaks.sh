#!/bin/bash
# detect-leaks.sh
# Скрипт анализирует журнал Xray access.log на предмет использования одного ключа (Email)
# с нескольких различных публичных IP-адресов.
# Предназначен для запуска через cron (например, каждую 1-5 минут).

set -ea

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
ACCESS_LOG="$DATA_DIR/access.log"

# Количество уникальных IP, после превышения которого пользователь считается "утекшим".
# Если MAX_IPS=3, то бан произойдет при появлении 4-го уникального IP-адреса.
MAX_IPS=${1:-3}

if [ ! -s "$ACCESS_LOG" ]; then
    # Лог пуст или не существует (нет новых подключений)
    exit 0
fi

# Копируем текущий лог во временный файл и ОЧИЩАЕМ оригинал.
# Это позволяет нам при следующем запуске анализировать только новые подключения
# и не дает файлу `access.log` разрастаться до гигабайтов.
TMP_LOG=$(mktemp)
cat "$ACCESS_LOG" > "$TMP_LOG"
> "$ACCESS_LOG"

# AWK-скрипт извлекает IP (без порта) и email
LEAKED_USERS=$(awk -v max="$MAX_IPS" '
/accepted/ {
    # Позиция 3 - это IP-адрес и порт клиента (напр. 192.0.2.1:56433)
    ip_port = $3
    sub(/:.*/, "", ip_port) # отбрасываем порт
    ip = ip_port
    
    email = ""
    # Ищем поле email
    for (i=1; i<=NF; i++) {
        if ($i == "email:" && $(i+1) != "") {
            email = $(i+1)
            break
        }
    }
    
    if (email != "") {
        # Считаем уникальные комбинации "email + ip"
        if (!seen[email, ip]++) {
            count[email]++
        }
    }
}
END {
    # Выводим пользователей, превысивших лимит уникальных IP
    for (e in count) {
        if (count[e] > max) {
            print e
        }
    }
}
' "$TMP_LOG")

rm -f "$TMP_LOG"

if [ -n "$LEAKED_USERS" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Обнаружены нарушения:"
    for user in $LEAKED_USERS; do
        echo "[!] Лимит превышен: пользователь $user был замечен с >$MAX_IPS уникальных IP. Запуск блокировки..."
        "$SCRIPT_DIR/revoke-user.sh" "$user"
        echo "[+] $user заблокирован и удален."
    done
fi
