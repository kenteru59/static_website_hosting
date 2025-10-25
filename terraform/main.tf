provider "aws" {
  profile = "sandbox-developer-user1"
  region  = "ap-northeast-1"
  default_tags {
    tags = var.default_tags
  }
}


# 動作確認のため新しくVPCを作る
resource "aws_vpc" "main" {
  cidr_block = "10.10.10.0/24"
  tags = {
    Name = "test_abe_vpc"
  }
}

variable "default_tags" {
  description = "共通タグ"
  type        = map(string)
}

