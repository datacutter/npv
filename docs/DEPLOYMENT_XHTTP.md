# Deployment Runbook: Xray VLESS Reality + XHTTP

Эта инструкция описывает текущую рекомендуемую схему проекта:

- `443/tcp`: VLESS + RAW/TCP + REALITY + Vision
- `8443/tcp`: запасной RAW/TCP + REALITY + Vision
- `9443/tcp`: VLESS + XHTTP + REALITY, рекомендуемый первый профиль

`9443/tcp` добавлен не как "магический порт", а как другой транспортный профиль. Если блокировка идет по IP/ASN VPS, смена транспорта не поможет. Если режется именно RAW/TCP Reality pattern или fingerprint, XHTTP и смена `fp` часто дают шанс восстановить доступ без нового VPS.

## 1. Что нужно на VPS

Рекомендуемая ОС: Ubuntu 22.04 или 24.04 LTS.

Минимальные пакеты:

```bash
sudo apt update
sudo apt install -y curl jq openssl make ufw
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
docker compose version
```

Откройте входящие порты:

```bash
sudo ufw allow 22/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8443/tcp
sudo ufw allow 9443/tcp
sudo ufw enable
```

Если у провайдера есть отдельный cloud firewall, откройте эти же TCP-порты там.

## 2. Новый сервер с нуля

Скопируйте проект на VPS, например в `/root/vpn`.

```bash
cd /root/vpn
cp .env.example .env
```

Проверьте `.env`:

```bash
nano .env
```

Минимально важные поля:

```env
SERVER_IP=YOUR_SERVER_IP
REALITY_DEST=www.apple.com:443
REALITY_SERVER_NAME=www.apple.com
REALITY_FINGERPRINT=edge
REALITY_FINGERPRINTS=edge,firefox,safari,chrome,android,ios
XRAY_PORT=443
XRAY_PORT_ALT=8443
XRAY_PORT_XHTTP=9443
XHTTP_MODE=auto
```

`XHTTP_PATH` можно не трогать: `make init` заменит placeholder на случайный путь вида `/assets/<random>`.

Запуск:

```bash
make init
make up
make healthcheck
```

Создать пользователя:

```bash
make add-user USER=alice_phone
```

Скрипт выведет несколько ссылок:

- сначала `XHTTP + REALITY` для разных `fp`;
- затем legacy `TCP + REALITY` на `443`;
- затем legacy `TCP + REALITY` на `8443`.

## 3. Обновить уже существующий сервер

На VPS:

```bash
cd /root/vpn
cp .env ".env.backup.$(date +%Y%m%d-%H%M%S)"
cp data/users.json "data/users.json.backup.$(date +%Y%m%d-%H%M%S)"
make upgrade-xray
docker compose up -d xray
make healthcheck
```

Если в UFW не открыт новый порт:

```bash
sudo ufw allow 9443/tcp
```

Выдать новые ссылки:

```bash
make list-users
make client-config USER=alice_phone
```

Старые TCP-ссылки могут продолжить работать, но клиентам лучше импортировать XHTTP-ссылку первой.

## 4. Что импортировать клиентам

Порядок тестирования:

1. `XHTTP + REALITY / fp=edge`
2. `XHTTP + REALITY / fp=firefox`
3. `XHTTP + REALITY / fp=safari`
4. `TCP + REALITY / 443 / fp=edge`
5. `TCP + REALITY / 8443 / fp=edge`

Android: используйте свежий NekoBox или другой клиент с поддержкой XHTTP.

iOS: поддержка XHTTP зависит от версии клиента. Если Shadowrocket не импортирует XHTTP-ссылку, используйте TCP Reality ссылки или клиент, который явно поддерживает XHTTP.

Не используйте один UUID на все устройства. Делайте отдельного пользователя на телефон, ноутбук и планшет:

```bash
make add-user USER=alice_android
make add-user USER=alice_laptop
```

## 5. Диагностика

На VPS:

```bash
make diagnose
```

Смысл результатов:

