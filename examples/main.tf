## Minimal example: an API-key protected webhook sink.
##
## For the Lambda authorizer shape, see the README.

module "webhook" {
  source = "git::ssh://git@github.com/Particle41/terraform.git//aws/apigw-sqs/v1?ref=main"

  api_name      = "example-webhook"
  api_title     = "example-webhook"
  queue_name    = "example-webhook"
  iam_role_name = "apigateway-example-webhook"

  dlq_max_receive_count = 5

  ssm_parameter_name_api_key = "/example/webhook-api-key"
  ssm_parameter_name_api_url = "/example/webhook-url"

  tags = { Service = "example-webhook" }
}

output "queue_url" {
  description = "Where the delivered webhook bodies land"
  value       = module.webhook.queue.id
}

output "dlq_name" {
  description = "Dead-letter queue name, for a depth alarm"
  value       = module.webhook.dlq.name
}
