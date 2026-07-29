"""
SnapWarden | Automated Multi-Region EBS Snapshot Lifecycle Manager
Handles snapshot creation across all active AWS regions and enforces
configurable retention policies by purging stale snapshots.
"""

import boto3
import datetime
import os
import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SNS_TOPIC_ARN     = os.environ.get("SNS_TOPIC_ARN", "")
RETENTION_DAYS    = int(os.environ.get("RETENTION_DAYS", "7"))
TAG_KEY           = os.environ.get("TAG_KEY", "Snapshot")
TAG_VALUE         = os.environ.get("TAG_VALUE", "true")
PROJECT_TAG       = "snapwarden"


def get_active_regions() -> list[str]:
    """Return all opted-in AWS regions available to this account."""
    ec2 = boto3.client("ec2", region_name="us-east-1")
    response = ec2.describe_regions(
        Filters=[{"Name": "opt-in-status", "Values": ["opt-in-not-required", "opted-in"]}]
    )
    return [r["RegionName"] for r in response["Regions"]]


def create_snapshots(region: str, today: str) -> list[str]:
    """
    Discover EBS volumes tagged for backup in the given region
    and create a point-in-time snapshot for each.
    """
    ec2 = boto3.client("ec2", region_name=region)
    created = []

    try:
        volumes = ec2.describe_volumes(
            Filters=[{"Name": f"tag:{TAG_KEY}", "Values": [TAG_VALUE]}]
        )
    except Exception as exc:
        logger.warning("Could not list volumes in %s: %s", region, exc)
        return created

    for volume in volumes["Volumes"]:
        volume_id = volume["VolumeId"]
        description = f"ebs-guardian | {volume_id} | {today}"
        try:
            snapshot = ec2.create_snapshot(
                VolumeId=volume_id,
                Description=description,
                TagSpecifications=[{
                    "ResourceType": "snapshot",
                    "Tags": [
                        {"Key": "CreatedOn",   "Value": today},
                        {"Key": "ManagedBy",   "Value": PROJECT_TAG},
                        {"Key": "SourceRegion","Value": region},
                        {"Key": "VolumeId",    "Value": volume_id},
                    ],
                }],
            )
            snap_id = snapshot["SnapshotId"]
            created.append(snap_id)
            logger.info("Created snapshot %s for volume %s in %s", snap_id, volume_id, region)
        except Exception as exc:
            logger.error("Failed to snapshot %s in %s: %s", volume_id, region, exc)

    return created


def purge_expired_snapshots(region: str, cutoff: datetime.datetime) -> list[str]:
    """
    Delete snapshots managed by ebs-guardian that are older than the
    retention cutoff date, returning a list of purged snapshot IDs.
    """
    ec2 = boto3.client("ec2", region_name=region)
    purged = []

    try:
        snapshots = ec2.describe_snapshots(
            Filters=[{"Name": "tag:ManagedBy", "Values": [PROJECT_TAG]}],
            OwnerIds=["self"],
        )
    except Exception as exc:
        logger.warning("Could not list snapshots in %s: %s", region, exc)
        return purged

    for snap in snapshots["Snapshots"]:
        start_time = snap["StartTime"].replace(tzinfo=None)
        if start_time < cutoff:
            snap_id = snap["SnapshotId"]
            try:
                ec2.delete_snapshot(SnapshotId=snap_id)
                purged.append(snap_id)
                logger.info(
                    "Purged expired snapshot %s (created %s) in %s",
                    snap_id, start_time.date(), region,
                )
            except Exception as exc:
                logger.error("Could not delete snapshot %s in %s: %s", snap_id, region, exc)

    return purged


def publish_report(regions_summary: list[dict], today: str) -> None:
    """Publish a structured execution report to the SNS topic."""
    if not SNS_TOPIC_ARN:
        logger.info("SNS_TOPIC_ARN not set — skipping notification.")
        return

    total_created = sum(r["created"] for r in regions_summary)
    total_purged  = sum(r["purged"]  for r in regions_summary)

    lines = [
        "ebs-guardian Execution Report",
        "=" * 40,
        f"Date          : {today}",
        f"Retention     : {RETENTION_DAYS} days",
        f"Regions scanned: {len(regions_summary)}",
        f"Snapshots created : {total_created}",
        f"Snapshots purged  : {total_purged}",
        "",
        "Region Breakdown",
        "-" * 40,
    ]

    for r in regions_summary:
        if r["created"] or r["purged"] or r["error"]:
            lines.append(
                f"  {r['region']:25s}  created={r['created']}  purged={r['purged']}"
                + (f"  [ERROR: {r['error']}]" if r["error"] else "")
            )

    sns = boto3.client("sns")
    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"ebs-guardian | Backup Report | {today}",
        Message="\n".join(lines),
    )
    logger.info("Execution report published to SNS.")


def lambda_handler(event, context):
    today   = datetime.datetime.utcnow().strftime("%Y-%m-%d")
    cutoff  = datetime.datetime.utcnow() - datetime.timedelta(days=RETENTION_DAYS)
    regions = get_active_regions()

    logger.info(
        "ebs-guardian started | date=%s | retention=%d days | regions=%d",
        today, RETENTION_DAYS, len(regions),
    )

    summary = []

    for region in regions:
        entry = {"region": region, "created": 0, "purged": 0, "error": ""}
        try:
            created = create_snapshots(region, today)
            purged  = purge_expired_snapshots(region, cutoff)
            entry["created"] = len(created)
            entry["purged"]  = len(purged)
        except Exception as exc:
            entry["error"] = str(exc)
            logger.error("Unhandled error in region %s: %s", region, exc)
        summary.append(entry)

    publish_report(summary, today)

    total_created = sum(r["created"] for r in summary)
    total_purged  = sum(r["purged"]  for r in summary)

    logger.info(
        "ebs-guardian complete | created=%d | purged=%d",
        total_created, total_purged,
    )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "date":          today,
            "regions":       len(regions),
            "snapshots_created": total_created,
            "snapshots_purged":  total_purged,
            "summary":       summary,
        }),
    }