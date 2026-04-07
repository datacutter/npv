.PHONY: init up down restart logs status render add-user revoke-user list-users client-config stats healthcheck regenerate-secrets firewall-apply firewall-reset firewall-status

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

firewall-apply:
	@bash scripts/apply-firewall.sh

firewall-reset:
	@bash scripts/reset-firewall.sh

firewall-status:
	@sudo iptables -nL VPN-FIREWALL -v || echo "Chain VPN-FIREWALL does not exist."

blocklist-apply:
	@bash scripts/apply-domain-blocklist.sh

blocklist-reset:
	@bash scripts/reset-domain-blocklist.sh

blocklist-status:
	@jq '.routing.rules[] | select(.tag == "domain-blocklist") | .domain' xray/config.json || echo "No blocklist rule found in config.json"

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
