# External Data Layer (AWS, us-east-1)

This phase provisions **all data services outside Kubernetes**:

- **MySQL** → AWS RDS (private subnet, no public access)
- **MongoDB** → EC2 (private subnet)
- **Redis** → EC2 (private subnet)
- **Elasticsearch** → EC2 (private subnet)

Access is locked down so **only the EKS worker node security group** can reach DB ports.

## What This Creates

Terraform in `infra/terraform` will create:

- RDS MySQL instance + subnet group
- RDS MySQL parameter group (utf8mb4 charset/collation)
- 3 EC2 instances (MongoDB, Redis, Elasticsearch)
- Security groups for each DB service (inbound only from EKS worker SG)
- IAM role + instance profile (SSM + Secrets Manager read)
- Secrets Manager secrets for DB credentials (no secrets printed)
- Optional S3 Gateway VPC endpoint (for backups without NAT)

## Preconditions

- AWS CLI configured for account `096365818004`
- Terraform 1.5+
- `jq` installed (required by discovery script)
- Access to region `us-east-1`

## How Discovery Works

Terraform queries AWS to discover:

- EKS cluster VPC ID
- Private subnets tagged `kubernetes.io/role/internal-elb=1`
- EKS worker node security group (via `infra/terraform/scripts/get-worker-sg.sh`)

No resource names are assumed.

## Deploy (Terraform)

Use the script for deterministic plan/apply:
```bash
infra/terraform/apply.sh
```

Equivalent manual commands:
```bash
terraform -chdir=infra/terraform init -input=false
terraform -chdir=infra/terraform plan -input=false -out tfplan
```

Before apply, review instance sizes and costs in `variables.tf`.

```bash
terraform -chdir=infra/terraform apply -input=false tfplan
```

## Critical Validation Checklist (Required)

1) **MySQL engine/version + parameter group**
   - Engine: `mysql` (not Aurora)
   - Version: `8.0.x`
   - Parameter group sets:
     - `character_set_server=utf8mb4`
     - `collation_server=utf8mb4_unicode_ci`

2) **MongoDB version + auth enabled**
   - Installed from MongoDB official repo (`mongodb-org` 6.0)
   - **Admin/root user created**
   - `authorization: enabled`
   - Bound to private interface (SG-restricted)

3) **Elasticsearch memory sizing**
   - Heap set via `/etc/elasticsearch/jvm.options.d/heap.options` (512m)
   - `vm.max_map_count=262144` applied via sysctl

4) **DNS / routing from pods to private services**
   - EKS nodes are in private subnets
   - SG inbound rules reference worker node SG
   - Route tables allow private subnet-to-private subnet traffic
   - NACLs allow TCP to DB ports

5) **Backups to S3 without NAT surprises**
   - If no NAT Gateway, enable `enable_s3_gateway_endpoint = true`
   - Gateway endpoint routes traffic to S3 without public egress

6) **Verification from inside EKS**
   - Use a temporary pod to validate connectivity and service health

## Verification Commands (Post-Provision)

> Replace placeholders with actual output values.

List RDS instance:

```bash
RDS_ENDPOINT=$(terraform -chdir=infra/terraform output -raw rds_endpoint)
aws rds describe-db-instances --region us-east-1 \
  --query "DBInstances[?Endpoint.Address=='${RDS_ENDPOINT}'].[DBInstanceIdentifier,PubliclyAccessible,Engine,EngineVersion]" \
  --output table
```

List EC2 instances:

```bash
for name in mongo redis elasticsearch; do
  ip=$(terraform -chdir=infra/terraform output -raw ${name}_private_ip)
  aws ec2 describe-instances --region us-east-1 \
    --filters Name=private-ip-address,Values=${ip} \
    --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,PublicIpAddress,State.Name]' \
    --output table
done
```

Get endpoints from Terraform:

```bash
terraform -chdir=infra/terraform output -json
```

Test connectivity from EKS:

```bash
kubectl -n openedx-prod run netcheck --rm -it --image=alpine -- sh
```

Inside the pod:

```sh
apk add --no-cache netcat-openbsd curl
nc -zv <RDS_ENDPOINT> 3306
nc -zv <MONGO_IP> 27017
nc -zv <REDIS_IP> 6379
nc -zv <ES_IP> 9200
curl -sS http://<ES_IP>:9200 | head -n 1
```

Optional MySQL client check:

```sh
apk add --no-cache mysql-client
mysql -h <RDS_ENDPOINT> -u <DB_USER> -p -e "SELECT 1;"
```

## Network Validation (AWS)

Check private subnets and route tables:

```bash
aws ec2 describe-subnets --subnet-ids <PRIVATE_SUBNET_ID_1> <PRIVATE_SUBNET_ID_2> --region us-east-1
aws ec2 describe-route-tables --filters Name=association.subnet-id,Values=<PRIVATE_SUBNET_ID_1>,<PRIVATE_SUBNET_ID_2> --region us-east-1
aws ec2 describe-network-acls --filters Name=vpc-id,Values=<VPC_ID> --region us-east-1
```

## Secrets (No Values Printed)

Retrieve secret ARNs from Terraform outputs. To fetch values safely:

```bash
aws secretsmanager get-secret-value --secret-id <SECRET_ARN> --region us-east-1
```

Do not print secret values in shared logs.

## Notes

- All DB services are in **private subnets** and **not publicly accessible**.
- Security groups only allow inbound from the EKS worker SG.

## Latest Verification (2026-02-09)

From an EKS `netcheck` pod:

```text
RDS 3306: connection succeeded
Mongo 27017: connection succeeded
Redis 6379: connection succeeded
ES 9200: connection succeeded
ES HTTP: responded with JSON header
```
- Instance sizes are intentionally small for cost control.
- For production hardening: enable backups, multi-AZ, monitoring, and authentication hardening.
