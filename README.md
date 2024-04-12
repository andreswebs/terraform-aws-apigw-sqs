# terraform-aws-apigw-sqs

Create an API Gateway endpoint that publishes to an SQS queue.

[//]: # (BEGIN_TF_DOCS)


## Usage

Example:

```hcl
module "apigw_sqs" {
  source = "github.com/andreswebs/terraform-aws-apigw-sqs"
}
```



## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_api_key_enabled"></a> [api\_key\_enabled](#input\_api\_key\_enabled) | Whether to enable API key for API Gateway | `bool` | `true` | no |
| <a name="input_api_key_name"></a> [api\_key\_name](#input\_api\_key\_name) | The name of the API Gateway key | `string` | `"default"` | no |
| <a name="input_api_name"></a> [api\_name](#input\_api\_name) | The API name in API Gateway | `string` | `"webhook"` | no |
| <a name="input_api_path"></a> [api\_path](#input\_api\_path) | (optional) The API path | `string` | `"/"` | no |
| <a name="input_api_stage_name"></a> [api\_stage\_name](#input\_api\_stage\_name) | The name of the API Gateway stage | `string` | `"default"` | no |
| <a name="input_api_title"></a> [api\_title](#input\_api\_title) | The `info.title` value in the OpenAPI spec | `string` | `"webhook"` | no |
| <a name="input_api_usage_plan_name"></a> [api\_usage\_plan\_name](#input\_api\_usage\_plan\_name) | The name of the API Gateway usage plan | `string` | `"default"` | no |
| <a name="input_apigateway_integration_request_parameters"></a> [apigateway\_integration\_request\_parameters](#input\_apigateway\_integration\_request\_parameters) | A JSON object of API Gateway Integration request parameter mappings.<br>These will be placed under the `x-amazon-apigateway-integration.requestParameters`<br>field in the OpenAPI spec.<br>See:<br><https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-integration-requestParameters.html> | `string` | `"{}"` | no |
| <a name="input_apigateway_method_parameters"></a> [apigateway\_method\_parameters](#input\_apigateway\_method\_parameters) | A JSON array of API Gateway Method request parameters.<br>Each element in the array must be a valid OpenAPI `parameter` object.<br>See:<br><https://swagger.io/docs/specification/describing-parameters/> | `string` | `""` | no |
| <a name="input_iam_role_name"></a> [iam\_role\_name](#input\_iam\_role\_name) | The name of the IAM role for API Gateway | `string` | `"apigateway-webhook"` | no |
| <a name="input_lambda_authorizer_enabled"></a> [lambda\_authorizer\_enabled](#input\_lambda\_authorizer\_enabled) | Whether to enable Lambda Autorizer for API Gateway.<br>If enabled, `lambda_authorizer_openapi_security_scheme` must be set. | `bool` | `false` | no |
| <a name="input_lambda_authorizer_openapi_security_scheme"></a> [lambda\_authorizer\_openapi\_security\_scheme](#input\_lambda\_authorizer\_openapi\_security\_scheme) | A partial OpenAPI configuration for the Lambda Authorizer.<br>This must be a valid JSON string representing a valid OpenAPI security scheme object.<br>It will be placed under the `components.securitySchemes.lambda-authorizer`<br>field in the OpenAPI spec.<br>See:<br><https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-authorizer.html> | `string` | `""` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Log retention in days | `number` | `30` | no |
| <a name="input_queue_name"></a> [queue\_name](#input\_queue\_name) | The queue name | `string` | `"webhook"` | no |
| <a name="input_ssm_parameter_name_api_key"></a> [ssm\_parameter\_name\_api\_key](#input\_ssm\_parameter\_name\_api\_key) | The name of the SSM parameter to store the API key | `string` | `null` | no |
| <a name="input_ssm_parameter_name_url"></a> [ssm\_parameter\_name\_url](#input\_ssm\_parameter\_name\_url) | The name of the SSM parameter to store the webhook URL | `string` | `null` | no |

## Modules

No modules.

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_api"></a> [api](#output\_api) | The `aws_api_gateway_rest_api` resource |
| <a name="output_api_key"></a> [api\_key](#output\_api\_key) | The `aws_api_gateway_api_key` resource |
| <a name="output_api_stage"></a> [api\_stage](#output\_api\_stage) | The `aws_api_gateway_stage` resource |
| <a name="output_iam_role"></a> [iam\_role](#output\_iam\_role) | API Gateway integration IAM role |
| <a name="output_invoke_url"></a> [invoke\_url](#output\_invoke\_url) | The API Gateway invocation URL |
| <a name="output_openapi_spec"></a> [openapi\_spec](#output\_openapi\_spec) | The OpenAPI spec |
| <a name="output_queue"></a> [queue](#output\_queue) | The `aws_sqs_queue` resource |
| <a name="output_test_cmd"></a> [test\_cmd](#output\_test\_cmd) | Commands to test the integration |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Resources

| Name | Type |
|------|------|
| [aws_api_gateway_api_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_api_key) | resource |
| [aws_api_gateway_deployment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment) | resource |
| [aws_api_gateway_method_settings.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method_settings) | resource |
| [aws_api_gateway_rest_api.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api) | resource |
| [aws_api_gateway_stage.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage) | resource |
| [aws_api_gateway_usage_plan.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_usage_plan) | resource |
| [aws_api_gateway_usage_plan_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_usage_plan_key) | resource |
| [aws_cloudwatch_log_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_role.apigw_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.apigw_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_sqs_queue.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_ssm_parameter.api_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.url](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.apigw_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apigw_permissions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.apigw_service_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

[//]: # (END_TF_DOCS)

## Authors

**Andre Silva** - [@andreswebs](https://github.com/andreswebs)

## License

This project is licensed under the [Unlicense](UNLICENSE.md).
