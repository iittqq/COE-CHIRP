import os
import boto3
import logging
import time

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ.get("CONNECTIONS_TABLE", "ChirpWebSocketConnections"))

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    qs = event.get("queryStringParameters") or {}
    device_id = qs.get("deviceId")
    if not device_id:
        return {"statusCode": 400, "body": "Missing deviceId"}

    connection_id = event["requestContext"]["connectionId"]
    ttl = int(time.time()) + 3600  # expire in 1 hour

    # Write or overwrite mapping
    table.put_item(Item={
        "deviceId": device_id,
        "connectionId": connection_id,
        "ttl": ttl
    })

    logger.info("Connected: %s -> %s", device_id, connection_id)

    return {"statusCode": 200, "body": f"Connected {device_id}"}
