#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${PROM_URL:-}" || -z "${APP_URL:-}" ]]; then
	echo "Error: PROM_URL and APP_URL must be set for production verification."
	echo "Example:"
	exit 1
fi

echo "== Targets =="
curl -s "$PROM_URL/api/v1/targets" | jq '.data.activeTargets[] | {job: .labels.job, health: .health, scrapeUrl: .scrapeUrl}'

echo "== App metrics sample =="
curl -s "$APP_URL/metrics" | grep -E 'http_requests_total|http_errors_total|http_request_duration_seconds' | head -n 20

echo "== Generate sample traffic =="
for i in {1..50}; do curl -s "$APP_URL/" > /dev/null; done
for i in {1..20}; do curl -s -o /dev/null "$APP_URL/error"; done

echo "== PromQL: requests/sec =="
curl -sG "$PROM_URL/api/v1/query" --data-urlencode 'query=sum(rate(http_requests_total[1m]))' | jq

echo "== PromQL: error rate (%) =="
curl -sG "$PROM_URL/api/v1/query" --data-urlencode 'query=(sum(rate(http_errors_total[1m])) / sum(rate(http_requests_total[1m]))) * 100' | jq

echo "== Alerts =="
curl -s "$PROM_URL/api/v1/alerts" | jq '.data.alerts[] | {alert: .labels.alertname, state: .state, summary: .annotations.summary}'

echo "Verification complete."
