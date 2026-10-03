import os
import boto3
import logging
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ.get("CONNECTIONS_TABLE", "ChirpWebSocketConnections"))

logger = logging.getLogger()
logger.setLevel(logging.INFO)

GSI_NAME = os.environ.get("CONNECTION_ID_GSI", "connectionId-index")

def lambda_handler(event, context):
    connection_id = event["requestContext"]["connectionId"]
    logger.info("Disconnect: %s", connection_id)

    try:
        # Try to find the device using the GSI
        resp = table.query(
            IndexName=GSI_NAME,
            KeyConditionExpression=Key("connectionId").eq(connection_id),
            ProjectionExpression="deviceId"
        )
        items = resp.get("Items", [])
        if items:
            for it in items:
                table.delete_item(Key={"deviceId": it["deviceId"]})
                logger.info("Disconnected and removed deviceId: %s", it["deviceId"])
            return {"statusCode": 200, "body": "Disconnected (GSI cleanup)"}
    except Exception as e:
        logger.warning("GSI query failed or missing: %s", e)

    # Fallback scan (slow, but safe for small tables)
    resp = table.scan(ProjectionExpression="deviceId, connectionId")
    for it in resp.get("Items", []):
        if it.get("connectionId") == connection_id:
            table.delete_item(Key={"deviceId": it["deviceId"]})
            logger.info("Disconnected and removed via scan: %s", it["deviceId"])
            break

    return {"statusCode": 200, "body": "Disconnected"}
