# Screenshot Checklist

Add screenshots here after deployment verification.

Required evidence:

1. Prometheus targets `app` and `node_exporter` both `UP`
2. Grafana dashboard panels populated:
   - Requests Per Second
   - Error Rate (%)
   - Latency p95
3. Active `HighErrorRate` alert in Prometheus alerts UI/API
4. CloudWatch Logs stream containing app container logs
5. CloudTrail events visible in Event history or `lookup-events`
6. GuardDuty detector enabled and sample findings (if generated)

Suggested filenames:

- prometheus-targets-up.png
- grafana-dashboard-live.png
- prometheus-alert-high-error-rate.png
- cloudwatch-log-stream.png
- cloudtrail-events.png
- guardduty-detector-or-findings.png
