## The optional SSM parameters, and that `tags` reaches everything taggable.
##
## The SSM cases exist because both parameters used to be created
## unconditionally while their name variables defaulted to null, so the module
## could not apply with its own defaults.

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

run "no_ssm_parameters_by_default" {
  command = apply

  assert {
    condition     = length(aws_ssm_parameter.api_url) == 0
    error_message = "The API URL parameter must not be created unless its name is given."
  }

  assert {
    condition     = length(aws_ssm_parameter.api_key) == 0
    error_message = "The API key parameter must not be created unless its name is given."
  }
}

run "api_url_parameter" {
  command = apply

  variables {
    ssm_parameter_name_api_url = "/test/api-url"
  }

  assert {
    condition     = length(aws_ssm_parameter.api_url) == 1
    error_message = "Naming the parameter should create it."
  }

  assert {
    condition     = aws_ssm_parameter.api_url[0].name == "/test/api-url"
    error_message = "The parameter must take the given name."
  }

  assert {
    condition     = aws_ssm_parameter.api_url[0].type == "String"
    error_message = "The API URL is not a secret and should be a plain String parameter."
  }
}

run "api_key_parameter" {
  command = apply

  variables {
    ssm_parameter_name_api_key = "/test/api-key"
  }

  assert {
    condition     = length(aws_ssm_parameter.api_key) == 1
    error_message = "Naming the parameter should create it."
  }

  assert {
    condition     = aws_ssm_parameter.api_key[0].type == "SecureString"
    error_message = "The API key must be stored as a SecureString."
  }
}

run "api_key_parameter_skipped_when_key_disabled" {
  command = apply

  variables {
    api_key_enabled            = false
    ssm_parameter_name_api_key = "/test/api-key"
  }

  assert {
    condition     = length(aws_ssm_parameter.api_key) == 0
    error_message = "There is no key to store when the API key is disabled, so the parameter must not be created."
  }
}

run "empty_parameter_name_is_treated_as_unset" {
  command = apply

  variables {
    ssm_parameter_name_api_url = ""
  }

  assert {
    condition     = length(aws_ssm_parameter.api_url) == 0
    error_message = "An empty name must be treated the same as null."
  }
}

run "invoke_command_falls_back_to_the_literal_url" {
  command = apply

  assert {
    condition     = !strcontains(output.test_cmd.invoke, "get-parameter")
    error_message = "With no SSM parameters the invoke command must not try to read one."
  }

  assert {
    condition     = strcontains(output.test_cmd.invoke, "API_URL=\"")
    error_message = "With no SSM parameters the invoke command must use the literal URL."
  }
}

run "invoke_command_reads_the_parameter_when_present" {
  command = apply

  variables {
    ssm_parameter_name_api_url = "/test/api-url"
  }

  assert {
    condition     = strcontains(output.test_cmd.invoke, "get-parameter")
    error_message = "With the parameter created the invoke command should read it."
  }
}

run "tags_reach_every_taggable_resource" {
  command = apply

  variables {
    tags                       = { Owner = "platform" }
    ssm_parameter_name_api_url = "/test/api-url"
    ssm_parameter_name_api_key = "/test/api-key"
  }

  assert {
    condition     = aws_sqs_queue.this.tags["Owner"] == "platform"
    error_message = "Tags must reach the main queue."
  }

  assert {
    condition     = aws_sqs_queue.dlq.tags["Owner"] == "platform"
    error_message = "Tags must reach the dead-letter queue."
  }

  assert {
    condition     = aws_iam_role.apigw_service.tags["Owner"] == "platform"
    error_message = "Tags must reach the integration role."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.tags["Owner"] == "platform"
    error_message = "Tags must reach the REST API."
  }

  assert {
    condition     = aws_api_gateway_stage.this.tags["Owner"] == "platform"
    error_message = "Tags must reach the stage."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags["Owner"] == "platform"
    error_message = "Tags must reach the log group."
  }

  assert {
    condition     = aws_api_gateway_usage_plan.this[0].tags["Owner"] == "platform"
    error_message = "Tags must reach the usage plan."
  }

  assert {
    condition     = aws_api_gateway_api_key.this[0].tags["Owner"] == "platform"
    error_message = "Tags must reach the API key."
  }

  assert {
    condition     = aws_ssm_parameter.api_url[0].tags["Owner"] == "platform"
    error_message = "Tags must reach the API URL parameter."
  }

  assert {
    condition     = aws_ssm_parameter.api_key[0].tags["Owner"] == "platform"
    error_message = "Tags must reach the API key parameter."
  }
}

run "log_group_name_and_retention" {
  command = apply

  variables {
    api_name           = "coderbyte-webhook"
    log_retention_days = 30
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/apigateway/coderbyte-webhook"
    error_message = "The log group name should be the prefix plus the API name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "Log retention should be configurable."
  }
}
