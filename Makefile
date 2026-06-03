.PHONY: init up down restart logs status render add-user revoke-user reset-users list-users client-config stats healthcheck check-reality-target rotate-reality regenerate-secrets firewall-apply firewall-reset firewall-status tune-kernel upgrade-xray

init:
	@bash scripts/init.sh

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

status:
	docker compose ps

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

reset-users:
	@bash scripts/reset-users.sh $(if $(filter YES,$(CONFIRM)),--yes,)

list-users:
	@bash scripts/list-users.sh

client-config:
	@bash scripts/print-client-config.sh $(USER)

stats:
	@bash scripts/stats.sh

healthcheck:
	@bash scripts/healthcheck.sh

check-reality-target:
	@bash scripts/check-reality-target.sh

rotate-reality:
	@bash scripts/rotate-reality.sh "$(DEST)" "$(SNI)"

regenerate-secrets:
	@bash scripts/generate-secrets.sh --force

tune-kernel:
	@sudo bash scripts/tune-kernel.sh

upgrade-xray:
	@bash scripts/upgrade-xray.sh
