import json
import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ.get("CONNECTIONS_TABLE", "ChirpWebSocketConnections"))

def get_apigateway_client(event):
    # Try to extract domain and stage from event; fall back to env variable or static value
    try:
        domain_name = event["requestContext"]["domainName"]
        stage = event["requestContext"]["stage"]
    except Exception:
        # fallback for non-proxy integrations
        # No hardcoded default: set both env vars on the function if you rely on this path.
        domain_name = os.environ["APIGW_DOMAIN_NAME"]
        stage = os.environ["APIGW_STAGE"]
        logger.warning(f"requestContext missing; using fallback domain={domain_name}, stage={stage}")

    return boto3.client(
        "apigatewaymanagementapi",
        endpoint_url=f"https://{domain_name}/{stage}",
    )

def lambda_handler(event, context):
    logger.info("Received event: %s", event)

    # Handle both wrapped and direct message cases
    body = event.get("body")
    if isinstance(body, str):
        try:
            body = json.loads(body)
        except Exception:
            pass
    elif isinstance(event, dict) and "action" in event:
        body = event
    else:
        body = {}

    target_device = body.get("target") or body.get("deviceId")
    if not target_device:
        logger.warning("Missing deviceId in body: %s", body)
        return {"statusCode": 400, "body": "Missing deviceId"}

    # Lookup target connection in DynamoDB
    resp = table.get_item(Key={"deviceId": target_device})
    if "Item" not in resp:
        logger.warning("Device not found in DynamoDB: %s", target_device)
        return {"statusCode": 404, "body": f"No connection found for {target_device}"}

    target_connection = resp["Item"]["connectionId"]
    logger.info("Forwarding to %s (connection %s)", target_device, target_connection)

    apigw = get_apigateway_client(event)
    try:
        apigw.post_to_connection(
            ConnectionId=target_connection,
            Data=json.dumps(body)
        )
        logger.info("Message forwarded successfully")
    except apigw.exceptions.GoneException:
        logger.warning("Connection %s for %s is gone. Deleting from DynamoDB.",
                    target_connection, target_device)
        table.delete_item(Key={"deviceId": target_device})
        return {"statusCode": 410, "body": "Connection gone"}

