import json
import os
import time
import unicodedata
from decimal import Decimal
from functools import wraps
from typing import Dict, List, Optional
from urllib.parse import quote_plus, urlparse

import boto3
import requests

s3_client = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
API_KEY = os.environ.get("SPORTSDB_KEY", "3").strip()
SPORTS_DB_BASE_URL = f"https://www.thesportsdb.com/api/v1/json/{API_KEY}"

REQUESTS_PER_MINUTE = 25
MAX_RETRIES = 5
INITIAL_BACKOFF = 2

DEBUG_LOG_PLAYERS = False  

LEAGUE_NAMES = {
    "nfl": "NFL",
    "nba": "NBA",
    "mlb": "MLB",
    "nhl": "NHL",
    "epl": "English Premier League",
    "mls": "Major League Soccer",
}

# ──────────────────────────────────────────────
# Rate limiter
# ──────────────────────────────────────────────
class RateLimiter:
    def __init__(self, requests_per_minute: int = 25):
        self.interval = 60.0 / requests_per_minute
        self.last_request_time = 0.0

    def wait(self):
        elapsed = time.time() - self.last_request_time
        if elapsed < self.interval:
            time.sleep(self.interval - elapsed)
        self.last_request_time = time.time()


rate_limiter = RateLimiter(REQUESTS_PER_MINUTE)


# ──────────────────────────────────────────────
# Retry decorator
# ──────────────────────────────────────────────
def retry_with_backoff(max_retries: int = MAX_RETRIES, initial_backoff: float = INITIAL_BACKOFF):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            backoff = initial_backoff
            for attempt in range(1, max_retries + 1):
                try:
                    return func(*args, **kwargs)
                except requests.exceptions.HTTPError as e:
                    status = e.response.status_code if e.response is not None else None
                    if status == 429:
                        wait = int(e.response.headers.get("Retry-After", backoff))
                        print(f"Rate limited (429). Waiting {wait}s (attempt {attempt}/{max_retries})")
                        time.sleep(wait)
                    elif status in {500, 502, 503, 504}:
                        print(f"Server error ({status}). Retrying in {backoff}s (attempt {attempt}/{max_retries})")
                        time.sleep(backoff)
                        backoff *= 2
                    else:
                        raise
                except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as e:
                    print(f"{type(e).__name__}. Retrying in {backoff}s (attempt {attempt}/{max_retries})")
                    time.sleep(backoff)
                    backoff *= 2
            raise Exception(f"Max retries ({max_retries}) exceeded for {func.__name__}")
        return wrapper
    return decorator


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
def to_ascii(value: str) -> str:
    """Strip non-ASCII characters (required for S3 metadata)."""
    return unicodedata.normalize("NFKD", value or "").encode("ascii", "ignore").decode("ascii")


def pick_player_image(player: Dict) -> Optional[str]:
    """Return the best available image URL (Cutout → Thumb → Render)."""
    for key in ("strCutout", "strThumb", "strRender"):
        url = (player.get(key) or "").strip()
        if url and url.lower() not in {"null", "none"} and "placeholder" not in url.lower():
            return url
    return None


