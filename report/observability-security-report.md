# Observability and Security Report (2-Page Summary)

## Project Scope

This project extends an existing CI/CD pipeline and containerized Node.js web application into a full observability and security stack on AWS. The objective was to deliver end-to-end operational visibility, proactive alerting, and foundational cloud security telemetry using Prometheus, Grafana, CloudWatch Logs, CloudTrail, GuardDuty, and S3 controls.

## Architecture Overview

The solution uses three EC2 instances:

- Jenkins EC2 for CI/CD automation.
- App EC2 hosting the containerized application and Node Exporter.
- Monitoring EC2 hosting Prometheus and Grafana in Docker.

The application exposes `/metrics` using Prometheus instrumentation with custom counters/histograms:

- `http_requests_total`
- `http_errors_total`
- `http_request_duration_seconds`

Prometheus scrapes application metrics and host metrics (Node Exporter) every 15 seconds. Grafana visualizes core service health indicators and latency behavior. A Prometheus alert rule detects sustained error-rate violations above 5%.

## Observability Outcomes

### Key dashboards

The Grafana dashboard includes three operational panels:

1. Requests Per Second (RPS)
2. Error Rate (%)
3. Latency p95 (seconds)

This panel set provides a compact but production-relevant view of throughput, reliability, and user experience.

### Alerting

A Prometheus rule triggers `HighErrorRate` when:

$$(\frac{\sum rate(http\_errors\_total[1m])}{\sum rate(http\_requests\_total[1m])}) \times 100 > 5$$

for 1 continuous minute.

The rule is labeled with severity/team/service metadata and annotations for incident context.

### Validation performed

- Prometheus targets validated as `UP`.
- Query output validated directly through Prometheus API.
- Alert fired after controlled error generation using `/error` endpoint.
- Grafana panels updated in near real-time under generated traffic.

## Security Outcomes

### CloudWatch Logs

The application container is deployed with Docker `awslogs` driver from Jenkins deployment. This streams runtime logs into CloudWatch log group `/cicd-demo/app`, improving operational auditability and troubleshooting speed.

### CloudTrail + S3 hardening

CloudTrail is configured as multi-region with log file validation and S3 storage. The log bucket includes:

- Server-side encryption (SSE-S3 / AES256)
- Public access blocking
- Lifecycle expiration policy (30 days)

This meets baseline governance for tamper resistance, retention control, and cost optimization.

### GuardDuty

GuardDuty is enabled account-wide with 15-minute finding publishing. It continuously analyzes CloudTrail, DNS, and network telemetry for compromise indicators such as:

- suspicious IAM/API behavior
- credential misuse
- crypto-mining activity
- data exfiltration patterns

## Operational Insights

1. **Fast MTTD (Mean Time To Detect):** alerting on error-rate percentage catches reliability regressions quickly.
2. **Useful minimal dashboard:** throughput + failure + p95 latency provides high signal with low noise.
3. **Security telemetry continuity:** CloudTrail + GuardDuty + CloudWatch logs together create stronger investigation trails than any single source alone.
4. **Automation maturity:** Terraform + Ansible makes environments reproducible and supports clean teardown after verification.

## Risks / Gaps / Next Steps

- Add Alertmanager integration for Slack/Email/PagerDuty routing.
- Restrict SG ingress from `0.0.0.0/0` to enterprise CIDRs.
- Move to SSE-KMS for key ownership and fine-grained key policies.
- Add WAF / ALB / TLS termination for internet-facing workloads.
- Add synthetic probes and SLO burn-rate alerts.

## Cleanup Confirmation Plan

After evidence collection, remove all monitoring/security resources via Terraform destroy and verify:

- EC2 instances terminated
- CloudTrail trail removed
- GuardDuty detector disabled/deleted if required by policy
- CloudWatch log group retention/cleanup complete
- S3 bucket emptied and removed

This closes the lab cycle and controls cost while preserving deployment repeatability.
