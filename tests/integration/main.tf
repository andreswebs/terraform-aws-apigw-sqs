## Fixture for the live round trip. The offline suite can only assert that the
## rendered template contains $util.urlEncode; whether API Gateway's VTL
## actually preserves a payload byte for byte can only be established by posting
## one and reading it back off the queue.
##
## The API key stays enabled so the fixture never stands up an unauthenticated
## public endpoint, even briefly.

module "apigw_sqs" {
  source = "../.."

  api_name      = var.name_prefix
  api_title     = var.name_prefix
  queue_name    = var.name_prefix
  iam_role_name = var.name_prefix

  api_usage_plan_name = var.name_prefix
  api_key_name        = var.name_prefix

  api_key_enabled = true

  ## Nothing polls this queue during the test, so a long visibility timeout
  ## would only slow a re-read after a failed comparison.
  queue_visibility_timeout_seconds = 30

  log_retention_days = 1

  tags = {
    Purpose = "apigw-sqs-integration-test"
  }
}