- `healthcheck` падает: проблема на сервере или в `xray/config.json`.
- `healthcheck` успешен, но из РФ не подключается: вероятен DPI, IP/ASN block или fingerprint filtering.
- В логах нет попыток подключения от клиента: вероятен IP/subnet block или порт режется до сервера.
- В логах попытки есть, но соединение висит: сначала пробуйте другой `fp`, потом ротацию Reality.
- Не работает ни XHTTP, ни TCP с нескольких российских провайдеров: вероятнее всего сгорел IP/ASN.

Полезные команды:

```bash
docker compose ps
docker compose logs -f xray
make healthcheck
make diagnose
make stats
```

## 6. Быстро поменять fingerprint

Это не требует перезапуска Xray, потому что `fp` живет в клиентской ссылке.

```bash
cd /root/vpn
sed -i 's/^REALITY_FINGERPRINT=.*/REALITY_FINGERPRINT=edge/' .env
sed -i 's/^REALITY_FINGERPRINTS=.*/REALITY_FINGERPRINTS=edge,firefox,safari,chrome,android,ios/' .env
make client-config USER=alice_phone
```

Если конкретный fingerprint перестал работать, не меняйте сервер сразу. Выдайте тому же пользователю ссылку с другим `fp`.

## 7. Ротация Reality

Ротация меняет `pbk`, `sid`, `SNI` и `XHTTP_PATH`. Все старые ссылки после этого считаются устаревшими.

```bash
cd /root/vpn
make rotate-reality DEST=www.apple.com:443 SNI=www.apple.com
docker compose up -d xray
make healthcheck
make client-config USER=alice_phone
```

Перед выбором другого target проверьте его:

```bash
bash scripts/check-reality-target.sh www.apple.com:443 www.apple.com
bash scripts/check-reality-target.sh www.samsung.com:443 www.samsung.com
bash scripts/check-reality-target.sh www.wikipedia.org:443 www.wikipedia.org
```

Требования к target:

- валидный сертификат;
- TLS 1.3;
- желательно HTTP/2 (`h2`);
- `REALITY_DEST` и `REALITY_SERVER_NAME` обычно должны совпадать;
- не используйте домен, который сам нестабилен или заблокирован у ваших пользователей.

## 8. Когда нужен новый VPS

Новый VPS нужен, если:

- `make healthcheck` успешен;
- XHTTP и TCP профили не работают у нескольких пользователей из разных российских сетей;
- в логах Xray нет входящих попыток от этих пользователей;
- ротация Reality и смена `fp` не помогли.

При выборе нового VPS:

- берите другой ASN/провайдера, а не соседний IP у того же хостера;
- избегайте слишком популярных дешевых локаций, которые массово используют под VPN;
- не переносите старую `.env` целиком, генерируйте новые Reality keys и `XHTTP_PATH`;
- `data/users.json` можно перенести, но ссылки все равно нужно выдать заново.

Минимальный перенос пользователей:

```bash
# На старом сервере
cd /root/vpn
tar czf vpn-users.tar.gz data/users.json data/blocked_domains.txt

# На новом сервере после копирования проекта
cd /root/vpn
tar xzf vpn-users.tar.gz
cp .env.example .env
sed -i "s|^SERVER_IP=.*|SERVER_IP=NEW_SERVER_IP|g" .env
make init
make up
make healthcheck
make list-users
make client-config USER=alice_phone
```

## 9. Регулярное обслуживание

Раз в 1-2 недели:

```bash
cd /root/vpn
make upgrade-xray
make healthcheck
```

После жалоб пользователей:

```bash
make diagnose
make client-config USER=<username>
```

Если ссылка утекла:

```bash
make revoke-user USER=<username>
make add-user USER=<username>_new
```

Не публикуйте VLESS-ссылки в общих чатах. Один пользователь должен соответствовать одному устройству. Это упрощает отзыв доступа и снижает риск массовой компрометации.

## 10. Ссылки на первичные источники

- Xray REALITY: https://xtls.github.io/en/config/transports/reality.html
- Xray transport settings: https://xtls.github.io/en/config/transport.html
- Xray TLS fingerprints: https://xtls.github.io/en/config/transports/tls.html
- Xray VLESS inbound/outbound: https://xtls.github.io/en/config/inbounds/vless.html
- Xray Browser Dialer: https://xtls.github.io/en/config/features/browser_dialer.html
- XHTTP discussion: https://github.com/XTLS/Xray-core/discussions/4113
