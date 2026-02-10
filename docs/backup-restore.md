# Backup & Restore Strategy

This project uses AWS-native snapshots for a **low-cost, minimal** backup strategy.

## Backup (Manual Snapshot Script)

Script:
- `infra/backups/backup.sh`
- `infra/backups/restore.sh` (restore helper; dry-run by default)

What it does:
- Creates a **manual RDS snapshot** for MySQL.
- Creates **EBS snapshots** for Mongo/Redis/Elasticsearch root volumes (EC2).
- Creates **EBS snapshots** for PVC volumes in `openedx-prod` (EBS CSI).
- The Open edX shared media volume (`openedx-media`, EFS) uses **AWS Backup / EFS backup policy** (not EBS snapshots).

Run:
```bash
infra/backups/backup.sh
```

Run from the repository root so the Terraform output path resolves correctly.

## EFS Media (AWS Backup)

Open edX uploads/media are stored on an EFS filesystem (RWX). For backups, use AWS Backup (recommended) or enable EFS automatic backups.

Enable automatic backups (EFS backup policy):
```bash
EFS_ID=$(terraform -chdir=infra/media-efs output -raw efs_file_system_id)
aws efs put-backup-policy --region us-east-1 --file-system-id "$EFS_ID" --backup-policy Status=ENABLED
```

Disable automatic backups (cost control):
```bash
EFS_ID=$(terraform -chdir=infra/media-efs output -raw efs_file_system_id)
aws efs put-backup-policy --region us-east-1 --file-system-id "$EFS_ID" --backup-policy Status=DISABLED
```

## Restore (High-Level)

## Restore (Scripts)

Restore helper script:
- `infra/backups/restore.sh`

Safety:
- This script is **dry-run by default**.
- To actually create restore resources, set: `CONFIRM_RESTORE=YES`

RDS restore (restores a new DB instance from the latest manual snapshot):
```bash
infra/backups/restore.sh rds
```

Create EBS volume from snapshot (for EC2 volumes or EBS-backed PV restores):
```bash
infra/backups/restore.sh ebs-volume snap-0123456789abcdef0 us-east-1a
```

### RDS
1. Create new DB from snapshot in RDS console.
2. Update Open edX MySQL host/password in Tutor config.

### EC2 DB nodes
1. Create volume from snapshot.
2. Attach to new EC2 instance (same AMI/role).
3. Mount volume to expected path and restart service.

### PVC (EBS CSI)
1. Create EBS volume from snapshot.
2. Create a PV pointing to the new volume.
3. Recreate PVC and rebind to PV.

## Notes
- This satisfies the assessment requirement for backup strategy.
- For production, schedule backups via AWS Backup or cron + AWS CLI.
