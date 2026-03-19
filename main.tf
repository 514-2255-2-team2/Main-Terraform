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

# -----------------------------
# Existing IAM Role
# -----------------------------
data "aws_iam_role" "amplify_service_role" {
  name = "amplify-service-role"
}

# -----------------------------
# Amplify App
# -----------------------------
resource "aws_amplify_app" "react_app" {
  name         = "AmplifyUI"
  repository   = "https://github.com/noahlago/AmplifyUI"
  access_token = var.github_token
  platform     = "WEB"

  enable_branch_auto_build = false

  build_spec = <<EOF
version: 1
applications:
  - appRoot: Amplify-React-UI
    frontend:
      phases:
        preBuild:
          commands:
            - npm ci
        build:
          commands:
            - npm run build
      artifacts:
        baseDirectory: dist
        files:
          - "**/*"
      cache:
        paths:
          - node_modules/**/*
EOF

  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "404-200"
  }

  lifecycle {
    ignore_changes = [
      access_token
    ]
  }
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.react_app.id
  branch_name = "main"
}