import json
import os

import boto3
from boto3.dynamodb.conditions import Attr

import re
from urllib.parse import urlparse

TABLE_NAME = os.environ.get("TABLE_NAME", "Players")
BUCKET_NAME = os.environ.get("BUCKET_NAME", "rit-athlete-photos-team2")
FACE_KEY = "face_id"

ddb = boto3.resource("dynamodb")
rek = boto3.client("rekognition")

# Takes in team name and simplifies it removing extra chars, spaces, lowers() etc
def team_to_collection_id(team_name):
    s = (team_name or "").strip().lower()
    if not s:
        return "unknown-team"
    s = s.replace("&", "and")
    s = re.sub(r"[^a-z0-9_.-]+", "-", s)
    s = re.sub(r"-+", "-", s).strip("-.")
    return s or "unknown-team"

# Helper function for parsing the S3 uri
def parse_s3_uri(s3_uri):
    p = urlparse(s3_uri or "")
    if p.scheme != "s3" or not p.netloc or not p.path:
        raise ValueError("bad s3 uri")
    return p.netloc, p.path.lstrip("/")

def lambda_handler(event, context):
    # This is what the lambda function returns
    stats = {"indexed": 0, "skipped": 0, "errors": []}

    # Gets table name
    table = ddb.Table(TABLE_NAME)

    # Filter for finding players without a face_id and also have a S3 image
    player_filter = (Attr(FACE_KEY).not_exists() | Attr(FACE_KEY).eq("")) & (Attr("s3_key").exists() | Attr("s3_url").exists())

    # Scans table for the players using the filter expression
    items = []
    scan_args = {"FilterExpression": player_filter}
    # While true since there can be multiple pages so we keep scanning until we get to the last player
    while True:
        resp = table.scan(**scan_args)
        items.extend(resp.get("Items", []))
        lek = resp.get("LastEvaluatedKey")
        if not lek:
            break
        scan_args["ExclusiveStartKey"] = lek

    # For each player 
    for item in items:
        try:
            pid = str(item.get("player_id", "")).strip()
            team = str(item.get("team", "")).strip()

            # Requires player to have a id and team
            if not pid or not team:
                stats["skipped"] += 1
                continue
            
            # Retrieves the image from the bucket
            if item.get("s3_url"):
                bucket, key = parse_s3_uri(item["s3_url"])
            else:
                bucket, key = BUCKET_NAME, item["s3_key"]

            # Ensures there is a collection for the players team
            cid = team_to_collection_id(team)
            try:
                rek.create_collection(CollectionId=cid)
            except rek.exceptions.ResourceAlreadyExistsException:
                pass

            # Index players face using rekognition
            out = rek.index_faces(
                CollectionId=cid,
                Image={"S3Object": {"Bucket": bucket, "Name": key}},
                ExternalImageId=pid,
                DetectionAttributes=[],
            )

            # If the indexing didnt work mark player as skipped
            recs = out.get("FaceRecords", [])
            if not recs:
                stats["skipped"] += 1
                continue
            
            # Updates table with the face_id
            fid = recs[0]["Face"]["FaceId"]
            table.update_item(
                Key={"player_id": pid},
                UpdateExpression=f"SET {FACE_KEY} = :f, face_collection = :c",
                ExpressionAttributeValues={":f": fid, ":c": cid},
            )

            stats["indexed"] += 1
        except Exception as e:
            stats["errors"].append(str(e))

    return {"statusCode": 200, "body": json.dumps(stats)}
