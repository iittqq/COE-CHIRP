import boto3
import hashlib
import hmac
import json
import os
import re
import uuid
from datetime import datetime, timezone

dynamodb = boto3.resource('dynamodb', region_name='us-east-2')
table = dynamodb.Table('ChirpUserAccounts')

CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'POST,OPTIONS',
    'Content-Type': 'application/json',
}

PBKDF2_ITERATIONS = 200_000
# Loose sanity check only - "no email validation needed" per product decision,
# this just rejects obviously-empty/garbage input, not RFC 5322 correctness.
EMAIL_RE = re.compile(r'^\S+@\S+\.\S+$')


def _get_method(event):
    if 'httpMethod' in event:
        return event['httpMethod']
    return event.get('requestContext', {}).get('http', {}).get('method', '')


def _response(status, body):
    return {'statusCode': status, 'headers': CORS_HEADERS, 'body': json.dumps(body)}


def _hash_password(password: str, salt: bytes) -> str:
    return hashlib.pbkdf2_hmac(
        'sha256', password.encode('utf-8'), salt, PBKDF2_ITERATIONS
    ).hex()


def _register(body):
    email = (body.get('email') or '').strip().lower()
    password = body.get('password') or ''

    if not EMAIL_RE.match(email):
        return _response(400, {'error': 'A valid email is required.'})
    if len(password) < 8:
        return _response(400, {'error': 'Password must be at least 8 characters.'})

    existing = table.get_item(Key={'email': email}).get('Item')
    if existing:
        return _response(409, {'error': 'An account with this email already exists.'})

    salt = os.urandom(16)
    user_id = str(uuid.uuid4())
    table.put_item(
        Item={
            'email': email,
            'user_id': user_id,
            'password_salt': salt.hex(),
            'password_hash': _hash_password(password, salt),
            'created_at': datetime.now(timezone.utc).isoformat(),
        },
        ConditionExpression='attribute_not_exists(email)',
    )
    return _response(200, {'user_id': user_id, 'email': email})


def _reset_password(body):
    # Proof-of-concept "forgot password": there is no email/token verification,
    # so anyone who knows an account's email can set a new password for it.
    # Acceptable only because this app holds no sensitive data - revisit before
    # any real deployment (see request_reset/confirm_reset via SES).
    email = (body.get('email') or '').strip().lower()
    password = body.get('password') or ''

    if not EMAIL_RE.match(email):
        return _response(400, {'error': 'A valid email is required.'})
    if len(password) < 8:
        return _response(400, {'error': 'Password must be at least 8 characters.'})

    item = table.get_item(Key={'email': email}).get('Item')
    if not item:
        return _response(404, {'error': 'No account found for that email.'})

    salt = os.urandom(16)
    # Re-put the whole item (the role has PutItem, not UpdateItem). We hold every
    # attribute from the get_item above, so this only rotates the salt/hash and
    # stamps password_updated_at - user_id/created_at/etc. are preserved.
    item['password_salt'] = salt.hex()
    item['password_hash'] = _hash_password(password, salt)
    item['password_updated_at'] = datetime.now(timezone.utc).isoformat()
    table.put_item(Item=item)

    return _response(200, {'user_id': item['user_id'], 'email': email})


def _login(body):
    email = (body.get('email') or '').strip().lower()
    password = body.get('password') or ''

    item = table.get_item(Key={'email': email}).get('Item')
    if not item:
        return _response(401, {'error': 'Invalid email or password.'})

    salt = bytes.fromhex(item['password_salt'])
    candidate_hash = _hash_password(password, salt)
    if not hmac.compare_digest(candidate_hash, item['password_hash']):
        return _response(401, {'error': 'Invalid email or password.'})

    return _response(200, {'user_id': item['user_id'], 'email': email})


def handler(event, context):
    print("EVENT:", json.dumps(event))

    method = _get_method(event)
    if method == 'OPTIONS':
        return {'statusCode': 200, 'headers': CORS_HEADERS, 'body': ''}

    if method != 'POST':
        return _response(400, {'error': f'No handler for method {method}'})

    try:
        body = json.loads(event.get('body') or '{}')
        action = body.get('action')

        if action == 'register':
            return _register(body)
        if action == 'login':
            return _login(body)
        if action == 'reset_password':
            return _reset_password(body)

        return _response(
            400,
            {'error': "action must be 'register', 'login', or 'reset_password'"},
        )

    except table.meta.client.exceptions.ConditionalCheckFailedException:
        return _response(409, {'error': 'An account with this email already exists.'})
    except Exception as e:
        print("ERROR:", str(e))
        return _response(500, {'error': str(e)})
