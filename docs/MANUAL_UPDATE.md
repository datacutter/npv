# Ручное обновление и восстановление доступа

Эта инструкция нужна, когда сервер уже развернут на VPS и вы хотите обновить его вручную, без угадывания порядка команд.

## Что важно понимать

- `make upgrade-xray` обновляет Xray Core и перерендеривает конфиг, но не ломает старые клиентские ссылки.
- `make rotate-reality` меняет Reality `pbk`, `sid` и `SNI`; после этого все старые VLESS-ссылки нужно выдать заново.
- Если заблокирован IP или подсеть VPS, ротация Reality может не помочь. В этом случае нужен новый IP/VPS.
- `8443/tcp` полезен только при фильтрации конкретного порта `443/tcp`. При IP-блоке он не поможет.
- WireGuard/OpenVPN для России не рассматриваются как основной вариант: их сигнатуры проще фильтровать.

## Перед любым обновлением

Подключитесь к VPS и сделайте быстрый backup текущего состояния:

```bash
cd /root/vpn
cp .env ".env.backup.$(date +%Y%m%d-%H%M%S)"
cp data/users.json "data/users.json.backup.$(date +%Y%m%d-%H%M%S)"
docker compose ps
make healthcheck
```

Если `make healthcheck` уже падает, сначала посмотрите логи:

```bash
make logs
```

## Быстрое штатное обновление

Используйте этот сценарий раз в 2-4 недели или когда клиентские приложения обновились, а сервер давно нет:

```bash
cd /root/vpn
make upgrade-xray
make healthcheck
```

Если `make` недоступен, выполните вручную:

```bash
cd /root/vpn
docker compose pull xray
bash scripts/render-config.sh
docker compose up -d xray
bash scripts/healthcheck.sh
```

## Ручное обновление версии Xray Core

Проверить последнюю версию на GitHub и записать ее в `.env`:

```bash
cd /root/vpn
XRAY_TAG=$(curl -fsSL https://api.github.com/repos/XTLS/Xray-core/releases | jq -r '.[0].tag_name | sub("^v"; "")')
echo "Latest Xray tag: ${XRAY_TAG}"
sed -i "s|^XRAY_IMAGE=.*|XRAY_IMAGE=ghcr.io/xtls/xray-core:${XRAY_TAG}|g" .env
```

Применить обновление:

```bash
docker compose pull xray
bash scripts/render-config.sh
docker compose up -d xray
bash scripts/healthcheck.sh
```

Если после обновления контейнер не стартует, верните старый image из backup `.env` и повторите:

```bash
cp .env.backup.YYYYMMDD-HHMMSS .env
bash scripts/render-config.sh
docker compose up -d xray
bash scripts/healthcheck.sh
```

## Ротация Reality при блокировке

Сначала попробуйте ротацию Reality без смены IP:

```bash
cd /root/vpn
make rotate-reality DEST=www.microsoft.com:443 SNI=www.microsoft.com
make healthcheck
```

То же самое вручную, без `make`:

```bash
cd /root/vpn
DEST=www.microsoft.com:443
SNI=www.microsoft.com

bash scripts/check-reality-target.sh "$DEST" "$SNI"
sed -i "s|^REALITY_DEST=.*|REALITY_DEST=${DEST}|g" .env
sed -i "s|^REALITY_SERVER_NAME=.*|REALITY_SERVER_NAME=${SNI}|g" .env
bash scripts/generate-secrets.sh --force
bash scripts/render-config.sh
docker compose up -d xray
bash scripts/healthcheck.sh
```

После ротации обязательно выдать новые ссылки всем активным пользователям:

```bash
make list-users
make client-config USER=alice
```

Вручную без `make`:

```bash
bash scripts/list-users.sh
bash scripts/print-client-config.sh alice
```

## Как выбрать Reality target

Target должен быть реальным HTTPS-сайтом с валидным сертификатом, TLS 1.3 и желательно HTTP/2:

```bash
bash scripts/check-reality-target.sh www.microsoft.com:443 www.microsoft.com
bash scripts/check-reality-target.sh www.apple.com:443 www.apple.com
bash scripts/check-reality-target.sh www.samsung.com:443 www.samsung.com
```

Практические правила:

- Не используйте домен, который сам нестабилен или заблокирован у нужных пользователей.
- `REALITY_DEST` и `REALITY_SERVER_NAME` должны совпадать, если вы точно не понимаете SAN сертификата.
- Не используйте случайные маленькие сайты: плохой TLS-профиль и редкий SNI выглядят хуже.
- Не меняйте target каждый день без причины: пользователям придется постоянно переимпортировать ссылки.

## Когда нужен новый IP/VPS

Меняйте IP или VPS, если после ротации Reality:

- не работает ни `443`, ни `8443`;
- контейнер и healthcheck на сервере успешны, но из России подключение не устанавливается;
- несколько пользователей у разных российских провайдеров одновременно не могут подключиться;
- `make logs` не показывает попыток подключения от клиентов.

Минимальный перенос на новый сервер:

```bash
# На старом сервере
cd /root/vpn
tar czf vpn-state.tar.gz data/users.json data/blocked_domains.txt

# Скопировать проект и vpn-state.tar.gz на новый VPS, затем на новом сервере:
cd /root/vpn
tar xzf vpn-state.tar.gz
cp .env.example .env
sed -i "s|^SERVER_IP=.*|SERVER_IP=NEW_SERVER_IP|g" .env
bash scripts/generate-secrets.sh --force
bash scripts/render-config.sh
docker compose up -d
bash scripts/healthcheck.sh
```

После переноса выдать новые ссылки всем активным пользователям:

```bash
bash scripts/list-users.sh
bash scripts/print-client-config.sh alice
```

## Диагностика

Проверить контейнер и порты:

```bash
docker compose ps
bash scripts/healthcheck.sh
```

Проверить синтаксис Xray config:

```bash
docker run --rm -v "$(pwd)/xray:/etc/xray:ro" "$(grep '^XRAY_IMAGE=' .env | cut -d= -f2-)" run -test -config /etc/xray/config.json
```

Посмотреть активных пользователей и статистику:

```bash
bash scripts/list-users.sh
bash scripts/stats.sh
```

Полностью очистить список пользователей:

```bash
make reset-users CONFIRM=YES
```

Команда создаст backup `data/users.json`, запишет пустой массив `[]` и перерендерит Xray config.

Посмотреть логи:

```bash
docker compose logs -f xray
```

## Регулярные рекомендации

- Обновляйте Xray Core и клиентские приложения одновременно: сервер старой версии плюс новый клиент часто дает нестабильные Reality-профили.
- Держите отдельный UUID на каждое устройство, а не один общий ключ на всех.
- Не публикуйте VLESS-ссылки в общих чатах. При утечке отзывайте конкретного пользователя, а не ротируйте весь Reality без необходимости.
- Основной рабочий порт держите `443/tcp`; `8443/tcp` используйте только как fallback.
- Проверяйте доступность не только с VPS, но и фактически из России: server-side healthcheck не видит DPI/IP-блокировку.
