"""Writes each export request from the queue to the exports bucket; a request that fails is retried on its own."""
import json
import os

import boto3

def handler(event, context):
    s3 = boto3.client("s3")
    bucket = os.environ.get("BUCKET", "")
    failures = []
    for record in event.get("Records", []):
        try:
            request = json.loads(record["body"])
            s3.put_object(Bucket=bucket, Key=f"requests/{record['messageId']}.json", Body=json.dumps(request).encode())
        except Exception as error:
            print(json.dumps({"level": "error", "message_id": record.get("messageId"), "error": str(error)}))
            failures.append({"itemIdentifier": record["messageId"]})
    return {"batchItemFailures": failures}
