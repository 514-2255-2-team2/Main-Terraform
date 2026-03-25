terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "react_app_sg" {
  name = "react-app-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "react_app" {
  ami           = "ami-02dfbd4ff395f2a1b"
  instance_type = "t3.micro"

  key_name = "NDL3389_Virginia_2"

  vpc_security_group_ids = [aws_security_group.react_app_sg.id]

  user_data = templatefile("${path.module}/userdata.sh", {
    image_upload_url = aws_apigatewayv2_api.image_upload_api.api_endpoint
    s3_bucket_url    = "https://${aws_s3_bucket.image_uploads.bucket}.s3.amazonaws.com"
  })

  tags = {
    Name = "react-app-server"
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "image_uploads" {
  bucket        = "react-image-uploads-${random_id.bucket_suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "image_uploads" {
  bucket = aws_s3_bucket.image_uploads.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.image_uploads.id

  depends_on = [aws_s3_bucket_public_access_block.image_uploads]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.image_uploads.arn}/*"
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "image_upload_lambda_role" {
  name               = "image-upload-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy" "image_upload_lambda_policy" {
  name = "image-upload-lambda-policy"
  role = aws_iam_role.image_upload_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.image_uploads.arn}/*"
      }
    ]
  })
}

resource "local_file" "lambda_source" {
  filename = "${path.module}/lambda_function.py"

  content = <<-PY
import base64
import boto3
import json
import os
import uuid

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_NAME"]

def detect_extension(content_type, image_bytes):
    if image_bytes.startswith(b'\x89PNG'):
        return "png"
    elif image_bytes.startswith(b'\xff\xd8'):
        return "jpg"
    elif image_bytes.startswith(b'GIF'):
        return "gif"
    elif image_bytes.startswith(b'RIFF'):
        return "webp"

    if "png" in content_type:
        return "png"
    elif "jpeg" in content_type or "jpg" in content_type:
        return "jpg"
    elif "gif" in content_type:
        return "gif"
    elif "webp" in content_type:
        return "webp"

    return "bin"

def lambda_handler(event, context):
    headers = event.get("headers") or {}
    content_type = headers.get("content-type") or headers.get("Content-Type") or "application/octet-stream"

    body = event.get("body") or ""

    if event.get("isBase64Encoded"):
        image_bytes = base64.b64decode(body)
    else:
        image_bytes = body.encode("utf-8")

    ext = detect_extension(content_type, image_bytes)

    key = f"uploads/{uuid.uuid4()}.{ext}"

    s3.put_object(
        Bucket=BUCKET,
        Key=key,
        Body=image_bytes,
        ContentType=content_type
    )

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps({
            "image_s3_uri": f"s3://{BUCKET}/{key}"
        })
    }
PY
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.lambda_source.filename
  output_path = "${path.module}/lambda_upload.zip"
}

resource "aws_lambda_function" "image_upload" {
  function_name    = "image-upload-function"
  role             = aws_iam_role.image_upload_lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.image_uploads.bucket
    }
  }
}

resource "aws_apigatewayv2_api" "image_upload_api" {
  name          = "image-upload-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
  }
}

resource "aws_apigatewayv2_integration" "image_upload_integration" {
  api_id                 = aws_apigatewayv2_api.image_upload_api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.image_upload.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "upload_route" {
  api_id    = aws_apigatewayv2_api.image_upload_api.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.image_upload_integration.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.image_upload_api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.image_upload_api.execution_arn}/*/*"
}

output "react_app_public_ip" {
  value = aws_instance.react_app.public_ip
}

output "image_upload_api_url" {
  value = aws_apigatewayv2_api.image_upload_api.api_endpoint
}

output "image_upload_bucket" {
  value = aws_s3_bucket.image_uploads.bucket
}