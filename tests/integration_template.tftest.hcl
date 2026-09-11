## The API Gateway to SQS integration request template.
##
## The assertions here guard the one defect in this module that fails silently
## in production: the message body must be URL-encoded, because the integration
## posts to SQS as application/x-www-form-urlencoded and an unencoded `&` in the
## payload would start a new form parameter and truncate the message.
##
## These are structural assertions only. They cannot prove the encoding works,
## because VTL is evaluated by API Gateway and nothing offline renders it. See
## tests/integration for the live round trip that does prove it.

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

run "body_is_url_encoded" {
  command = apply

  assert {
    condition     = output.integration_request_template == "Action=SendMessage&MessageBody=$util.urlEncode($input.body)"
    error_message = "The message body must be wrapped in $util.urlEncode, or payloads containing & or + are silently corrupted."
  }

  assert {
    condition     = strcontains(jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].requestTemplates["application/json"], "$util.urlEncode($input.body)")
    error_message = "The rendered OpenAPI spec must carry the URL-encoded body template."
  }
}

run "both_content_type_keys_are_registered" {
  command = apply

  assert {
    condition     = length(keys(jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].requestTemplates)) == 2
    error_message = "Exactly two request template keys are expected: application/json and $default."
  }

  assert {
    condition     = contains(keys(jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].requestTemplates), "$default")
    error_message = "A $default template must be registered, or an unexpected Content-Type is a 415 and the event is lost before the buffer."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].requestTemplates["application/json"] == jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].requestTemplates["$default"]
    error_message = "Both request template keys must carry the identical template."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].passthroughBehavior == "never"
    error_message = "passthroughBehavior must stay never: an unmapped body must not reach SQS raw."
  }
}

run "appended_templates_stay_outside_the_encoding" {
  command = apply

  variables {
    apigateway_request_templates = "&MessageDeduplicationId=$context.requestId"
  }

  assert {
    condition     = output.integration_request_template == "Action=SendMessage&MessageBody=$util.urlEncode($input.body)&MessageDeduplicationId=$context.requestId"
    error_message = "Caller-appended parameters must follow the encoded body as separate form parameters, not be encoded with it."
  }

  assert {
    condition     = endswith(output.integration_request_template, "&MessageDeduplicationId=$context.requestId")
    error_message = "The appended value must land at the end of the template."
  }
}

run "integration_target_and_credentials" {
  command = apply

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].uri == "arn:aws:apigateway:us-east-1:sqs:path/123456789012/webhook"
    error_message = "The integration URI must address the module's own queue in this account and region."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].credentials == aws_iam_role.apigw_service.arn
    error_message = "The integration must use the role this module creates."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].type == "aws"
    error_message = "The integration must be a direct AWS service integration."
  }
}

run "content_type_header_is_forced" {
  command = apply

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].requestParameters["integration.request.header.Content-Type"] == "'application/x-www-form-urlencoded'"
    error_message = "SQS requires the form-encoded Content-Type on the integration request."
  }
}

run "caller_request_parameters_merge_with_the_default" {
  command = apply

  variables {
    apigateway_integration_request_parameters = "{\"integration.request.header.X-Extra\": \"'y'\"}"
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].requestParameters["integration.request.header.X-Extra"] == "'y'"
    error_message = "Caller-supplied integration request parameters must be present."
  }

  assert {
    condition     = jsondecode(output.openapi_spec).paths["/"].post["x-amazon-apigateway-integration"].requestParameters["integration.request.header.Content-Type"] == "'application/x-www-form-urlencoded'"
    error_message = "Caller-supplied parameters must not displace the mandatory Content-Type."
  }
}
