"""
AWS Cost Optimizer — Idle EC2 Instance Stopper
Author: Emmanuel Ubani — Cloud and DevOps Engineer
GitHub: github.com/Eaglewings966

Description:
    Identifies EC2 instances with average CPU utilization below
    the configured threshold for the past 24 hours and stops them.
    Publishes a detailed report to SNS with instance IDs, names,
    CPU averages, and actions taken.

Environment Variables:
    SNS_TOPIC_ARN        — ARN of the SNS topic for notifications
    CPU_IDLE_THRESHOLD   — CPU % below which instance is idle (default: 5)
    IDLE_HOURS_THRESHOLD — Hours of low CPU to qualify as idle (default: 24)
    ENVIRONMENT          — Deployment environment label
"""

import boto3
import json
import os
import logging
from datetime import datetime, timezone, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment configuration
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
CPU_IDLE_THRESHOLD = float(os.environ.get("CPU_IDLE_THRESHOLD", "5"))
IDLE_HOURS_THRESHOLD = int(os.environ.get("IDLE_HOURS_THRESHOLD", "24"))
ENVIRONMENT = os.environ.get("ENVIRONMENT", "production")

ec2_client = boto3.client("ec2")
cloudwatch_client = boto3.client("cloudwatch")
sns_client = boto3.client("sns")


def get_running_instances():
    """
    Returns all running EC2 instances in the account.
    Excludes instances tagged with CostOptimizer: exempt.
    """
    instances = []

    paginator = ec2_client.get_paginator("describe_instances")
    pages = paginator.paginate(
        Filters=[{"Name": "instance-state-name", "Values": ["running"]}]
    )

    for page in pages:
        for reservation in page["Reservations"]:
            for instance in reservation["Instances"]:
                tags = {
                    tag["Key"]: tag["Value"]
                    for tag in instance.get("Tags", [])
                }

                # Skip instances explicitly exempted from cost optimization
                if tags.get("CostOptimizer") == "exempt":
                    logger.info(
                        f"Skipping exempt instance: {instance['InstanceId']}"
                    )
                    continue

                instances.append({
                    "instance_id": instance["InstanceId"],
                    "instance_type": instance["InstanceType"],
                    "launch_time": instance["LaunchTime"].isoformat(),
                    "name": tags.get("Name", "unnamed"),
                    "environment": tags.get("Environment", "untagged"),
                    "owner": tags.get("Owner", "untagged"),
                    "project": tags.get("Project", "untagged"),
                    "cost_center": tags.get("CostCenter", "untagged"),
                })

    logger.info(f"Found {len(instances)} running instances to evaluate")
    return instances


def get_average_cpu(instance_id, hours=24):
    """
    Returns the average CPU utilization for an instance
    over the past specified number of hours.
    Returns None if no data is available.
    """
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(hours=hours)

    response = cloudwatch_client.get_metric_statistics(
        Namespace="AWS/EC2",
        MetricName="CPUUtilization",
        Dimensions=[
            {"Name": "InstanceId", "Value": instance_id}
        ],
        StartTime=start_time,
        EndTime=end_time,
        Period=int(hours * 3600),
        Statistics=["Average"]
    )

    datapoints = response.get("Datapoints", [])

    if not datapoints:
        logger.warning(f"No CPU data for instance {instance_id}")
        return None

    return round(datapoints[0]["Average"], 2)


def stop_instance(instance_id):
    """
    Stops a single EC2 instance.
    Returns True on success, False on failure.
    """
    try:
        ec2_client.stop_instances(InstanceIds=[instance_id])
        logger.info(f"Successfully stopped instance: {instance_id}")
        return True
    except Exception as error:
        logger.error(f"Failed to stop instance {instance_id}: {str(error)}")
        return False


