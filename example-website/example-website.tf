variable "bucket_log_prefix" {default = "example-website-bucket"}
variable "log_file_prefix" {default = "website-cdn/"}

variable "web_acl_id" {default = ""}

variable "aws_region" {}

provider "aws" {
  region = "${var.aws_region}"
}

resource "aws_s3_bucket" "website_bucket" {
  bucket_prefix   = "example-website"


  logging {
    target_bucket = "${aws_s3_bucket.access_log_bucket.id}"
    target_prefix = "${var.bucket_log_prefix}/"
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "Example Website"
}

data "aws_iam_policy_document" "origin_access_policy" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website_bucket.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["${aws_s3_bucket.website_bucket.arn}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

resource "aws_s3_bucket_policy" "website_bucket_policy" {
  bucket = "${aws_s3_bucket.website_bucket.id}"
  policy = "${data.aws_iam_policy_document.origin_access_policy.json}"
}

resource "aws_cloudfront_distribution" "website_cdn" {
  enabled      = true
  http_version = "http2"

  "origin" {
    origin_id   = "origin-bucket-${aws_s3_bucket.website_bucket.id}"
    domain_name = "${aws_s3_bucket.website_bucket.bucket_regional_domain_name}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }

  }

  default_root_object = "index.html"

  custom_error_response {
     error_code            = "404"
     error_caching_min_ttl = "360"
     response_code         = "404"
     response_page_path    = "/404.html"
  }

  "default_cache_behavior" {
    allowed_methods = ["GET", "HEAD", "DELETE", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]

    "forwarded_values" {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl          = "0"
    default_ttl      = "300"                                              //3600
    max_ttl          = "1200"                                             //86400
    target_origin_id = "origin-bucket-${aws_s3_bucket.website_bucket.id}"

    viewer_protocol_policy = "redirect-to-https"
    compress               = true
  }

  "restrictions" {
    "geo_restriction" {
      restriction_type = "none"
    }
  }

  "logging_config" {
    include_cookies = false
    bucket          = "${aws_s3_bucket.access_log_bucket.id}.s3.amazonaws.com"
    prefix          = "${var.log_file_prefix}"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
  web_acl_id = "${var.web_acl_id}"
}

resource "aws_s3_bucket" "access_log_bucket" {
  bucket_prefix = "example-website-logs"  
  acl    = "log-delivery-write"
  lifecycle_rule {
      id      = "log"
      enabled = true
      expiration {
        days = 7
      }
    }  
}

data "archive_file" "site_zip" {
  type        = "zip"
  source_dir = "example-website-contents"
  output_path = "/tmp/example-site.zip"
}

resource "null_resource" "publish_site_to_s3" {
  triggers {
    trigger_on_filechange = "${data.archive_file.site_zip.output_md5}"
  }  
  provisioner "local-exec" {
    command = "aws s3 sync example-website-contents s3://${aws_s3_bucket.website_bucket.id}"
  }
}

output "website_url" {
  value = "https://${aws_cloudfront_distribution.website_cdn.domain_name}/"
}

output "cdn_log_bucket" {
  value = "${element(split(".", lookup(aws_cloudfront_distribution.website_cdn.logging_config[0], "bucket")), 0)}"
  # value = "${element(split('.', lookup(aws_cloudfront_distribution.website_cdn.logging_config[0], "bucket")), 0)}"
}

output "cdn_log_prefix" {
  value = "${lookup(aws_cloudfront_distribution.website_cdn.logging_config[0], "prefix")}"
}





