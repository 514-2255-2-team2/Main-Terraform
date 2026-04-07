import base64
import json
import os
import uuid
from datetime import datetime

import boto3

BUCKET_NAME = os.environ.get("BUCKET_NAME", "")
s3 = boto3.client("s3")

# so the react page can call this from anywhere
CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "OPTIONS,POST",
}

# Helper function for parsing data:image/...;base64,...
def parse_data_url(image_base64):
    content_type = "image/jpeg"
    data = image_base64 or ""

    if data.startswith("data:"):
        header, encoded = data.split(",", 1)
        if ";" in header:
            content_type = header.split(";")[0].replace("data:", "").strip() or content_type
        return content_type, encoded

    return content_type, data

# Helper function for figuring out the file extension
def content_type_to_ext(content_type):
    m = {
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
    }
    return m.get((content_type or "").lower(), ".jpg")

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

        # Requires image_base64 in payload
        image_base64 = data.get("image_base64")
        if not image_base64:
            return {"statusCode": 400, "headers": CORS, "body": json.dumps({"error": "need image_base64"})}

        if not BUCKET_NAME:
            return {"statusCode": 500, "headers": CORS, "body": json.dumps({"error": "missing bucket config"})}

        # Parses the image and decodes it
        content_type, encoded = parse_data_url(image_base64)
        raw = base64.b64decode(encoded)

        # Creates the object key if one wasnt given
        object_key = str(data.get("object_key") or "").strip()
        if not object_key:
            now = datetime.utcnow()
            ext = content_type_to_ext(content_type)
            object_key = f"user-uploads/{now.strftime('%Y/%m/%d')}/{uuid.uuid4().hex}{ext}"

        # Uploads the image to S3
        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=object_key,
            Body=raw,
            ContentType=content_type,
        )

        s3_uri = f"s3://{BUCKET_NAME}/{object_key}"

        return {
            "statusCode": 200,
            "headers": CORS,
            "body": json.dumps({
                "bucket_name": BUCKET_NAME,
                "object_key": object_key,
                "image_s3_uri": s3_uri,
                "s3_uri": s3_uri,
                "content_type": content_type,
            }),
        }
    except Exception as e:
        return {"statusCode": 500, "headers": CORS, "body": json.dumps({"error": str(e)})}