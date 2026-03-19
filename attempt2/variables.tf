variable "token" {
  type        = string
  description = "github token to connect github repo"
  default     = "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"
}

variable "repository" {
  type        = string
  description = "github repo url"
  default     = "https://github.com/noahlago/AmplifyUI"
}

variable "app_name" {
  type        = string
  description = "AWS Amplify App Name"
  default     = "Team2"
}

variable "branch_name" {
  type        = string
  description = "AWS Amplify App Repo Branch Name"
  default     = "main"
}


variable "domain_name" {
  type        = string
  default     = "team2amplify.com"
  description = "AWS Amplify Domain Name"
}