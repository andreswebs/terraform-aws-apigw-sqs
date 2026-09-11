## Every variable validation gets a run that trips it. A validation nothing
## exercises is a validation that can rot: two of these were unreachable in
## practice before the module had a test suite at all.

## The policy document has to be mocked to something valid even here: a run
## with expect_failures still evaluates the rest of the configuration, and a
## generated string would fail the provider's JSON check and mask the
## validation error the run is asserting.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

run "api_path_must_start_with_a_slash" {
  command = plan

  variables {
    api_path = "coderbyte"
  }

  expect_failures = [var.api_path]
}

run "log_group_prefix_must_start_and_end_with_a_slash" {
  command = plan

  variables {
    log_group_name_prefix = "aws/apigateway"
  }

  expect_failures = [var.log_group_name_prefix]
}

run "logging_level_must_be_one_of_three" {
  command = plan

  variables {
    apigateway_logging_level = "TRACE"
  }

  expect_failures = [var.apigateway_logging_level]
}

run "method_parameters_must_be_a_json_array" {
  command = plan

  variables {
    apigateway_method_parameters = "not json"
  }

  expect_failures = [var.apigateway_method_parameters]
}

run "integration_request_parameters_must_be_a_json_object" {
  command = plan

  variables {
    apigateway_integration_request_parameters = "not json"
  }

  expect_failures = [var.apigateway_integration_request_parameters]
}

run "authorizer_scheme_must_be_a_json_object" {
  command = plan

  variables {
    lambda_authorizer_openapi_security_scheme = "not json"
  }

  expect_failures = [var.lambda_authorizer_openapi_security_scheme]
}

run "authorizer_cannot_be_enabled_without_a_scheme" {
  command = plan

  variables {
    lambda_authorizer_enabled = true
  }

  expect_failures = [var.lambda_authorizer_openapi_security_scheme]
}
