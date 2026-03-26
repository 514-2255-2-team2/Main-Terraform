variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "athlete-face-api"
}

variable "table_name" {
  type    = string
  default = "Players"
}

# existing player image bucket
variable "bucket_name" {
  type    = string
  default = "athlete-photos-team2"
}

# new user upload bucket
variable "user_upload_bucket_name" {
  type    = string
  default = ""
}

variable "user_upload_bucket_force_destroy" {
  type    = bool
  default = true
}

variable "allowed_origins" {
  type    = list(string)
  default = ["*"]
}

variable "index_lambda_timeout" {
  type    = number
  default = 300
}

variable "search_lambda_timeout" {
  type    = number
  default = 30
}

variable "upload_lambda_timeout" {
  type    = number
  default = 30
}

variable "player_details_lambda_timeout" {
  type    = number
  default = 30
}

variable "player_image_url_expires" {
  type    = number
  default = 3600
}

variable "invoke_index_on_apply" {
  type    = bool
  default = true
}

variable "alert_email" {
  type        = string
  description = "Email address for SNS subscription; confirm via link after apply."
}

variable "similarity_alarm_threshold" {
  type        = number
  default     = 10
  description = "CloudWatch alarm fires when minimum best-match similarity in the period is below this (percent)."
}

variable "alarm_period_seconds" {
  type        = number
  default     = 60
  description = "Alarm evaluation period; must be a multiple of 60 for standard-resolution metrics."
}

variable "cw_metric_namespace" {
  type        = string
  default     = "AthleteFaceSearch"
  description = "Custom metric namespace; must match CW_METRIC_NAMESPACE on the search Lambda."
}