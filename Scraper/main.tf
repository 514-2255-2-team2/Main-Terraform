# ──────────────────────────────────────────────
# main.tf
# Athlete Face Match System
# ──────────────────────────────────────────────

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ──────────────────────────────────────────────
# S3 Bucket – Player Images + Checkpoints
# ──────────────────────────────────────────────
resource "aws_s3_bucket" "athlete_photos" {
  bucket = "rit-athlete-photos-team2"
  force_destroy = true

  tags = {
    Project = "athlete-face-match"
  }
}

resource "aws_s3_bucket_public_access_block" "athlete_photos" {
  bucket                  = aws_s3_bucket.athlete_photos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────
# DynamoDB – Players Table
# ──────────────────────────────────────────────
resource "aws_dynamodb_table" "players" {
  name         = "Players"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "player_id"

  attribute {
    name = "player_id"
    type = "S"
  }

  tags = {
    Project = "athlete-face-match"
  }
}

# ──────────────────────────────────────────────
# IAM Role – Scraper Lambda
# ──────────────────────────────────────────────
resource "aws_iam_role" "scraper_lambda_role" {
  name = "athlete-scraper-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "scraper_lambda_policy" {
  name = "athlete-scraper-lambda-policy"
  role = aws_iam_role.scraper_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.athlete_photos.arn,
          "${aws_s3_bucket.athlete_photos.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.players.arn
      },
      {
        Effect = "Allow"
        Action = [
          "rekognition:IndexFaces",
          "rekognition:CreateCollection",
          "rekognition:DescribeCollection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:us-east-1:*:*"
      }
    ]
  })
}

# ──────────────────────────────────────────────
# Lambda – Scraper
# ──────────────────────────────────────────────
data "archive_file" "scraper_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/scrape_player_data.py"
  output_path = "${path.module}/scrape_player_data.zip"
}

resource "aws_lambda_function" "scraper" {
  function_name    = "athlete-scraper"
  filename         = data.archive_file.scraper_zip.output_path
  source_code_hash = data.archive_file.scraper_zip.output_base64sha256
  role             = aws_iam_role.scraper_lambda_role.arn
  handler = "scrape_player_data.lambda_handler"
  runtime          = "python3.11"
  timeout          = 900
  memory_size      = 512

  layers = [
    "arn:aws:lambda:us-east-1:770693421928:layer:Klayers-p311-requests:15"
  ]

  environment {
    variables = {
      SPORTSDB_KEY = "3"
    }
  }

  tags = {
    Project = "athlete-face-match"
  }
}

resource "aws_cloudwatch_log_group" "scraper_logs" {
  name              = "/aws/lambda/athlete-scraper"
  retention_in_days = 14
}

resource "aws_lambda_invocation" "run_scraper" {
  function_name = aws_lambda_function.scraper.function_name

  input = jsonencode({
    league         = "nfl"
    bucket_name    = aws_s3_bucket.athlete_photos.bucket
    table_name     = aws_dynamodb_table.players.name
    specific_teams = ["Buffalo Bills", "Kansas City Chiefs"]
  })

  depends_on = [
    aws_lambda_function.scraper,
    aws_s3_bucket.athlete_photos,
    aws_dynamodb_table.players
  ]
}

# ──────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────
output "s3_bucket_name" {
  value = aws_s3_bucket.athlete_photos.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.players.name
}

output "scraper_lambda_arn" {
  value = aws_lambda_function.scraper.arn
}