output "api_url" {
  description = "URL to POST payloads to"
  value       = module.apigw_sqs.api_url
}

output "api_key" {
  description = "API key for the x-api-key header"
  value       = module.apigw_sqs.api_key[0].value
  sensitive   = true
}

output "queue_url" {
  description = "Queue to read the delivered payloads back from"
  value       = module.apigw_sqs.queue.id
}
