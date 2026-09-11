## The four combinations of api_key_enabled and lambda_authorizer_enabled, and
## what each renders into the OpenAPI spec. The both-disabled case matters
## because the security scheme block collapses to an empty object and the spec
## still has to be valid JSON.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }

  ## The provider validates some attributes as real ARNs even under mocks, so a
  ## generated random string fails the apply. The stage's access_log_settings
  ## check on the log group ARN is the one that bites.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock"
    }
  }
}

## Per-address overrides, so that assertions comparing the redrive policy to the
## dead-letter queue's ARN compare two distinct real values instead of passing
## trivially on one shared generated string.

override_resource {
  target = aws_sqs_queue.this
  values = {
    arn = "arn:aws:sqs:us-east-1:123456789012:main"
  }
}

override_resource {
  target = aws_sqs_queue.dlq
  values = {
    arn = "arn:aws:sqs:us-east-1:123456789012:dead-letter"
  }
}

override_resource {
  target = aws_iam_role.apigw_service
  values = {
    arn = "arn:aws:iam::123456789012:role/mock-apigw"
  }
}

override_resource {
  target = aws_api_gateway_stage.this
  values = {
    invoke_url = "https://abc123.execute-api.us-east-1.amazonaws.com/default"
  }
}

run "api_key_only" {
  command = apply

  assert {
    condition     = jsondecode(output.openapi_spec)["x-amazon-apigateway-api-key-source"] == "HEADER"
    error_message = "With an API key and no authorizer, the key source is the header."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post.security == [{ "api-key" = [] }]
    error_message = "The method must require the api-key scheme."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).components.securitySchemes["api-key"].name == "x-api-key"
    error_message = "The api-key scheme must read the x-api-key header."
  }

  assert {
    condition     = length(aws_api_gateway_usage_plan.this) == 1 && length(aws_api_gateway_api_key.this) == 1 && length(aws_api_gateway_usage_plan_key.this) == 1
    error_message = "The usage plan, key and plan-key should all exist when the API key is enabled."
  }
}

run "nothing_enabled" {
  command = apply

  variables {
    api_key_enabled = false
  }

  assert {
    condition     = !contains(keys(jsondecode(output.openapi_spec)), "x-amazon-apigateway-api-key-source")
    error_message = "With no API key there must be no key source declared."
  }

  assert {
    condition     = !contains(keys(jsondecode(output.openapi_spec).paths["/"].post), "security")
    error_message = "With nothing enabled the method must carry no security requirement."
  }

  assert {
    condition     = length(keys(jsondecode(output.openapi_spec).components.securitySchemes)) == 0
    error_message = "With nothing enabled securitySchemes must render as a valid empty object."
  }

  assert {
    condition     = length(aws_api_gateway_usage_plan.this) == 0 && length(aws_api_gateway_api_key.this) == 0
    error_message = "No usage plan or key should exist when the API key is disabled."
  }
}

run "authorizer_only" {
  command = apply

  variables {
    api_key_enabled                           = false
    lambda_authorizer_enabled                 = true
    lambda_authorizer_openapi_security_scheme = "{\"type\":\"apiKey\",\"name\":\"Authorization\",\"in\":\"header\",\"x-amazon-apigateway-authtype\":\"custom\"}"
  }

  assert {
    condition     = !contains(keys(jsondecode(output.openapi_spec)), "x-amazon-apigateway-api-key-source")
    error_message = "Without an API key there must be no key source, even with an authorizer."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post.security == [{ "lambda-authorizer" = [] }]
    error_message = "The method must require the lambda-authorizer scheme."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).components.securitySchemes["lambda-authorizer"].name == "Authorization"
    error_message = "The supplied authorizer scheme must land verbatim under securitySchemes."
  }

  assert {
    condition     = !contains(keys(jsondecode(output.openapi_spec).components.securitySchemes), "api-key")
    error_message = "The api-key scheme must not be rendered when the API key is disabled."
  }
}

run "authorizer_and_api_key" {
  command = apply

  variables {
    api_key_enabled                           = true
    lambda_authorizer_enabled                 = true
    lambda_authorizer_openapi_security_scheme = "{\"type\":\"apiKey\",\"name\":\"Authorization\",\"in\":\"header\",\"x-amazon-apigateway-authtype\":\"custom\"}"
  }

  assert {
    condition     = jsondecode(output.openapi_spec)["x-amazon-apigateway-api-key-source"] == "AUTHORIZER"
    error_message = "With both enabled the API key must come from the authorizer, not the header."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post.security == [{ "lambda-authorizer" = [] }]
    error_message = "With both enabled the authorizer is the method's security requirement."
  }

  assert {
    condition     = !contains(keys(jsondecode(output.openapi_spec).components.securitySchemes), "api-key")
    error_message = "With both enabled only the authorizer scheme is rendered."
  }
}

run "method_parameters" {
  command = apply

  variables {
    apigateway_method_parameters = "[{\"name\":\"X-Test\",\"in\":\"header\",\"required\":true,\"schema\":{\"type\":\"string\"}}]"
  }

  assert {
    condition     = length(jsondecode(output.openapi_spec).paths["/"].post.parameters) == 1
    error_message = "Caller-supplied method parameters must be rendered."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post.parameters[0].name == "X-Test"
    error_message = "The method parameter must land verbatim."
  }
}

run "no_method_parameters_by_default" {
  command = apply

  assert {
    condition     = !contains(keys(jsondecode(output.openapi_spec).paths["/"].post), "parameters")
    error_message = "No parameters key should be emitted when none are supplied."
  }
}

run "api_path_and_base_path" {
  command = apply

  variables {
    api_path       = "/coderbyte"
    api_stage_name = "live"
  }

  assert {
    condition     = contains(keys(jsondecode(output.openapi_spec).paths), "/coderbyte")
    error_message = "The configured api_path must be the spec's path key."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).servers[0].variables.basePath.default == "/live"
    error_message = "The base path must follow the stage name."
  }
}
