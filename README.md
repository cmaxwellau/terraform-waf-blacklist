# Terraform WAF Blacklist

This portable tool is intended to standup dedicated functionality for processing CloudFront access logs, identifying bad actors, and then blacklisting those bad actors by adding them to a WAF blacklist, and then attaching that WAF blacklist to the CloudFront distribution.

There are 2 ways to use this tooling:
* Extend single existing web application
* Extend multiple existing web applications

##Configure AWS credentials in your environment for terraform
You can set a default region in the CLI environment. This can still be overriden by an explicit command line option.

```
$ export AWS_REGION=ap-southeast-2
```

Configure AWS credentials using a profile in ~/.aws/credentials and refer to it through an environment variable:

```
$ export AWS_PROFILE=my-dev-account-profile
```

You can also configure explicit credentials using environment variables:

```
$ export AWS_ACCESS_KEY_ID=AKIA12345678ABCDEAFGH
$ export AWS_SECRET_ACCESS_KEY=12345678ABCDEFGHabcdefgh12345678abcdefgh
```

# Example Web Application
A working example site is included with this code in the *example-wesite* folder

## Set *aws_region* in vars file
```
$ vim terraform.tfvars.tf
aws_region = "ap-southeast-2"
```

## Deploy example website
```
$ terraform init
$ terraform apply...
Outputs:

cdn_log_bucket = example-website-logs-abcd1234
cdn_log_prefix = website-cdn/
```

# (Single application) Modifying your existing Web Application terrform template
Make the following changes to ensure that your existing template can both producte the needed outputs for the WAF Blacklist functionality, and can accept an optional WAF Web ACL id which will be generated later.

Add variable with a default empty value:
```
variable "web_acl_id" {default = ""}
```

Add a new web_acl_id parameter to CloudFront distribution:
```
resource "aws_cloudfront_distribution" "website_cdn" {
  ...
  web_acl_id = "${var.web_acl_id}"
}
```

Add exports for cloudfront distribution logging configuration:
```
output "cdn_log_bucket" {
  value = "${lookup(aws_cloudfront_distribution.website_cdn.logging_config[0], "bucket")}"
}

output "cdn_log_prefix" {
  value = "${lookup(aws_cloudfront_distribution.website_cdn.logging_config[0], "prefix")}"
}
```

## Update Web Application resources.
Update the web application with terraform to get new output values. Record the output values for *cdn_logs_bucket* and *cdn_logs_prefix* as you will use them as inputs to the next step:
```
$ terraform update
...
Outputs:

cdn_log_bucket = example-website-logs-abcd1234
cdn_log_prefix = website-cdn/
```

# (Multiple applications) Modifying your existing Web Application terrform template
You can have a single set of WAF blacklist functionality shared across multiple CloudFront enabled applications by making the following changes:
* Create a single dedicated S3 bucket for all of your application logs.
* Add web-acl-id parameter extension as above.
* Make sure each CloudFront distribution is configure to use this S3 bucket.
* Make sure each CloudFront distribution shared a common prefix for log files. 

Application 1:
```
resource "aws_cloudfront_distribution" "website_cdn" {
  ...
  "logging_config" {
    include_cookies = false
    bucket          = "my-common-logging-bucket.s3.amazonaws.com"
    prefix          = "all-cdn-logs/application1"
  }
  ...
}
```

Application 2:
```
resource "aws_cloudfront_distribution" "website_cdn" {
  ...
  "logging_config" {
    include_cookies = false
    bucket          = "my-common-logging-bucket.s3.amazonaws.com"
    prefix          = "all-cdn-logs/application2"
  }
  ...
}
```

In this use case, the variables for the WAF blacklist implementation would be *my-common-logging-bucket* and *all-cdn-logs/*


# Stand up WAF blacklist resources
The WAF Blacklist resources are contained in the *waf-blacklist* directory.

Set *aws_region*, *cdn_log_bucket*, and *cdn_log_prefix* variables in the terraform vars file. The bucket and prefix variables are output from a terrform template that has been modified as per above.
```
$ vim terraform.tfvars.tf
aws_region = "ap-southeast-2"
cdn_log_bucket = "example-website-logs-abcd1234"
cdn_log_prefix = "website-cdn/"
```

Create the WAF Blasklist resources using terraform, and take note ofthe output variable for *acl_id*
```
$ terraform init
$ terraform apply --var cdn_log_bucket=example-website-logs-abcd1234 --var cdn_log_prefix=website-cdn/
Outputs:

acl_id = 01234567-5678-abcd-1234-a6cbdf0a010d
```

## Update Web Application(s) to apply WAF Blacklist Web ACL.
You can apply the newly created Web ACL to one, or multiple, CloudFront Web Application that have been modified to accept a web-acli-id parameter as shown above. This variable can be supplied directly on the command line, or spcified in a *terraform.tfvars.tf* file.

```
$ terraform apply -var web_acl_id=01234567-5678-abcd-1234-a6cbdf0a010d
...
Outputs:

cdn_logs_bucket = example-website-logs-abcd1234
cdn_logs_prefix = website-cdn/
```

# Testing the WAF Blacklist
A test script is included -*test.py* - that will continually request random URLs from a WAF-enabled website until is gets a HTTP:403 Not Authorised error, and will report the time taken for the block to to be put in place.

```
$ ./test.py -u https://abcd1234.cloudfront.net/ -c 1000

https://abcd1234.cloudfront.net/czpk5bkweyll: 404
https://abcd1234.cloudfront.net/45kexlg7lbfv: 404
https://abcd1234.cloudfront.net/e2t20flrm3sj: 404
...
https://abcd1234.cloudfront.net/7m9gi7h14pe1: 404
https://abcd1234.cloudfront.net/r2ezucuui3oc: 403
We were blocked in 204 seconds!
```