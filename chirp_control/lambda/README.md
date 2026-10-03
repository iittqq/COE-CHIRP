# AWS backend (Lambda functions)

These are the functions behind the web and mobile apps, exported from the
deployed account. `remote_control.py` is **not** a Lambda — it runs on the
on-site phone (see [`../README.md`](../README.md)).

Region: the code hardcodes `us-east-2`; change it in the files if you deploy
elsewhere. Account IDs and API IDs below are placeholders.

## Functions

| File | Function name | Handler | Runtime | Timeout / memory | Behind |
| ---- | ------------- | ------- | ------- | ---------------- | ------ |
| `auth_handler.py` | `authHandler` | `auth_handler.handler` | Python 3.13 | 10 s / 128 MB | HTTP API `POST /auth` |
| `sonar_handler.py` | `sonarHandler` | `sonar_handler.handler` | Python 3.13+ | 3 s / 128 MB | HTTP API `GET`/`POST`/`DELETE /sonars` |
| `scan_handler.py` | `scanHandler` | `scan_handler.handler` | Python 3.13 | 15 s / 256 MB | HTTP API `GET`/`POST`/`PUT`/`DELETE /scans` |
| `connect_handler.py` | `connect` | `lambda_function.lambda_handler`* | Python 3.13 | 3 s / 128 MB | WebSocket `$connect` |
| `disconnect_handler.py` | `disconnect` | `lambda_function.lambda_handler`* | Python 3.13 | 3 s / 128 MB | WebSocket `$disconnect` |
| `send_message_handler.py` | `sendMessage` | `lambda_function.lambda_handler`* | Python 3.13 | 3 s / 128 MB | WebSocket `$default` |

\* These three are deployed with the file named `lambda_function.py`. Either
upload each as `lambda_function.py`, or set the handler to match the file name
here (e.g. `connect_handler.lambda_handler`).

None of the deployed functions use environment variables except `scanHandler`
(`SCANS_BUCKET`). The WebSocket functions optionally read `CONNECTIONS_TABLE`
(default `ChirpWebSocketConnections`) and `CONNECTION_ID_GSI` (default
`connectionId-index`); `sendMessage` only needs `APIGW_DOMAIN_NAME` and
`APIGW_STAGE` if an event arrives without a `requestContext`.

## APIs

**HTTP API** — one integration per function (payload format 2.0), `$default`
stage with auto-deploy, and CORS allowing `GET, POST, PUT, DELETE, OPTIONS`
from your web origins. Routes: `POST /auth`, `GET|POST|DELETE /sonars`,
`GET|POST|PUT|DELETE /scans`.

**WebSocket API** — route selection expression `$request.body.action`, stage
`test`. Routes: `$connect` → `connect`, `$disconnect` → `disconnect`,
`$default` → `sendMessage`, and `ping` as a MOCK integration. The app and the
on-site device both connect with `?deviceId=<id>`; the app sends
`{"target": "<deviceId>", ...}` and `sendMessage` relays it to that device's
connection.

## DynamoDB tables (all on-demand)

| Table | Partition key | Sort key | Used by |
| ----- | ------------- | -------- | ------- |
| `ChirpUserAccounts` | `email` (S) | — | `authHandler` |
| `RegisteredChirpSonars` | `user_id` (S) | `sonar_id` (S) | `sonarHandler` |
| `ChirpScans` | `user_id` (S) | `scan_id` (S) | `scanHandler` |
| `ChirpWebSocketConnections` | `deviceId` (S) | — | WebSocket functions (+ GSI `connectionId-index`) |

`ChirpWebSocketConnections` needs a global secondary index `connectionId-index`
(partition key `connectionId`, String; projection: keys only) so `disconnect` can
look up a device by connection ID. Without it, `disconnect` falls back to a
full-table scan.

Items carry a `ttl` attribute (1 hour) but TTL is deliberately **not** enabled on
the table: a device connected longer than an hour would lose its routing row and
stop receiving commands until it reconnected. Rows are instead overwritten on
each reconnect and deleted on disconnect.

Scan CSVs live in an S3 bucket (private, with a CORS rule allowing `GET`);
`scanHandler` returns presigned URLs.

## IAM (least privilege each function needs)

- `authHandler`: `dynamodb:GetItem`, `PutItem` on `ChirpUserAccounts`
- `sonarHandler`: `dynamodb:PutItem`, `Query`, `DeleteItem` on `RegisteredChirpSonars`
- `scanHandler`: `dynamodb:Query`, `PutItem`, `UpdateItem`, `DeleteItem` on `ChirpScans`; `s3:PutObject`, `GetObject`, `DeleteObject` on the bucket
- `connect`: `dynamodb:PutItem` on `ChirpWebSocketConnections`
- `sendMessage`: `dynamodb:GetItem`, `DeleteItem` on `ChirpWebSocketConnections`; `execute-api:ManageConnections` on the WebSocket API
- `disconnect`: `dynamodb:Query` (on the GSI), `Scan`, `DeleteItem` on `ChirpWebSocketConnections`

Each also needs the `AWSLambdaBasicExecutionRole` managed policy for logs, and
API Gateway needs `lambda:InvokeFunction` permission on each function.

The `disconnect` and `sendMessage` roles must have the `DeleteItem` (and, for
`disconnect`, `Query` on the index plus `Scan` for the fallback) permissions listed
above. Without them, stale-connection cleanup is silently denied. The unused
integrations for `tap`, `swipe`, `sendCommand`, `launch` and a `ping` Lambda were
removed from the WebSocket API; only the `ping` MOCK route remains.
