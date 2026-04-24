# CI/CD Monitoring + Security Stack (Prometheus, Grafana, AWS)

This repository extends the existing containerized application and Jenkins CI/CD into a full observability and security implementation.

## Architecture

- Application container on App EC2 exposes `/metrics`.
- Node Exporter runs on App EC2 (`:9100`).
- Prometheus runs on Monitoring EC2 (`:9090`) and scrapes:
  - App metrics (`app:3000/metrics`)
  - Node Exporter (`app:9100/metrics`)
- Grafana runs on Monitoring EC2 (`:3001`) and is auto-provisioned with:
  - Prometheus datasource
  - Dashboard for RPS, error rate, p95 latency
- CloudWatch Logs receives app container logs via Docker `awslogs`.
- CloudTrail is enabled with encrypted S3 storage and lifecycle expiration.
- GuardDuty is enabled for managed threat detection.

## Deliverables in Repo

- Prometheus config: [observability/prometheus.yml](observability/prometheus.yml)
- Alert rules: [observability/alert.rules.yml](observability/alert.rules.yml)
- Grafana dashboard (portable import): [observability/grafana-dashboard.json](observability/grafana-dashboard.json)
- Grafana dashboard (auto-provisioned): [observability/grafana-dashboard-provisioned.json](observability/grafana-dashboard-provisioned.json)
- Terraform infra + security resources: [terraform/main.tf](terraform/main.tf), [terraform/security.tf](terraform/security.tf)
- Ansible monitoring automation: [ansible/playbook.yml](ansible/playbook.yml), [ansible/roles/monitoring/tasks/main.yml](ansible/roles/monitoring/tasks/main.yml)
- Verification script: [scripts/verify_observability.sh](scripts/verify_observability.sh)
- Screenshot evidence checklist: [evidence/screenshots/README.md](evidence/screenshots/README.md)
- 2-page report: [report/observability-security-report.md](report/observability-security-report.md)

## 1) Prerequisites

Run locally (macOS):

```bash
brew install terraform ansible awscli jq
```

Also required:
- Docker on EC2 hosts (installed by Ansible roles)
- AWS credentials configured locally (`aws configure`)

## 2) Provision AWS infrastructure (Terraform)

From repository root:

```bash
cd terraform
terraform init
terraform plan -out tfplan
terraform apply tfplan
```

This provisions:
- Jenkins EC2
- App EC2
- Monitoring EC2
- Security groups for app, Jenkins, monitoring
- CloudWatch log group for app logs
- CloudTrail + encrypted S3 bucket + lifecycle rule (30 days)
- GuardDuty detector

Get outputs:

```bash
terraform output
```

## 3) Configure servers (Ansible)

From repository root:

```bash
cd ansible
ansible-playbook -i inventory.ini playbook.yml
```

This configures:
- Docker on app + monitoring hosts
- Node Exporter container on app host
- Prometheus container on monitoring host
- Grafana container on monitoring host
- Auto-provisioned Grafana datasource/dashboard

## 4) Deploy app via Jenkins pipeline

Run Jenkins pipeline (existing flow). Deployment now includes Docker `awslogs` configuration in [Jenkinsfile](Jenkinsfile), sending container logs to CloudWatch log group `/cicd-demo/app`.

## 5) Access monitoring UIs

Use Terraform outputs:

- Prometheus URL: `prometheus_url`
- Grafana URL: `grafana_url`

Default Grafana credentials:
- user: `admin`
- pass: `admin123`

## 6) PromQL queries

Requests/sec:

```promql
sum(rate(http_requests_total[1m]))
```

Error rate (%):

```promql
(sum(rate(http_errors_total[1m])) / sum(rate(http_requests_total[1m]))) * 100
```

Latency p95:

```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))
```

## 7) Alerting

Rule file: [observability/alert.rules.yml](observability/alert.rules.yml)

Condition:

$$
\left(\frac{\sum rate(http\_errors\_total[1m])}{\sum rate(http\_requests\_total[1m])}\right) \times 100 > 5
$$

for 1 minute.

## 8) Verification

Run automated checks:

```bash
./scripts/verify_observability.sh
```

Manual checks:

### Prometheus targets UP
```bash
curl -s http://<monitoring-ec2-public-ip>:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health, endpoint: .scrapeUrl}'
```

### Simulate errors to trigger alert
```bash
for i in {1..200}; do curl -s -o /dev/null http://<app-ec2-public-ip>:3000/error; done
```

```bash
curl -s http://<monitoring-ec2-public-ip>:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state: .state, summary: .annotations.summary}'
```

### Confirm CloudWatch logs
```bash
aws logs describe-log-streams --log-group-name /cicd-demo/app --region eu-west-1
```

### Confirm CloudTrail events
```bash
aws cloudtrail lookup-events --max-results 10 --region eu-west-1
```

### Confirm GuardDuty detector
```bash
aws guardduty list-detectors --region eu-west-1
```

## 9) Screenshots and submission evidence

Store screenshots in [evidence/screenshots](evidence/screenshots) following [evidence/screenshots/README.md](evidence/screenshots/README.md).

Report file: [report/observability-security-report.md](report/observability-security-report.md).

## 10) Cleanup (required)

After validation and screenshots:

```bash
cd terraform
terraform destroy
```

Then verify:
- EC2 instances terminated
- CloudTrail removed
- GuardDuty detector removed if your policy requires teardown
- CloudWatch log group and S3 bucket deleted

## Notes

- This setup is production-like but intentionally simple.
- Tighten `admin_cidr` in Terraform variables before real deployments.
- Replace default Grafana credentials before shared/team use.
