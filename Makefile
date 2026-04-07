.PHONY: init up down restart logs vless wg status

init:
	@chmod +x scripts/*.sh
	@./scripts/init.sh

up:
	docker-compose up -d

down:
	docker-compose down

restart:
	docker-compose restart

logs:
	docker-compose logs -f

vless:
	@chmod +x scripts/get-vless-link.sh
	@./scripts/get-vless-link.sh

wg:
	@chmod +x scripts/get-wg-client.sh
	@./scripts/get-wg-client.sh $(client)

status:
	docker-compose ps
