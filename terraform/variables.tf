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

# 外部公開用ドメイン名
variable "domain_name_public" {
  type        = string
  description = "The public domain name for the static website"
  default     = "kenteruhogehoge.com"
}

# プレビュー画面用ドメイン名
variable "domain_name_preview" {
  type        = string
  description = "The preview domain name for the static website"
  default     = "preview.kenteruhogehoge.com"
}

# Route53のホストゾーンID
variable "route53_hosted_zone_id" {
  type        = string
  description = "The Route53 Hosted Zone ID for the domain"
}

# # コンテンツ公開をするS3バケットにあてるCloudFrontのTLS証明書のARN
# variable "cloudfront_certificate_arn" {
#   type        = string
#   description = "The ARN of the TLS certificate for CloudFront"
# }

variable "region_main" {
  type        = string
  description = "Main AWS region (for main resources except Lambda@Edge)"
  default     = "ap-northeast-1"
}
