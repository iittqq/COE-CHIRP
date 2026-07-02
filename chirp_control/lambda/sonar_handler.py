import boto3
import json

dynamodb = boto3.resource('dynamodb', region_name='us-east-2')
table = dynamodb.Table('RegisteredChirpSonars')

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
    'Content-Type': 'application/json',
}


def _get_method(event):
    # REST API (v1): httpMethod / HTTP API (v2): requestContext.http.method
    if 'httpMethod' in event:
        return event['httpMethod']
    return event.get('requestContext', {}).get('http', {}).get('method', '')


def handler(event, context):
    print("EVENT:", json.dumps(event))

    method = _get_method(event)
    qs = event.get('queryStringParameters') or {}

    if method == 'OPTIONS':
        return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': ''}

    try:
        if method == 'GET':
            from boto3.dynamodb.conditions import Key
            result = table.query(
                KeyConditionExpression=Key('user_id').eq(qs['user_id'])
            )
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS,
                'body': json.dumps({'sonars': result['Items']}),
            }

        if method == 'POST':
            body = json.loads(event.get('body') or '{}')
            table.put_item(Item={
                'user_id': body['user_id'],
                'sonar_id': body['sonar_id'],
                'name': body['name'],
                'status': body.get('status', 'Active'),
            })
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS,
                'body': json.dumps({'success': True}),
            }

        if method == 'DELETE':
            table.delete_item(Key={
                'user_id': qs['user_id'],
                'sonar_id': qs['sonar_id'],
            })
            return {
                'statusCode': 200,
                'headers': CORS_HEADERS,
                'body': json.dumps({'success': True}),
            }

    except Exception as e:
        print("ERROR:", str(e))
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': str(e)}),
        }

    print(f"UNMATCHED method={method}")
    return {
        'statusCode': 400,
        'headers': CORS_HEADERS,
        'body': json.dumps({'error': f'No handler for method {method}'}),
    }