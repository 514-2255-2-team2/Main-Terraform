/*
output "s3_bucket_name" {
  value = aws_s3_bucket.athlete_photos.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.players.name
}

output "scraper_lambda_arn" {
  value = aws_lambda_function.scraper.arn
}

output "api_base_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "search_url" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}/search"
}

output "index_url" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}/index"
}

output "upload_url" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}/upload"
}

output "player_details_url" {
  value = "${aws_apigatewayv2_stage.default.invoke_url}/player-details"
}

output "index_lambda_name" {
  value = aws_lambda_function.indexer.function_name
}

output "search_lambda_name" {
  value = aws_lambda_function.search.function_name
}

output "upload_lambda_name" {
  value = aws_lambda_function.upload.function_name
}

output "player_details_lambda_name" {
  value = aws_lambda_function.player_details.function_name
}

output "user_upload_bucket_name" {
  value = aws_s3_bucket.user_uploads.bucket
}
*/

output "react_app_public_ip" {
  value       = aws_instance.react_app.public_ip
  description = "Public IP of the React app EC2 instance"
}

/*
output "search_similarity_alert_sns_topic_arn" {
  value       = aws_sns_topic.search_similarity_alerts.arn
  description = "SNS topic ARN for low best-match similarity alarms."
}
*/

output "search_similarity_alert_note" {
  value       = "After apply, open the inbox for alert_email and confirm the AWS SNS subscription; unconfirmed subscriptions do not receive alarm emails."
  description = "Operational reminder for SNS email confirmation."
}

