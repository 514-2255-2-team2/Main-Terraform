import json
import os
from decimal import Decimal
from urllib.parse import urlparse

import boto3

TABLE_NAME = os.environ.get("TABLE_NAME", "Players")
BUCKET_NAME = os.environ.get("BUCKET_NAME", "athlete-photos-team2")
SIGNED_URL_EXPIRES = int(os.environ.get("SIGNED_URL_EXPIRES", "3600"))

ddb = boto3.resource("dynamodb")
s3 = boto3.client("s3")

# so the react page can call this from anywhere
CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
}

# Helper function for parsing the S3 uri
def parse_s3_uri(s3_uri):
    p = urlparse(s3_uri or "")
    if p.scheme != "s3" or not p.netloc or not p.path:
        raise ValueError("bad s3 uri")
    return p.netloc, p.path.lstrip("/")

# Helper function because dynamodb returns Decimal sometimes
def json_default(v):
    if isinstance(v, Decimal):
        return int(v) if v == int(v) else float(v)
    raise TypeError(f"Object of type {type(v).__name__} is not JSON serializable")

def lambda_handler(event, context):
    try:
        # code for CORS return
        m = (event.get("requestContext") or {}).get("http") or {}
        if m.get("method") == "OPTIONS":
            return {"statusCode": 204, "headers": CORS, "body": ""}

        # Parses the input --------------------------------------------------------
        data = {}
        body = event.get("body")
        if body:
            data = json.loads(body) if isinstance(body, str) else body
        elif event:
            data = event

        # Requires player_id in payload
        pid = str(data.get("player_id") or "").strip()
        if not pid:
            return {"statusCode": 400, "headers": CORS, "body": json.dumps({"error": "need player_id"})}

        # Gets the player from DynamoDB
        table = ddb.Table(TABLE_NAME)
        resp = table.get_item(Key={"player_id": pid})
        player = resp.get("Item")

        if not player:
            return {"statusCode": 404, "headers": CORS, "body": json.dumps({"error": "player not found"})}

        # Figures out where the player image is
        bucket = None
        key = None

        if player.get("s3_url"):
            bucket, key = parse_s3_uri(player["s3_url"])
        elif player.get("s3_key"):
            bucket, key = BUCKET_NAME, player["s3_key"]

        image_url = None
        image_s3_uri = None

        # Builds a temporary URL for the frontend to display
        if bucket and key:
            image_s3_uri = f"s3://{bucket}/{key}"
            image_url = s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": bucket, "Key": key},
                ExpiresIn=SIGNED_URL_EXPIRES,
            )

        out = {
            "player": player,
            "image_url": image_url,
            "image_s3_uri": image_s3_uri,
        }

        return {
            "statusCode": 200,
            "headers": CORS,
            "body": json.dumps(out, default=json_default),
        }
    except Exception as e:
        return {"statusCode": 500, "headers": CORS, "body": json.dumps({"error": str(e)})}