# maximum bad requests per minute per IP. Default: 50
variable "config_request_threshold" { default = "50" }

#duration (in seconds) the IP should be blocked for. Default: 4 hours (14400 sec)
variable "config_waf_block_period" { default = "14400" }

variable "aws_region" {}

variable "cdn_log_bucket" {}
variable "cdn_log_prefix" {}

provider "aws" {
  region = "${var.aws_region}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "ops_bucket" {
  bucket_prefix = "waf-block-ops"
  acl           = "private"
  versioning {
    enabled = true    
  }
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir = "./lambda-function"
  output_path = "parser.zip"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${var.cdn_log_bucket}"
  lambda_function {
    id = "logfile_created_notify_lambda"
    lambda_function_arn = "${aws_lambda_function.lambda_function.arn}"
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".gz"
    filter_prefix       = "${var.cdn_log_prefix}"    
  }
}

resource "random_id" "function_name" {
  prefix = "waf-blocker-"
  byte_length = 8
}

resource "aws_lambda_function" "lambda_function" {
  depends_on  = ["aws_iam_role.lambda_role"]
  function_name    = "${random_id.function_name.hex}"
  role             = "${aws_iam_role.lambda_role.arn}"
  handler          = "parser.lambda_handler"
  runtime          = "python2.7"
  memory_size      = "512"
  timeout          = "300"
  filename         = "${data.archive_file.lambda_zip.output_path}"
  description      = "Parse cloudfront logs, identify bad actors, and them to a WAF block"

  environment {
    variables = {
      OUTPUT_BUCKET = "${aws_s3_bucket.ops_bucket.id}"
      IP_SET_ID_MANUAL_BLOCK = "${aws_waf_ipset.ipset_manual.id}"
      IP_SET_ID_AUTO_BLOCK = "${aws_waf_ipset.ipset_auto.id}"
      BLACKLIST_BLOCK_PERIOD = "${var.config_waf_block_period}"
      REQUEST_PER_MINUTE_LIMIT = "${var.config_request_threshold}"
    }
  }  
}

resource "aws_waf_ipset" "ipset_manual" {
  name = "Manual Block Set"
}

resource "aws_waf_rule" "rule_manual" {
  depends_on  = ["aws_waf_ipset.ipset_manual"]
  name        = "ManualBlockRule"
  metric_name = "ManualBlockRule"

  predicates {
    data_id = "${aws_waf_ipset.ipset_manual.id}"
    negated = false
    type    = "IPMatch"
  }
}

resource "aws_waf_ipset" "ipset_auto" {
  name = "Auto Block Set"
}

resource "aws_waf_rule" "rule_auto" {
  depends_on  = ["aws_waf_ipset.ipset_auto"]
  name        = "AutoBlockRule"
  metric_name = "AutoBlockRule"

  predicates {
    data_id = "${aws_waf_ipset.ipset_auto.id}"
    negated = false
    type    = "IPMatch"
  }
}

resource "aws_waf_web_acl" "waf_acl" {
  depends_on  = ["aws_waf_rule.rule_auto", "aws_waf_rule.rule_manual"]
  name        = "Malicious Requesters"
  metric_name = "MaliciousRequesters"

  default_action {
    type = "ALLOW"
  }

  rules {
	    action {
	      type = "BLOCK"
	    }
	    priority = 1
	    rule_id  = "${aws_waf_rule.rule_manual.id}"
	  }
  rules
    {
	    action {
	      type = "BLOCK"
	    }
	    priority = 2
	    rule_id  = "${aws_waf_rule.rule_auto.id}"
	  }
  
}

resource "aws_iam_role" "lambda_role" {
  name_prefix        = "lambda_execution_role"  
  path               = "/"
  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": ["lambda.amazonaws.com"]
      },
      "Action": ["sts:AssumeRole"]
    }]
}
POLICY
}

resource "aws_lambda_permission" "allow_lambda_function" {
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.lambda_function.arn}"
  principal      = "s3.amazonaws.com"
  source_account = "${data.aws_caller_identity.current.account_id}"
  source_arn     = "arn:aws:s3:::${var.cdn_log_bucket}"
}


resource "aws_iam_role_policy" "lambda_role_policy" {
  role   = "${aws_iam_role.lambda_role.id}"
  depends_on = [
        "aws_waf_ipset.ipset_manual",
        "aws_waf_ipset.ipset_auto",
        "aws_waf_rule.rule_manual",
        "aws_waf_rule.rule_auto",
        "aws_waf_web_acl.waf_acl"
   ]
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "waf:*",
      "Resource": [
        "${aws_waf_ipset.ipset_manual.arn}",
        "${aws_waf_ipset.ipset_auto.arn}",
        "arn:aws:waf::${data.aws_caller_identity.current.account_id}:rules/${aws_waf_rule.rule_manual.id}",
        "arn:aws:waf::${data.aws_caller_identity.current.account_id}:rules/${aws_waf_rule.rule_auto.id}",
        "arn:aws:waf::${data.aws_caller_identity.current.account_id}:webacl/${aws_waf_web_acl.waf_acl.id}",
        "arn:aws:waf::${data.aws_caller_identity.current.account_id}:changetoken/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "logs:*",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": [
        "${aws_s3_bucket.ops_bucket.arn}",
        "${aws_s3_bucket.ops_bucket.arn}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:Get*",
        "s3:List*",
        "s3:Describe*"
      ],
      "Resource": [
        "arn:aws:s3:::${var.cdn_log_bucket}",
        "arn:aws:s3:::${var.cdn_log_bucket}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "cloudwatch:PutMetricData",
      "Resource": "*"
    }
  ]
}
EOF
}

output "acl_id" {
  value = "${aws_waf_web_acl.waf_acl.id}"
}
