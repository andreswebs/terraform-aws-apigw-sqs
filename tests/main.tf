module "apigw_sqs" {
  source                                    = "../"
  api_key_enabled                           = false
  lambda_authorizer_enabled                 = true
  lambda_authorizer_openapi_security_scheme = <<-EOT
    {
      "test": "ok"
    }
  EOT
}