def publish_report(stopped, skipped, no_data, errors):
    """
    Publishes a structured cost optimization report to SNS.
    """
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    subject = (
        f"[{ENVIRONMENT.upper()}] Cost Optimizer — "
        f"{len(stopped)} instance(s) stopped — {timestamp[:10]}"
    )

    message_lines = [
        "=" * 60,
        "AWS COST OPTIMIZER — IDLE INSTANCE REPORT",
        "=" * 60,
        f"Timestamp:       {timestamp}",
        f"Environment:     {ENVIRONMENT}",
        f"CPU Threshold:   Below {CPU_IDLE_THRESHOLD}% for {IDLE_HOURS_THRESHOLD} hours",
        "",
        f"SUMMARY",
        f"  Instances stopped:        {len(stopped)}",
        f"  Instances within limit:   {len(skipped)}",
        f"  Instances with no data:   {len(no_data)}",
        f"  Stop errors:              {len(errors)}",
        "",
    ]

    if stopped:
        message_lines.append("STOPPED INSTANCES")
        message_lines.append("-" * 40)
        for inst in stopped:
            message_lines.extend([
                f"  Instance ID:   {inst['instance_id']}",
                f"  Name:          {inst['name']}",
                f"  Type:          {inst['instance_type']}",
                f"  Avg CPU (24h): {inst['avg_cpu']}%",
                f"  Owner:         {inst['owner']}",
                f"  Project:       {inst['project']}",
                f"  CostCenter:    {inst['cost_center']}",
                "",
            ])

    if skipped:
        message_lines.append("INSTANCES WITHIN CPU THRESHOLD (not stopped)")
        message_lines.append("-" * 40)
        for inst in skipped:
            message_lines.extend([
                f"  {inst['instance_id']} ({inst['name']}) "
                f"— CPU: {inst['avg_cpu']}%",
            ])
        message_lines.append("")

    if no_data:
        message_lines.append("INSTANCES WITH NO CLOUDWATCH DATA")
        message_lines.append("-" * 40)
        for inst in no_data:
            message_lines.append(
                f"  {inst['instance_id']} ({inst['name']}) "
                f"— launched {inst['launch_time'][:10]}"
            )
        message_lines.append("")

    if errors:
        message_lines.append("STOP ERRORS")
        message_lines.append("-" * 40)
        for error in errors:
            message_lines.append(f"  {error}")
        message_lines.append("")

    message_lines.extend([
        "=" * 60,
        "Powered by Tech with Emma — Cost Optimization Engine",
        "github.com/Eaglewings966/aws-cost-optimization",
        "=" * 60,
    ])

    message = "\n".join(message_lines)

    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        logger.info("Cost optimization report published to SNS")
    except Exception as error:
        logger.error(f"Failed to publish SNS report: {str(error)}")


def lambda_handler(event, context):
    """
    Main Lambda handler.
    Evaluates all running EC2 instances for CPU idleness
    and stops those that have been idle for the configured threshold.
    """
    logger.info("Starting AWS Cost Optimizer — Idle Instance Check")
    logger.info(
        f"Configuration: CPU threshold={CPU_IDLE_THRESHOLD}%, "
        f"Hours={IDLE_HOURS_THRESHOLD}"
    )

    stopped = []
    skipped = []
    no_data = []
    errors = []

    instances = get_running_instances()

    if not instances:
        logger.info("No running instances found. Nothing to evaluate.")
        return {
            "statusCode": 200,
            "body": json.dumps({
                "instances_evaluated": 0,
                "instances_stopped": 0,
                "instances_skipped": 0,
                "instances_no_data": 0,
                "errors": 0,
                "stopped_ids": []
            })
        }

    for instance in instances:
        instance_id = instance["instance_id"]
        avg_cpu = get_average_cpu(instance_id, IDLE_HOURS_THRESHOLD)

        if avg_cpu is None:
            logger.warning(
                f"No CPU data for {instance_id} — skipping"
            )
            no_data.append(instance)
            continue

        instance["avg_cpu"] = avg_cpu

        if avg_cpu < CPU_IDLE_THRESHOLD:
            logger.info(
                f"Instance {instance_id} is idle — "
                f"avg CPU: {avg_cpu}% — stopping"
            )
            success = stop_instance(instance_id)
            if success:
                stopped.append(instance)
            else:
                errors.append(
                    f"{instance_id} ({instance['name']}) — stop failed"
                )
        else:
            logger.info(
                f"Instance {instance_id} is active — "
                f"avg CPU: {avg_cpu}% — skipping"
            )
            skipped.append(instance)

    publish_report(stopped, skipped, no_data, errors)

    result = {
        "statusCode": 200,
        "body": json.dumps({
            "instances_evaluated": len(instances),
            "instances_stopped": len(stopped),
            "instances_skipped": len(skipped),
            "instances_no_data": len(no_data),
            "errors": len(errors),
            "stopped_ids": [i["instance_id"] for i in stopped]
        })
    }

    logger.info(f"Cost optimizer completed: {result['body']}")
    return result
