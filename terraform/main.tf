#################################################
# コンテンツ保管用のS3バケットを作成
#################################################
# 公開用コンテンツ保管S3バケット
resource "aws_s3_bucket" "public_content_bucket" {
  bucket = "${var.project_name}-content-public"

  tags = merge(
    var.default_tags,
    {
      Name = "${var.project_name}-content-public"
    }
  )
}

# 公開コンテンツのブロックパブリックアクセスポリシー
resource "aws_s3_bucket_public_access_block" "public_content_bucket_access_block" {
  bucket                  = aws_s3_bucket.public_content_bucket.id
  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 公開用コンテンツS3バケットのバージョニング有効化
resource "aws_s3_bucket_versioning" "public_content_bucket_versioning" {
  bucket = aws_s3_bucket.public_content_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# プレビュー用コンテンツ保管S3バケット
resource "aws_s3_bucket" "preview_content_bucket" {
  bucket = "${var.project_name}-content-preview"

  tags = merge(
    var.default_tags,
    {
      Name = "${var.project_name}-content-preview"
    }
  )
}

# プレビューコンテンツのブロックパブリックアクセスポリシー
resource "aws_s3_bucket_public_access_block" "preview_content_bucket_access_block" {
  bucket                  = aws_s3_bucket.preview_content_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# プレビュー用コンテンツS3バケットのバージョニング有効化
resource "aws_s3_bucket_versioning" "preview_content_bucket_versioning" {
  bucket = aws_s3_bucket.preview_content_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

#################################################
# WAF（CloudFront用）を作成
#################################################
resource "aws_wafv2_web_acl" "public_cloudfront_waf" {
  provider    = aws.use1
  name        = "${var.project_name}-public-cloudfront-waf"
  description = "WebACL for public Cloudfront"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-public-cloudfront-waf-metric"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedCommonRules"
    priority = 1
    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedCommonRulesMetric"
      sampled_requests_enabled   = true
    }
  }

  tags = merge(
    var.default_tags,
    {
      Name = "${var.project_name}-public-cloudfront-waf"
    }
  )
}

#################################################
# Cognito User Poolを作成（Transfer Family用 and プレビューサイトアクセス用）
#################################################
resource "aws_cognito_user_pool" "static_website_user_pool" {
  name = "${var.project_name}-user-pool"

  tags = merge(
    var.default_tags,
    {
      Name = "${var.project_name}-user-pool"
    }
  )

  password_policy {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }
}

resource "aws_cognito_user_pool_client" "static_website_user_pool_client" {
  name            = "${var.project_name}-user-pool-client"
  user_pool_id    = aws_cognito_user_pool.static_website_user_pool.id
  generate_secret = false

  # allowed_oauth_flows_user_pool_client = true
  # allowed_oauth_scopes                 = ["email", "openid", "profile"]
  # allowed_oauth_flows                  = ["code"]
  # callback_urls = ["https://${var.domain_name_preview}/callback"]
  # logout_urls   = ["https://${var.domain_name_preview}/logout"]

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}

resource "aws_cognito_user_pool_domain" "static_website_user_pool_domain" {
  domain       = "${var.project_name}-user-pool-domain"
  user_pool_id = aws_cognito_user_pool.static_website_user_pool.id
}

#################################################
# Lambda@Edgeの作成（Cognito認証用）
#################################################
resource "aws_iam_role" "lambda_edge_cognito_auth_role" {
  name = "${var.project_name}-lambda-edge-cognito-auth-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com" # cspell:disable-line
          ]
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = merge(
    var.default_tags,
    {
      Name = "${var.project_name}-lambda-edge-cognito-auth-role"
    }
  )
}

resource "aws_iam_role_policy" "lambda_edge_cognito_auth_role_policy" {
  name = "${var.project_name}-lambda-edge-cognito-auth-role-policy"
  role = aws_iam_role.lambda_edge_cognito_auth_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:ListUsers",
          "cognito-idp:GetJWKSUri",
          "cognito-idp:DescribeUserPool"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "lambda_edge_cognito_auth" {
  provider         = aws.use1
  function_name    = "${var.project_name}-lambda-edge-cognito-auth"
  role             = aws_iam_role.lambda_edge_cognito_auth_role.arn
  handler          = "edge_auth.handler"
  runtime          = "python3.10"
  filename         = "../python/lambda_edge_cognito_auth.zip"
  source_code_hash = filebase64sha256("../python/lambda_edge_cognito_auth.zip")
  publish          = true

  tags = merge(
    var.default_tags,
    {
      Name = "${var.project_name}-lambda-edge-cognito-auth"
    }
  )
}

#################################################
# CloudFront（公開サイト用）を作成
#################################################
resource "aws_cloudfront_origin_access_control" "public_cloudfront_oac" {
  name                              = "${var.project_name}-public-cloudfront-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "public_cloudfront_distribution" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront Distribution for Public Static Website"
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.public_content_bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.public_content_bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.public_cloudfront_oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "S3-${aws_s3_bucket.public_content_bucket.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    lambda_function_association {
      event_type   = "viewer-request"
      lambda_arn   = aws_lambda_function.lambda_edge_cognito_auth.qualified_arn
      include_body = false
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # viewer_certificate {
  #   acm_certificate_arn      = var.cloudfront_certificate_arn
  #   ssl_support_method       = "sni-only"
  #   minimum_protocol_version = "TLSv1.2_2021"
  # }
  viewer_certificate {
    cloudfront_default_certificate = true
  }


  web_acl_id = aws_wafv2_web_acl.public_cloudfront_waf.arn

  tags = merge(
    var.default_tags,
    {
      Name = "${var.project_name}-public-cloudfront-distribution"
    }
  )
}

data "aws_iam_policy_document" "s3_bucket_policy_public_content" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.public_content_bucket.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.public_cloudfront_distribution.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "public_website_bucket_policy" {
  bucket = aws_s3_bucket.public_content_bucket.id
  policy = data.aws_iam_policy_document.s3_bucket_policy_public_content.json
}
