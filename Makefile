.PHONY: init up down restart logs status render add-user revoke-user list-users client-config stats healthcheck regenerate-secrets

init:
	@bash scripts/init.sh

up:
	docker-compose up -d

down:
	docker-compose down

restart:
	docker-compose restart

logs:
	docker-compose logs -f

status:
	docker-compose ps

render:
	@bash scripts/render-config.sh

add-user:
	@bash scripts/add-user.sh $(USER)

revoke-user:
	@bash scripts/revoke-user.sh $(USER)

list-users:
	@bash scripts/list-users.sh

client-config:
	@bash scripts/print-client-config.sh $(USER)

stats:
	@bash scripts/stats.sh

healthcheck:
	@bash scripts/healthcheck.sh

regenerate-secrets:
	@bash scripts/generate-secrets.sh --force
