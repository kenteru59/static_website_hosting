# 通常使用のAWSプロバイダー設定
provider "aws" {
  profile = "sandbox-developer-user1"
  region  = "ap-northeast-1"
  max_retries = 1
  default_tags {
    tags = var.default_tags
  }
}

# Lambda@edge用のAWSプロバイダー設定
provider "aws" {
  alias   = "use1"
  profile = "sandbox-developer-user1"
  region  = "us-east-1"
  max_retries = 1
  default_tags {
    tags = var.default_tags
  }
}

terraform {
  backend "s3" {
    # dynamodb_table = "terraform-lock"                # 任意（ロック管理に使用）
    encrypt        = true                              # サーバーサイド暗号化
  }
}