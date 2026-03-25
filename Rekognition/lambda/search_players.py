import json
import os

import boto3

import re
from urllib.parse import urlparse

BUCKET = os.environ.get("BUCKET_NAME", "athlete-photos-team2")
rek = boto3.client("rekognition")

# so the react page can call this from anywhere
CORS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "content-type",
    "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
}

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

        # Requires teams_names in payload
        teams = data.get("team_names") or []
        if not teams:
            return {"statusCode": 400, "headers": CORS, "body": json.dumps({"error": "need team_names"})}

        # Sets return_count
        return_count = int(data.get("return_count", 3))

        # Gets the users uploaded image from the S3 bucket
        if data.get("image_s3_uri"):
            bucket, key = parse_s3_uri(data["image_s3_uri"])
        else:
            bucket = data.get("bucket_name") or BUCKET
            key = data.get("object_key")
        if not key:
            return {"statusCode": 400, "headers": CORS, "body": json.dumps({"error": "need image_s3_uri or object_key"})}
        
        # Compares users face to -----------------------------------------------------------------
        best = {}
        # For each team given compare the users face
        for team in teams:
            cid = team_to_collection_id(team)
            if not cid:
                continue

            # Runs the rekognition and returns "return_count" players that are similar
            try:
                r = rek.search_faces_by_image(
                    CollectionId=cid,
                    Image={"S3Object": {"Bucket": bucket, "Name": key}},
                    MaxFaces=return_count,
                    FaceMatchThreshold=0,
                )
            except rek.exceptions.ResourceNotFoundException:
                continue
            
            # For each match 
            for match in r.get("FaceMatches", []):
                face = match.get("Face", {})

                # Gets the player_id
                pid = str(face.get("ExternalImageId") or "").strip()
                if not pid:
                    continue
                
                # Add the player to the dictionary
                best[pid] = float(match.get("Similarity", 0))

        # Sorts the players from highest similarly to lowest
        out = [{"player_id": p, "similarity": s} for p, s in best.items()]
        out.sort(key=lambda x: x["similarity"], reverse=True)
        out = out[:return_count] # returns return_count of players

        return {"statusCode": 200, "headers": CORS, "body": json.dumps({"matches": out})}
    except Exception as e:
        return {"statusCode": 500, "headers": CORS, "body": json.dumps({"error": str(e)})}
