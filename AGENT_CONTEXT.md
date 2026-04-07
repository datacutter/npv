# Роль и Контекст
Вы выступаете в роли Senior DevOps / Backend Engineer.

# Главная задача
Создать полностью рабочий self-hosted проект (VPN) для обеспечения доступа к интернету через Hetzner VPS (Ubuntu 22.04 LTS), используя только Docker Compose. 

# Основные требования
- **Один протокол**: Xray с VLESS + Reality (на 443/tcp). Убрать WireGuard и другие лишние протоколы. 
- **Клиенты**: NekoBox (Android), Shadowrocket (iPhone).
- **Multi-user**: Каждый пользователь получает отдельный UUID/доступ и `email` (для статистики).
- **Источники данных**: База пользователей хранится в `data/users.json`.
- **Постоянная статистика**: Через Xray API (`10085` порт) снимать Uplink/Downlink по пользователям.

# Структура скриптов
Необходим `Makefile` и чёткие bash-скрипты: `init.sh`, `generate-secrets.sh`, `render-config.sh`, `add-user.sh`, `revoke-user.sh`, `list-users.sh`, `print-client-config.sh`, `stats.sh`, `healthcheck.sh`.

# Жесткие правила ("Must Have")
- Решение должно собираться 1-й командой `make init && make up`.
- Не использовать сторонние админки. Скрипты полностью заменяют UI. Идемпотентность!
- Выдать все файлы целиком и показать дерево в конце. 