def convert_floats(obj):
    """Recursively convert floats to Decimal for DynamoDB compatibility."""
    if isinstance(obj, float):
        return Decimal(str(obj))
    if isinstance(obj, dict):
        return {k: convert_floats(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [convert_floats(i) for i in obj]
    return obj


# ──────────────────────────────────────────────
# Checkpoint helpers
# S3 path: s3://{bucket}/checkpoints/{league}_checkpoint.json
# ──────────────────────────────────────────────
def _checkpoint_key(league: str) -> str:
    return f"checkpoints/{league}_checkpoint.json"


def load_checkpoint(bucket: str, league: str) -> Dict:
    """
    Load the progress checkpoint from S3.

    The checkpoint tracks which teams and players have already been fully
    processed so the Lambda can resume safely after a timeout or failure.

    Schema:
        {
            "processed_teams":   [<team_name>, ...],   # team names completed
            "processed_players": [<player_id>, ...],   # player IDs saved to DB
            "last_team":         "<team_name>",         # last successfully completed team
            "stats": {
                "teams_processed": int,
                "players_found":   int,
                "photos_uploaded": int
            }
        }
    """
    empty = {
        "processed_teams": [],
        "processed_players": [],
        "last_team": None,
        "stats": {"teams_processed": 0, "players_found": 0, "photos_uploaded": 0},
    }
    try:
        resp = s3_client.get_object(Bucket=bucket, Key=_checkpoint_key(league))
        checkpoint = json.loads(resp["Body"].read().decode("utf-8"))
        print(f"Checkpoint loaded: {len(checkpoint.get('processed_teams', []))} teams already done")
        return checkpoint
    except s3_client.exceptions.NoSuchKey:
        print("No checkpoint found – starting fresh")
    except Exception as e:
        print(f"⚠ Could not load checkpoint ({e}) – starting fresh")
    return empty


def save_checkpoint(bucket: str, league: str, checkpoint: Dict):
    """Persist the checkpoint to S3 after each completed team."""
    try:
        s3_client.put_object(
            Bucket=bucket,
            Key=_checkpoint_key(league),
            Body=json.dumps(checkpoint, indent=2),
            ContentType="application/json",
        )
        print(f"Checkpoint saved: {checkpoint['stats']['teams_processed']} teams done")
    except Exception as e:
        print(f"Could not save checkpoint: {e}")


def delete_checkpoint(bucket: str, league: str):
    """Remove the checkpoint once all teams are fully processed."""
    try:
        s3_client.delete_object(Bucket=bucket, Key=_checkpoint_key(league))
        print("Checkpoint cleared (all teams complete)")
    except Exception:
        pass


# ──────────────────────────────────────────────
# API calls
# ──────────────────────────────────────────────
@retry_with_backoff()
def get_teams_in_league(league: str) -> List[Dict]:
    league_name = LEAGUE_NAMES.get(league)
    if not league_name:
        raise ValueError(f"Unknown league '{league}'. Available: {list(LEAGUE_NAMES)}")

    rate_limiter.wait()
    url = f"{SPORTS_DB_BASE_URL}/search_all_teams.php?l={quote_plus(league_name)}"
    print(f"Fetching teams: {url}")
    r = requests.get(url, timeout=15)
    r.raise_for_status()
    teams = r.json().get("teams") or []

    if teams and league == "nfl":
        sport = (teams[0].get("strSport") or "").lower()
        if sport and sport != "american football":
            raise Exception(
                f"Wrong sport '{teams[0].get('strSport')}' returned for NFL – "
                f"first team was '{teams[0].get('strTeam')}'"
            )

    return teams


@retry_with_backoff()
def get_players_in_team(team_id: str) -> List[Dict]:
    if not team_id:
        return []
    rate_limiter.wait()
    r = requests.get(f"{SPORTS_DB_BASE_URL}/lookup_all_players.php?id={team_id}", timeout=15)
    r.raise_for_status()
    return r.json().get("player") or []


# ──────────────────────────────────────────────
# S3 image upload
# ──────────────────────────────────────────────
@retry_with_backoff()
def upload_player_image(image_url: str, player_id: str, player_name: str, bucket: str, league: str) -> Optional[str]:
    if not image_url or "placeholder" in image_url.lower():
        return None

    rate_limiter.wait()
    r = requests.get(image_url, timeout=20)
    r.raise_for_status()

    content_type = r.headers.get("content-type", "")
    if "image" not in content_type and len(r.content) < 1000:
        print(f"  ⚠ Invalid image for {player_name}")
        return None

    ext = os.path.splitext(urlparse(image_url).path)[1] or ".jpg"
    safe_name = to_ascii(player_name).replace(" ", "_").replace("/", "_")
    s3_key = f"players/{league}/{player_id}_{safe_name}{ext}"

    s3_client.put_object(
        Bucket=bucket,
        Key=s3_key,
        Body=r.content,
        ContentType=content_type or "image/jpeg",
        Metadata={
            "player_id": str(player_id),
            "player_name": to_ascii(player_name),
            "league": league,
            "source_url": to_ascii(image_url),
        },
    )
    print(f"  ✓ Uploaded: {player_name}")
    return s3_key


# ──────────────────────────────────────────────
# DynamoDB save
# ──────────────────────────────────────────────
def save_player(player_data: Dict, table_name: str) -> bool:
    try:
        table = dynamodb.Table(table_name)
        item = convert_floats(player_data)
        item["updated_at"] = int(time.time())
        table.put_item(Item=item)
        return True
    except Exception as e:
        print(f"  ✗ DynamoDB error: {e}")
        return False


# ──────────────────────────────────────────────
# Core scraping logic
# ──────────────────────────────────────────────
def scrape_league(
    league: str,
    bucket: str,
    table_name: str,
    max_teams: Optional[int] = None,
    resume: bool = True,
    specific_teams: Optional[List[str]] = None,
) -> Dict:
    checkpoint = load_checkpoint(bucket, league) if resume else {
        "processed_teams": [],
        "processed_players": [],
        "last_team": None,
        "stats": {"teams_processed": 0, "players_found": 0, "photos_uploaded": 0},
    }

    stats = {
        "league": league,
        "teams_processed": checkpoint["stats"]["teams_processed"],
        "players_found": checkpoint["stats"]["players_found"],
        "players_with_images": 0,
        "players_without_images": 0,
        "photos_uploaded": checkpoint["stats"]["photos_uploaded"],
        "photo_failures": 0,
        "dynamodb_saves": 0,
        "dynamodb_failures": 0,
        "skipped_existing": 0,
        "skipped_no_image": 0,
        "skipped_bad_upload": 0,
        "api_calls": 0,
        "errors": [],
    }

    print(f"\n{'='*60}\nScraping {league.upper()}\n{'='*60}\n")

    all_teams = get_teams_in_league(league)
    stats["api_calls"] += 1

    if specific_teams:
        wanted = {s.strip().lower() for s in specific_teams if s}
        all_teams = [t for t in all_teams if (t.get("strTeam") or "").lower() in wanted]
        print(f"Filtered to {len(all_teams)} specific team(s)")

    done_teams = set(checkpoint["processed_teams"])
    queue = [t for t in all_teams if t.get("strTeam") and t["strTeam"] not in done_teams]
    print(f"Already done: {len(done_teams)} | Remaining: {len(queue)}\n")

    if max_teams:
        queue = queue[:max_teams]
        print(f"Capped at {max_teams} teams this run\n")

    for i, team in enumerate(queue, 1):
        team_name = team["strTeam"]
        team_id = team.get("idTeam")
        if not team_id:
            continue

        print(f"{'='*60}\nTeam {i}/{len(queue)}: {team_name}\n{'='*60}")

        try:
            players = get_players_in_team(team_id)
            stats["api_calls"] += 1
            print(f"Found {len(players)} players")

            saved_this_team = 0

            for player in players:
                pid = player.get("idPlayer")
                name = player.get("strPlayer")
                if not pid or not name:
                    continue

                if pid in checkpoint["processed_players"]:
                    stats["skipped_existing"] += 1
                    continue

                stats["players_found"] += 1
                image_url = pick_player_image(player)

                if not image_url:
                    stats["players_without_images"] += 1
                    stats["skipped_no_image"] += 1
                    print(f"  ⏭ No image: {name}")
                    continue

                stats["players_with_images"] += 1

                try:
                    s3_key = upload_player_image(image_url, str(pid), name, bucket, league)
                    stats["api_calls"] += 1
                except Exception as e:
                    print(f"  ✗ Upload error for {name}: {e}")
                    s3_key = None

                if not s3_key:
                    stats["photo_failures"] += 1
                    stats["skipped_bad_upload"] += 1
                    continue

                stats["photos_uploaded"] += 1

                player_record = {
                    "player_id": str(pid),
                    "league": league,
                    "name": name,
                    "team": team_name,
                    "team_id": str(team_id),
                    "position": player.get("strPosition", "Unknown"),
                    "nationality": player.get("strNationality", "Unknown"),
                    "birth_date": player.get("dateBorn", "Unknown"),
                    "height": player.get("strHeight", "Unknown"),
                    "weight": player.get("strWeight", "Unknown"),
                    "description": player.get("strDescriptionEN") or "",
                    "has_image": True,
                    "original_image_url": image_url,
                    "s3_key": s3_key,
                    "s3_url": f"s3://{bucket}/{s3_key}",
                }

                if save_player(player_record, table_name):
                    stats["dynamodb_saves"] += 1
                    saved_this_team += 1
                    checkpoint["processed_players"].append(pid)
                else:
                    stats["dynamodb_failures"] += 1

            print(f"\n📊 {team_name}: {len(players)} found, {saved_this_team} saved\n")

            checkpoint["processed_teams"].append(team_name)
            checkpoint["last_team"] = team_name
            checkpoint["stats"] = {
                "teams_processed": len(checkpoint["processed_teams"]),
                "players_found": stats["players_found"],
                "photos_uploaded": stats["photos_uploaded"],
            }
            stats["teams_processed"] = len(checkpoint["processed_teams"])
            save_checkpoint(bucket, league, checkpoint)

        except Exception as e:
            msg = f"Error on team {team_name}: {e}"
            print(f"  ✗ {msg}")
            stats["errors"].append(msg)

    if not specific_teams and len(checkpoint["processed_teams"]) >= len(all_teams):
        delete_checkpoint(bucket, league)

    print(
        f"\n{'='*60}\nDONE – {league.upper()}\n{'='*60}\n"
        f"Teams processed : {stats['teams_processed']}\n"
        f"Players found   : {stats['players_found']}\n"
        f"Photos uploaded : {stats['photos_uploaded']}\n"
        f"DB saves        : {stats['dynamodb_saves']}\n"
        f"API calls       : {stats['api_calls']}\n"
    )
    return stats


# ──────────────────────────────────────────────
# Lambda entry point
# ──────────────────────────────────────────────
def lambda_handler(event, context):
    """
    Expected event payload:
    {
        "league":         "nfl",
        "bucket_name":    "your-s3-bucket",
        "table_name":     "Players",
        "max_teams":      5,           // optional  cap teams per invocation
        "resume":         true,        // optional  default true
        "specific_teams": ["Kansas City Chiefs", "Buffalo Bills"]  // optional
    }
    """
    try:
        league = (event.get("league") or "nfl").lower()
        bucket = event.get("bucket_name")
        table_name = event.get("table_name")
        max_teams = event.get("max_teams")
        resume = event.get("resume", True)
        specific_teams = event.get("specific_teams")

        if not bucket:
            return {"statusCode": 400, "body": json.dumps({"error": "bucket_name is required"})}
        if not table_name:
            return {"statusCode": 400, "body": json.dumps({"error": "table_name is required"})}

        results = scrape_league(
            league=league,
            bucket=bucket,
            table_name=table_name,
            max_teams=max_teams,
            resume=resume,
            specific_teams=specific_teams,
        )

        photo_rate = (
            f"{results['photos_uploaded'] / results['players_with_images'] * 100:.1f}%"
            if results["players_with_images"] else "N/A"
        )
        db_rate = (
            f"{results['dynamodb_saves'] / results['players_found'] * 100:.1f}%"
            if results["players_found"] else "N/A"
        )

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Scraping complete",
                "results": {
                    "league": results["league"],
                    "teams_processed": results["teams_processed"],
                    "players_found": results["players_found"],
                    "players_with_images": results["players_with_images"],
                    "skipped_existing": results["skipped_existing"],
                    "skipped_no_image": results["skipped_no_image"],
                    "skipped_bad_upload": results["skipped_bad_upload"],
                    "photos_uploaded": results["photos_uploaded"],
                    "photo_success_rate": photo_rate,
                    "dynamodb_saves": results["dynamodb_saves"],
                    "db_success_rate": db_rate,
                    "api_calls": results["api_calls"],
                    "errors": len(results["errors"]),
                },
            }),
        }

    except Exception as e:
        print(f"Lambda error: {e}")
        return {"statusCode": 500, "body": json.dumps({"error": str(e)})}


# ──────────────────────────────────────────────
# Local test
# ──────────────────────────────────────────────
if __name__ == "__main__":
    test_event = {
        "league": "nfl",
        "bucket_name": "rit-athlete-photos-team2",
        "table_name": "Players",
        "max_teams": 2,
        "resume": True,
        "specific_teams": ["Buffalo Bills", "Kansas City Chiefs"],
    }
    result = lambda_handler(test_event, None)
    print("\n" + "=" * 60)
    print(json.dumps(json.loads(result["body"]), indent=2))