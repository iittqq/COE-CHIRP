import boto3
import json
import os
import uuid
from boto3.dynamodb.conditions import Key
from botocore.config import Config

REGION = 'us-east-2'
BUCKET = os.environ.get('SCANS_BUCKET', 'chirp-scan-data')
URL_TTL_SECONDS = 900

dynamodb = boto3.resource('dynamodb', region_name=REGION)
table = dynamodb.Table('ChirpScans')
# Regional endpoint + SigV4 so presigned URLs point straight at the bucket's
# region. The global endpoint answers 307, and browsers drop CORS on redirects.
s3 = boto3.client(
    's3',
    region_name=REGION,
    endpoint_url=f'https://s3.{REGION}.amazonaws.com',
    config=Config(signature_version='s3v4', s3={'addressing_style': 'virtual'}),
)

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
    'Content-Type': 'application/json',
}

# Scan metadata (title, notes, ...) lives in DynamoDB; the raw CSVs live in S3
# because they can exceed DynamoDB's 400 KB item limit. Reads return presigned
# S3 URLs rather than inline CSV so a long history can't blow past the 6 MB
# Lambda response limit.


def _get_method(event):
    if 'httpMethod' in event:
        return event['httpMethod']
    return event.get('requestContext', {}).get('http', {}).get('method', '')


def _response(status, body):
    return {'statusCode': status, 'headers': CORS_HEADERS, 'body': json.dumps(body)}


def _csv_key(user_id, scan_id, kind):
    return f'{user_id}/{scan_id}/{kind}.csv'


def _put_csv(user_id, scan_id, kind, text):
    s3.put_object(
        Bucket=BUCKET,
        Key=_csv_key(user_id, scan_id, kind),
        Body=(text or '').encode('utf-8'),
        ContentType='text/csv',
    )


def _presign(user_id, scan_id, kind):
    return s3.generate_presigned_url(
        'get_object',
        Params={'Bucket': BUCKET, 'Key': _csv_key(user_id, scan_id, kind)},
        ExpiresIn=URL_TTL_SECONDS,
    )


def _to_api(item):
    user_id, scan_id = item['user_id'], item['scan_id']
    return {
        'id': scan_id,
        'folderName': item['folder_name'],
        'title': item.get('title', ''),
        'location': item.get('location', ''),
        'notes': item.get('notes', ''),
        'sonarCsvUrl': _presign(user_id, scan_id, 'sonar'),
        'bathymetryCsvUrl': _presign(user_id, scan_id, 'bathymetry'),
    }


def _list(user_id):
    items = []
    kwargs = {'KeyConditionExpression': Key('user_id').eq(user_id), 'ConsistentRead': True}
    while True:
        result = table.query(**kwargs)
        items.extend(result['Items'])
        if 'LastEvaluatedKey' not in result:
            break
        kwargs['ExclusiveStartKey'] = result['LastEvaluatedKey']
    return [_to_api(i) for i in items]


def handler(event, context):
    method = _get_method(event)
    qs = event.get('queryStringParameters') or {}

    if method == 'OPTIONS':
        return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': ''}

    try:
        if method == 'GET':
            return _response(200, {'scans': _list(qs['user_id'])})

        if method == 'POST':
            # Create a scan, or overwrite one in place when scan_id is given.
            body = json.loads(event.get('body') or '{}')
            user_id = body['user_id']
            scan_id = body.get('scan_id') or str(uuid.uuid4())
            _put_csv(user_id, scan_id, 'sonar', body.get('sonar_csv'))
            _put_csv(user_id, scan_id, 'bathymetry', body.get('bathymetry_csv'))
            item = {
                'user_id': user_id,
                'scan_id': scan_id,
                'folder_name': body['folder_name'],
                'title': '',
                'location': '',
                'notes': '',
            }
            table.put_item(Item=item)
            return _response(200, {'scan': _to_api(item)})

        if method == 'PUT':
            # Partial metadata update: only title and notes are editable.
            body = json.loads(event.get('body') or '{}')
            names, values, sets = {}, {}, []
            for field in ('title', 'notes'):
                if field in body:
                    names[f'#{field}'] = field
                    values[f':{field}'] = body[field]
                    sets.append(f'#{field} = :{field}')
            if not sets:
                return _response(400, {'error': 'Nothing to update'})
            table.update_item(
                Key={'user_id': body['user_id'], 'scan_id': body['scan_id']},
                UpdateExpression='SET ' + ', '.join(sets),
                ExpressionAttributeNames=names,
                ExpressionAttributeValues=values,
                ConditionExpression='attribute_exists(scan_id)',
            )
            return _response(200, {'success': True})

        if method == 'DELETE':
            user_id, scan_id = qs['user_id'], qs['scan_id']
            table.delete_item(Key={'user_id': user_id, 'scan_id': scan_id})
            s3.delete_objects(
                Bucket=BUCKET,
                Delete={'Objects': [
                    {'Key': _csv_key(user_id, scan_id, 'sonar')},
                    {'Key': _csv_key(user_id, scan_id, 'bathymetry')},
                ]},
            )
            return _response(200, {'success': True})

    except KeyError as e:
        return _response(400, {'error': f'Missing field: {e}'})
    except Exception as e:
        print('ERROR:', str(e))
        return _response(500, {'error': str(e)})

    return _response(400, {'error': f'No handler for method {method}'})
