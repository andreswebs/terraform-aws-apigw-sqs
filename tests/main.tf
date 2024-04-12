module "apigw_sqs" {
  source                     = "../"
  ssm_parameter_name_api_key = "/test/api-key"
  ssm_parameter_name_url     = "/test/url"
}
