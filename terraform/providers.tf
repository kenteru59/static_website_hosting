# 通常使用のAWSプロバイダー設定
provider "aws" {
  profile = "sandbox-developer-user1"
  region  = "ap-northeast-1"
  default_tags {
    tags = var.default_tags
  }
}

# Lambda@edge用のAWSプロバイダー設定
provider "aws" {
  alias   = "use1"
  profile = "sandbox-developer-user1"
  region  = "us-east-1"
  default_tags {
    tags = var.default_tags
  }
}
