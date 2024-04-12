output "queue" {
  value       = aws_sqs_queue.this
  description = "The `aws_sqs_queue` resource"
}

output "api" {
  description = "The `aws_api_gateway_rest_api` resource"
  value       = aws_api_gateway_rest_api.this
}

output "api_stage" {
  description = "The `aws_api_gateway_stage` resource"
  value       = aws_api_gateway_stage.this
}

output "invoke_url" {
  value       = aws_api_gateway_stage.this.invoke_url
  description = "The API Gateway invocation URL"
}

output "api_key" {
  description = "The `aws_api_gateway_api_key` resource"
  value       = aws_api_gateway_api_key.this
}

output "iam_role" {
  description = "API Gateway integration IAM role"
  value       = aws_iam_role.apigw_service
}

output "openapi_spec" {
  description = "The OpenAPI spec"
  value       = local.openapi_spec
}

output "test_cmd" {
  description = "Commands to test the integration"
  value = {

    invoke = templatefile("${path.module}/tpl/invoke.sh.tftpl", {
      api_key_enabled    = var.api_key_enabled
      api_key_param_name = var.api_key_enabled ? aws_ssm_parameter.api_key[0].name : null
      api_path           = var.api_path
      invoke_url         = aws_api_gateway_stage.this.invoke_url
      test_message       = "Hello from ApiGateway!"
    })

    retrieve = templatefile("${path.module}/tpl/retrieve.sh.tftpl", {
      queue_url = aws_sqs_queue.this.id
    })

  }
}
