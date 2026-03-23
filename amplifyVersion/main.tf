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
# Amplify App
# -----------------------------
resource "aws_amplify_app" "react_app" {
  name       = "my-react-app"
  repository = "https://github.com/noahlago/AmplifyUI"
  access_token = var.github_token
  platform   = "WEB"

  iam_service_role_arn = aws_iam_role.amplify_service_role.arn

  build_spec = <<EOF
version: 1
frontend:
  phases:
    preBuild:
      commands:
        - cd Amplify-React-UI
        - npm ci
    build:
      commands:
        - npm run build
  artifacts:
    baseDirectory: Amplify-React-UI/dist
    files:
      - '**/*'
  cache:
    paths:
      - Amplify-React-UI/node_modules/**/*
EOF

  custom_rule {
    source = "/<*>"
    target = "/index.html"
    status = "404-200"
  }

  # Do NOT enable auto branch creation or auto-build for the first run
  enable_auto_branch_creation = false
  enable_branch_auto_build    = false

  lifecycle {
    ignore_changes = [
      access_token
    ]
  }
}

# -----------------------------
# Amplify Branch
# -----------------------------
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.react_app.id
  branch_name = "main"

  enable_auto_build = false

  depends_on = [aws_amplify_app.react_app]
}