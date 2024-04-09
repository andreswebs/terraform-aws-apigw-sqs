output "info" {
  value = {
    invoke_url = module.apigw_sqs.invoke_url
    test_cmd = module.apigw_sqs.test_cmd
    oas = module.apigw_sqs.openapi_spec
  }
}