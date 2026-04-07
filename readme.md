# Production Xray + WireGuard (Docker Compose)

Этот проект разворачивает надежный VPN стек на Ubuntu 22.04:
- **Xray** (VLESS + XTLS Reality) на порту 443/tcp
- **WireGuard** (Fallback) на порту 51820/udp

## Быстрый старт
1. `make init` - Автоматически инициализирует переменные, генерирует секреты Xray и ключи WireGuard.
2. `make up` - Запускает контейнеры в фоне.
3. `make vless` - Печатает готовую ссылку VLESS для импорта в NekoBox / v2rayN.
4. `make wg client=client1` - Генерирует клиентский конфиг WireGuard (сохраняется в папку `clients/`). **После добавления пира необходимо выполнить `make restart`**.

## Настройки Firewall

Убедитесь, что ваш VPS разрешает входящий трафик на эти порты:
- `443/tcp` (Xray)
- `51820/udp` (WireGuard)

Если вы используете `ufw`, выполните:
```bash
sudo ufw allow 443/tcp
sudo ufw allow 51820/udp
```

## Управление
В проекте используется `Makefile` для удобного вызова команд:
- `make logs` - посмотреть логи контейнеров
- `make down` - остановить VPN
- `make restart` - перезапустить (полезно после добавления WG клиентов)
- `make status` - проверить статус работы
