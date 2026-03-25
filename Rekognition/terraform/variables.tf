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