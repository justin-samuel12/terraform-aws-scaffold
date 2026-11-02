"""A daily report: counts the objects in the exports bucket and logs the total."""
import json
import os

import boto3


def handler(event, context):
    s3 = boto3.client("s3")
    bucket = os.environ.get("BUCKET", "")
    total = 0
    if bucket:
        for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket):
            total += page.get("KeyCount", 0)
    print(json.dumps({"level": os.environ.get("LEVEL", "info"), "bucket": bucket, "objects": total}))
    return {"objects": total}
