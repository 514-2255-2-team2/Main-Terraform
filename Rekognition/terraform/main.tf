data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  user_upload_bucket_name = var.user_upload_bucket_name != "" ? var.user_upload_bucket_name : "${var.project_name}-user-uploads-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

data "archive_file" "indexer_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/index_players.py"
  output_path = "${path.module}/index_players.zip"
}

data "archive_file" "search_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/search_players.py"
  output_path = "${path.module}/search_players.zip"
}

data "archive_file" "upload_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/upload_user_image.py"
  output_path = "${path.module}/upload_user_image.zip"
}

data "archive_file" "player_details_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda/get_player_details.py"
  output_path = "${path.module}/get_player_details.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

#
# User upload bucket
#
resource "aws_s3_bucket" "user_uploads" {
  bucket        = local.user_upload_bucket_name
  force_destroy = var.user_upload_bucket_force_destroy
}

resource "aws_s3_bucket_public_access_block" "user_uploads" {
  bucket = aws_s3_bucket.user_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "user_uploads" {
  bucket = aws_s3_bucket.user_uploads.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

#
# IAM: indexer Lambda
#
resource "aws_iam_role" "indexer" {
  name               = "${var.project_name}-indexer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "indexer_basic" {
  role       = aws_iam_role.indexer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "indexer_policy" {
  statement {
    sid = "DynamoDBAccess"

    actions = [
      "dynamodb:Scan",
      "dynamodb:UpdateItem"
    ]

    resources = [
      "arn:aws:dynamodb:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.table_name}"
    ]
  }

  statement {
    sid = "S3ReadImages"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "arn:aws:s3:::${var.bucket_name}/*"
    ]
  }

  statement {
    sid = "RekognitionIndex"

    actions = [
      "rekognition:CreateCollection",
      "rekognition:IndexFaces"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "indexer_inline" {
  name   = "${var.project_name}-indexer-policy"
  role   = aws_iam_role.indexer.id
  policy = data.aws_iam_policy_document.indexer_policy.json
}

#
# IAM: search Lambda
# reads the user-uploaded image bucket
#
resource "aws_iam_role" "search" {
  name               = "${var.project_name}-search-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "search_basic" {
  role       = aws_iam_role.search.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "search_policy" {
  statement {
    sid = "S3ReadUserImages"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.user_uploads.arn}/*"
    ]
  }

  statement {
    sid = "RekognitionSearch"

    actions = [
      "rekognition:SearchFacesByImage"
    ]

    resources = ["*"]
  }

  statement {
    sid = "CloudWatchPutMetrics"

    actions = [
      "cloudwatch:PutMetricData"
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "search_inline" {
  name   = "${var.project_name}-search-policy"
  role   = aws_iam_role.search.id
  policy = data.aws_iam_policy_document.search_policy.json
}

#
# IAM: upload Lambda
#
resource "aws_iam_role" "upload" {
  name               = "${var.project_name}-upload-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "upload_basic" {
  role       = aws_iam_role.upload.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "upload_policy" {
  statement {
    sid = "S3PutUserImages"

    actions = [
      "s3:PutObject"
    ]

    resources = [
      "${aws_s3_bucket.user_uploads.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "upload_inline" {
  name   = "${var.project_name}-upload-policy"
  role   = aws_iam_role.upload.id
  policy = data.aws_iam_policy_document.upload_policy.json
}

#
# IAM: player details Lambda
#
resource "aws_iam_role" "player_details" {
  name               = "${var.project_name}-player-details-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "player_details_basic" {
  role       = aws_iam_role.player_details.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "player_details_policy" {
  statement {
    sid = "DynamoDBGetPlayer"

    actions = [
      "dynamodb:GetItem"
    ]

    resources = [
      "arn:aws:dynamodb:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:table/${var.table_name}"
    ]
  }

  statement {
    sid = "S3ReadPlayerImages"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "arn:aws:s3:::${var.bucket_name}/*"
    ]
  }
}

resource "aws_iam_role_policy" "player_details_inline" {
  name   = "${var.project_name}-player-details-policy"
  role   = aws_iam_role.player_details.id
  policy = data.aws_iam_policy_document.player_details_policy.json
}

#
# Lambdas
#
resource "aws_lambda_function" "indexer" {
  function_name    = "${var.project_name}-indexer"
  role             = aws_iam_role.indexer.arn
  filename         = data.archive_file.indexer_zip.output_path
  source_code_hash = data.archive_file.indexer_zip.output_base64sha256

  runtime = "python3.12"
  handler = "index_players.lambda_handler"

  timeout     = var.index_lambda_timeout
  memory_size = 512

  environment {
    variables = {
      TABLE_NAME  = var.table_name
      BUCKET_NAME = var.bucket_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.indexer_basic,
    aws_iam_role_policy.indexer_inline
  ]
}

resource "aws_lambda_function" "search" {
  function_name    = "${var.project_name}-search"
  role             = aws_iam_role.search.arn
  filename         = data.archive_file.search_zip.output_path
  source_code_hash = data.archive_file.search_zip.output_base64sha256

  runtime = "python3.12"
  handler = "search_players.lambda_handler"

  timeout     = var.search_lambda_timeout
  memory_size = 256

  environment {
    variables = {
      BUCKET_NAME         = aws_s3_bucket.user_uploads.bucket
      CW_METRIC_NAMESPACE = var.cw_metric_namespace
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.search_basic,
    aws_iam_role_policy.search_inline
  ]
}

#
# Search similarity alerts: SNS + CloudWatch alarm on custom metric
#
resource "aws_sns_topic" "search_similarity_alerts" {
  name = "${var.project_name}-search-similarity-alerts"
}

resource "aws_sns_topic_subscription" "search_similarity_email" {
  topic_arn = aws_sns_topic.search_similarity_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "search_similarity_sns_policy" {
  statement {
    sid    = "AllowCloudWatchPublish"
    effect = "Allow"

    actions = [
      "sns:Publish"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    resources = [aws_sns_topic.search_similarity_alerts.arn]
  }
}

resource "aws_sns_topic_policy" "search_similarity_alerts" {
  arn    = aws_sns_topic.search_similarity_alerts.arn
  policy = data.aws_iam_policy_document.search_similarity_sns_policy.json
}

resource "aws_cloudwatch_metric_alarm" "search_low_best_similarity" {
  alarm_name          = "${var.project_name}-search-low-best-similarity"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BestMatchSimilarity"
  namespace           = var.cw_metric_namespace
  period              = var.alarm_period_seconds
  statistic           = "Minimum"
  threshold           = var.similarity_alarm_threshold
  treat_missing_data  = "notBreaching"
  alarm_description   = "Best face-match similarity below ${var.similarity_alarm_threshold}% in the period (or no matches / 0)."
  alarm_actions       = [aws_sns_topic.search_similarity_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.search.function_name
  }

  depends_on = [
    aws_sns_topic_policy.search_similarity_alerts,
    aws_sns_topic_subscription.search_similarity_email,
  ]
}

resource "aws_lambda_function" "upload" {
  function_name    = "${var.project_name}-upload"
  role             = aws_iam_role.upload.arn
  filename         = data.archive_file.upload_zip.output_path
  source_code_hash = data.archive_file.upload_zip.output_base64sha256

  runtime = "python3.12"
  handler = "upload_user_image.lambda_handler"

  timeout     = var.upload_lambda_timeout
  memory_size = 256

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.user_uploads.bucket
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.upload_basic,
    aws_iam_role_policy.upload_inline
  ]
}

resource "aws_lambda_function" "player_details" {
  function_name    = "${var.project_name}-player-details"
  role             = aws_iam_role.player_details.arn
  filename         = data.archive_file.player_details_zip.output_path
  source_code_hash = data.archive_file.player_details_zip.output_base64sha256

  runtime = "python3.12"
  handler = "get_player_details.lambda_handler"

  timeout     = var.player_details_lambda_timeout
  memory_size = 256

  environment {
    variables = {
      TABLE_NAME          = var.table_name
      BUCKET_NAME         = var.bucket_name
      SIGNED_URL_EXPIRES  = tostring(var.player_image_url_expires)
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.player_details_basic,
    aws_iam_role_policy.player_details_inline
  ]
}

#
# API Gateway HTTP API
#
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-http"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_integration" "search" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.search.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "indexer" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.indexer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "upload" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.upload.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "player_details" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.player_details.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "search_post" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /search"
  target    = "integrations/${aws_apigatewayv2_integration.search.id}"
}

resource "aws_apigatewayv2_route" "index_post" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /index"
  target    = "integrations/${aws_apigatewayv2_integration.indexer.id}"
}

resource "aws_apigatewayv2_route" "upload_post" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /upload"
  target    = "integrations/${aws_apigatewayv2_integration.upload.id}"
}

resource "aws_apigatewayv2_route" "player_details_post" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /player-details"
  target    = "integrations/${aws_apigatewayv2_integration.player_details.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

#
# Allow API Gateway to invoke Lambdas
#
resource "aws_lambda_permission" "apigw_search" {
  statement_id  = "AllowAPIGatewayInvokeSearch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.search.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_indexer" {
  statement_id  = "AllowAPIGatewayInvokeIndexer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.indexer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_upload" {
  statement_id  = "AllowAPIGatewayInvokeUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_player_details" {
  statement_id  = "AllowAPIGatewayInvokePlayerDetails"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.player_details.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

#
# Invoke the indexer once after deploy / when its code or key settings change
#
resource "terraform_data" "run_index_after_apply" {
  count = var.invoke_index_on_apply ? 1 : 0

  triggers_replace = {
    code_hash   = data.archive_file.indexer_zip.output_base64sha256
    table_name  = var.table_name
    bucket_name = var.bucket_name
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws lambda invoke \
        --function-name ${aws_lambda_function.indexer.function_name} \
        --cli-binary-format raw-in-base64-out \
        --payload '{}' \
        ${path.module}/indexer-response.json >/dev/null
    EOT
  }

  depends_on = [
    aws_lambda_function.indexer
  ]
}