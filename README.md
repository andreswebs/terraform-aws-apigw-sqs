# terraform-aws-apigw-sqs

An API Gateway REST endpoint that writes request bodies onto an SQS queue.

## Authentication

Three shapes, chosen by two variables:

- **`api_key_enabled = true` (default)**: callers send `x-api-key`.
- **`lambda_authorizer_enabled = true`**: supply the authorizer's OpenAPI
  security scheme through `lambda_authorizer_openapi_security_scheme` and own
  the function separately. Use this when the caller's credential is something API
  Gateway cannot check natively, such as a Bearer JWT signed HS256.
- **Both**: the API key is sourced from the authorizer rather than the header
  (`x-amazon-apigateway-api-key-source: AUTHORIZER`).

Both disabled leaves the endpoint open. That is only appropriate if something
else in front of it is doing the authentication.

## Account prerequisite

The stage's access logging and the `INFO` execution logging both depend on the
account-and-region-level API Gateway CloudWatch role
(`aws_api_gateway_account`). This module does not create it. Use
[`apigw-logs-iam`](https://github.com/andreswebs/terraform-aws-apigw-logs-iam) once per account and region to create it.

## Usage

```hcl
module "webhook" {
  source = "git::ssh://git@github.com/Particle41/terraform.git//aws/apigw-sqs/v1?ref=main"

  api_name      = "example-webhook"
  api_title     = "example-webhook"
  queue_name    = "example-webhook"
  iam_role_name = "apigateway-example-webhook"

  dlq_queue_name        = "example-webhook-dlq"
  dlq_max_receive_count = 5

  queue_visibility_timeout_seconds = 300

  ## The caller sends a Bearer JWT, not an x-api-key header.
  api_key_enabled           = false
  lambda_authorizer_enabled = true

  lambda_authorizer_openapi_security_scheme = jsonencode({
    type                           = "apiKey"
    name                           = "Authorization"
    in                             = "header"
    "x-amazon-apigateway-authtype" = "custom"
    "x-amazon-apigateway-authorizer" = {
      type                         = "token"
      authorizerUri                = "arn:aws:apigateway:${var.region}:lambda:path/2015-03-31/functions/${aws_lambda_function.authorizer.arn}/invocations"
      authorizerCredentials        = aws_iam_role.authorizer_invoke.arn
      authorizerResultTtlInSeconds = 300
      identityValidationExpression = "^Bearer [A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$"
    }
  })

  ssm_parameter_name_api_url = "/example/webhook-url"

  tags = { Service = "example-webhook" }
}
```

## The message body is URL-encoded

The integration posts to SQS as `application/x-www-form-urlencoded`, so the
request template wraps the body:

```text
Action=SendMessage&MessageBody=$util.urlEncode($input.body)
```

Without the encoding, an `&` anywhere in the
payload starts a new form parameter and the message is silently truncated at
that point, and a `+` decodes to a space. Any payload carrying a URL with a
query string hits this.

Anything added through `apigateway_request_templates` is appended **after**
the encoded body, as further form parameters. That is what the FIFO
`MessageDeduplicationId` and `MessageGroupId` usage needs. Do not
URL-encode values passed there.

The template is registered under both `application/json` and the `$default`
catch-all, so an unexpected request `Content-Type` cannot produce a 415 and
lose the event at the edge.

## Tests

### Offline

Runs against a mocked AWS provider. No credentials, no account, nothing
created:

```sh
terraform init -backend=false
terraform test
```

The runs use `command = apply` against `mock_provider`, not `command = plan`,
because the rendered OpenAPI spec depends on the integration role's ARN, which
is unknown during plan. Mocked applies make it known while staying entirely
local.

### Live round trip

The offline suite can assert that the request template _says_
`$util.urlEncode`. It cannot prove the encoding works, because VTL is evaluated
by API Gateway and nothing offline renders it. The integration test verifies that

Run:

```sh
cd tests/integration
AWS_PROFILE="${SCRATCH_PROFILE}" AWS_REGION="${SCRATCH_REGION}" ./run.bash
```

It deploys the module using a per-run name prefix, POSTs every payload in
`tests/integration/payloads/` (bodies containing `&`, `=`, `+`, `%`, real
newlines, escaped quotes, backslashes and non-ASCII), reads each back off the
queue, asserts the delivered body is byte-identical with `cmp`, and destroys
the stack when ended, including on failure.

This test creates and destroys real resources, and an
aborted run can leave them behind.

[//]: # (BEGIN_TF_DOCS)


## Usage

Example:

```hcl
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
```



## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_api_key_enabled"></a> [api\_key\_enabled](#input\_api\_key\_enabled) | Whether to enable API key for API Gateway | `bool` | `true` | no |
| <a name="input_api_key_name"></a> [api\_key\_name](#input\_api\_key\_name) | The name of the API Gateway key | `string` | `"default"` | no |
| <a name="input_api_name"></a> [api\_name](#input\_api\_name) | The API name in API Gateway | `string` | `"webhook"` | no |
| <a name="input_api_path"></a> [api\_path](#input\_api\_path) | (optional) The API path | `string` | `"/"` | no |
| <a name="input_api_stage_name"></a> [api\_stage\_name](#input\_api\_stage\_name) | The name of the API Gateway stage | `string` | `"default"` | no |
| <a name="input_api_title"></a> [api\_title](#input\_api\_title) | The `info.title` value in the OpenAPI spec | `string` | `"webhook"` | no |
| <a name="input_api_usage_plan_name"></a> [api\_usage\_plan\_name](#input\_api\_usage\_plan\_name) | The name of the API Gateway usage plan | `string` | `"default"` | no |
| <a name="input_apigateway_caching_enabled"></a> [apigateway\_caching\_enabled](#input\_apigateway\_caching\_enabled) | API Gateway method settings - caching\_enabled | `bool` | `false` | no |
| <a name="input_apigateway_data_trace_enabled"></a> [apigateway\_data\_trace\_enabled](#input\_apigateway\_data\_trace\_enabled) | API Gateway method settings - data\_trace\_enabled | `bool` | `false` | no |
| <a name="input_apigateway_integration_request_parameters"></a> [apigateway\_integration\_request\_parameters](#input\_apigateway\_integration\_request\_parameters) | A JSON object of API Gateway Integration request parameter mappings.<br/>These will be placed under the `x-amazon-apigateway-integration.requestParameters`<br/>field in the OpenAPI spec.<br/>See:<br/><https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-integration-requestParameters.html> | `string` | `"{}"` | no |
| <a name="input_apigateway_logging_level"></a> [apigateway\_logging\_level](#input\_apigateway\_logging\_level) | API Gateway method settings - logging\_level | `string` | `"INFO"` | no |
| <a name="input_apigateway_method_parameters"></a> [apigateway\_method\_parameters](#input\_apigateway\_method\_parameters) | A JSON array of API Gateway Method request parameters.<br/>Each element in the array must be a valid OpenAPI `parameter` object.<br/>See:<br/><https://swagger.io/docs/specification/describing-parameters/> | `string` | `""` | no |
| <a name="input_apigateway_metrics_enabled"></a> [apigateway\_metrics\_enabled](#input\_apigateway\_metrics\_enabled) | API Gateway method settings - metrics\_enabled | `bool` | `true` | no |
| <a name="input_apigateway_request_templates"></a> [apigateway\_request\_templates](#input\_apigateway\_request\_templates) | String appended to the API Gateway integration request template, after the<br/>URL-encoded message body. Use it to add further form parameters.<br/>If using a FIFO queue, this variable must contain a value similar to the following:<br/>`&MessageDeduplicationId=$context.requestId&MessageGroupId=$input.json('$.Example')`<br/><br/>Note that the message body itself is URL-encoded by the module and must not<br/>be added here. | `string` | `""` | no |
| <a name="input_dlq_max_receive_count"></a> [dlq\_max\_receive\_count](#input\_dlq\_max\_receive\_count) | Number of times a consumer can receive a message from the main queue before it is moved to the dead-letter queue | `number` | `1` | no |
| <a name="input_dlq_message_retention_seconds"></a> [dlq\_message\_retention\_seconds](#input\_dlq\_message\_retention\_seconds) | (Optional) How long the dead-letter queue keeps a message, in seconds.<br/>Defaults to `queue_message_retention_seconds`: a dead-letter queue that<br/>expires sooner than the queue feeding it destroys the evidence it exists to<br/>preserve. | `number` | `null` | no |
| <a name="input_dlq_queue_name"></a> [dlq\_queue\_name](#input\_dlq\_queue\_name) | Name for the dead-letter queue. Defaults to `<queue_name>-dlq`. | `string` | `null` | no |
| <a name="input_fifo_queue"></a> [fifo\_queue](#input\_fifo\_queue) | Whether to use a FIFO queue | `bool` | `false` | no |
| <a name="input_iam_role_name"></a> [iam\_role\_name](#input\_iam\_role\_name) | The name of the IAM role for API Gateway | `string` | `"apigateway-webhook"` | no |
| <a name="input_lambda_authorizer_enabled"></a> [lambda\_authorizer\_enabled](#input\_lambda\_authorizer\_enabled) | Whether to enable Lambda Autorizer for API Gateway.<br/>If enabled, `lambda_authorizer_openapi_security_scheme` must be set. | `bool` | `false` | no |
| <a name="input_lambda_authorizer_openapi_security_scheme"></a> [lambda\_authorizer\_openapi\_security\_scheme](#input\_lambda\_authorizer\_openapi\_security\_scheme) | A partial OpenAPI configuration for the Lambda Authorizer.<br/>This must be a valid JSON string representing a valid OpenAPI security scheme object.<br/>It will be placed under the `components.securitySchemes.lambda-authorizer`<br/>field in the OpenAPI spec.<br/>See:<br/><https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-authorizer.html> | `string` | `""` | no |
| <a name="input_log_group_kms_key_id"></a> [log\_group\_kms\_key\_id](#input\_log\_group\_kms\_key\_id) | KMS key ID to use for log group encryption | `string` | `null` | no |
| <a name="input_log_group_name_prefix"></a> [log\_group\_name\_prefix](#input\_log\_group\_name\_prefix) | Name prefix for the created log group | `string` | `"/aws/apigateway/"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Log retention in days | `number` | `90` | no |
| <a name="input_queue_message_retention_seconds"></a> [queue\_message\_retention\_seconds](#input\_queue\_message\_retention\_seconds) | (Optional) How long the queue keeps a message, in seconds, from 60 to<br/>1209600 (14 days).<br/>When null the AWS default of 4 days applies, which is shorter than a buffer<br/>fronting an unreliable consumer usually wants. | `number` | `null` | no |
| <a name="input_queue_name"></a> [queue\_name](#input\_queue\_name) | The queue name | `string` | `"webhook"` | no |
| <a name="input_queue_visibility_timeout_seconds"></a> [queue\_visibility\_timeout\_seconds](#input\_queue\_visibility\_timeout\_seconds) | (Optional) Visibility timeout for the queue (default: 30) | `number` | `null` | no |
| <a name="input_sqs_managed_sse_enabled"></a> [sqs\_managed\_sse\_enabled](#input\_sqs\_managed\_sse\_enabled) | Whether to enable SQS-managed server-side encryption on both queues.<br/>Enabled by default: the module is a webhook sink, so the queue contents are<br/>whatever a third party posted. | `bool` | `true` | no |
| <a name="input_ssm_parameter_kms_key_id"></a> [ssm\_parameter\_kms\_key\_id](#input\_ssm\_parameter\_kms\_key\_id) | KMS key ID to use for SSM parameter encryption | `string` | `null` | no |
| <a name="input_ssm_parameter_name_api_key"></a> [ssm\_parameter\_name\_api\_key](#input\_ssm\_parameter\_name\_api\_key) | The name of the SSM parameter to store the API key.<br/>Only used when `api_key_enabled` is true. When null or empty, the<br/>parameter is not created. | `string` | `null` | no |
| <a name="input_ssm_parameter_name_api_url"></a> [ssm\_parameter\_name\_api\_url](#input\_ssm\_parameter\_name\_api\_url) | The name of the SSM parameter to store the API URL.<br/>When null or empty, the parameter is not created and the `api_url` output<br/>remains the only way to read the URL. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |

## Modules

No modules.

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_api"></a> [api](#output\_api) | The `aws_api_gateway_rest_api` resource |
| <a name="output_api_key"></a> [api\_key](#output\_api\_key) | The `aws_api_gateway_api_key` resource |
| <a name="output_api_stage"></a> [api\_stage](#output\_api\_stage) | The `aws_api_gateway_stage` resource |
| <a name="output_api_url"></a> [api\_url](#output\_api\_url) | The configured API URL |
| <a name="output_dlq"></a> [dlq](#output\_dlq) | The dead-letter `aws_sqs_queue` resource |
| <a name="output_iam_role"></a> [iam\_role](#output\_iam\_role) | API Gateway integration IAM role |
| <a name="output_integration_request_template"></a> [integration\_request\_template](#output\_integration\_request\_template) | The API Gateway integration request template, as sent to SQS. Exposed so<br/>that callers and tests can assert the message body is URL-encoded without<br/>decoding the whole OpenAPI spec. |
| <a name="output_log_group"></a> [log\_group](#output\_log\_group) | The access log `aws_cloudwatch_log_group` resource |
| <a name="output_openapi_spec"></a> [openapi\_spec](#output\_openapi\_spec) | The OpenAPI spec |
| <a name="output_queue"></a> [queue](#output\_queue) | The `aws_sqs_queue` resource |
| <a name="output_ssm_parameter_api_key_name"></a> [ssm\_parameter\_api\_key\_name](#output\_ssm\_parameter\_api\_key\_name) | Name of the `aws_ssm_parameter` holding the API key, or null if not created |
| <a name="output_ssm_parameter_api_url_name"></a> [ssm\_parameter\_api\_url\_name](#output\_ssm\_parameter\_api\_url\_name) | Name of the `aws_ssm_parameter` holding the API URL, or null if not created |
| <a name="output_test_cmd"></a> [test\_cmd](#output\_test\_cmd) | Commands to test the integration |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.64.0 |

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.14 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Resources

| Name | Type |
| ---- | ---- |
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
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_redrive_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_policy) | resource |
| [aws_ssm_parameter.api_key](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
| [aws_ssm_parameter.api_url](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ssm_parameter) | resource |
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

This project is licensed under the [Unlicense](UNLICENSE).
