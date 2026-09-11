output "queue" {
  value       = aws_sqs_queue.this
  description = "The `aws_sqs_queue` resource"
}

output "dlq" {
  value       = aws_sqs_queue.dlq
  description = "The dead-letter `aws_sqs_queue` resource"
}

output "api" {
  description = "The `aws_api_gateway_rest_api` resource"
  value       = aws_api_gateway_rest_api.this
}

output "api_stage" {
  description = "The `aws_api_gateway_stage` resource"
  value       = aws_api_gateway_stage.this
}

output "api_url" {
  description = "The configured API URL"
  value       = local.api_url
}

output "api_key" {
  description = "The `aws_api_gateway_api_key` resource"
  value       = aws_api_gateway_api_key.this

  ## The resource carries the key itself in `value`, so the whole object is
  ## sensitive. Without this a caller using the module as a root module cannot
  ## plan at all.
  sensitive = true
}

output "log_group" {
  description = "The access log `aws_cloudwatch_log_group` resource"
  value       = aws_cloudwatch_log_group.this
}

output "iam_role" {
  description = "API Gateway integration IAM role"
  value       = aws_iam_role.apigw_service
}

output "openapi_spec" {
  description = "The OpenAPI spec"
  value       = local.openapi_spec
}

output "integration_request_template" {
  description = <<-EOT
    The API Gateway integration request template, as sent to SQS. Exposed so
    that callers and tests can assert the message body is URL-encoded without
    decoding the whole OpenAPI spec.
  EOT
  value       = local.apigateway_integration_request_template
}

## Names rather than the whole resources: `aws_ssm_parameter.value` is
## sensitive, so exposing the objects would make both outputs sensitive and
## force every caller to treat the API URL as a secret. The name is what a
## consumer needs anyway, to read the parameter at runtime.

output "ssm_parameter_api_key_name" {
  description = "Name of the `aws_ssm_parameter` holding the API key, or null if not created"
  value       = try(aws_ssm_parameter.api_key[0].name, null)
}

output "ssm_parameter_api_url_name" {
  description = "Name of the `aws_ssm_parameter` holding the API URL, or null if not created"
  value       = try(aws_ssm_parameter.api_url[0].name, null)
}

output "test_cmd" {
  description = "Commands to test the integration"
  value = {

    invoke = templatefile("${path.module}/tpl/invoke.sh.tftpl", {
      api_key_param_name = try(aws_ssm_parameter.api_key[0].name, null)
      api_url_param_name = try(aws_ssm_parameter.api_url[0].name, null)
      api_url            = local.api_url
      test_message       = "Hello from ApiGateway!"
    })

    retrieve = templatefile("${path.module}/tpl/retrieve.sh.tftpl", {
      queue_url = aws_sqs_queue.this.id
    })

  }
}
