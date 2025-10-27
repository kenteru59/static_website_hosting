# 共通タグ用の変数定義
variable "default_tags" {
  description = "共通タグ"
  type        = map(string)
}

# プロジェクト名
variable "project_name" {
  type        = string
  description = "Prefix for resource names"
  default     = "static-website-architecture"
}

variable "region_main" {
  description = "メインリージョン（S3, Lambda(通常), Transfer Familyなどを置くリージョン）"
  type        = string
  default     = "ap-northeast-1"
}

# stateファイルを保持するS3
variable "state_file_bucket" {
  type        = string
  description = "state_file_bucket"
}