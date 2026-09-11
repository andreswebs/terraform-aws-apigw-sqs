## Queue wiring: names, encryption, and the redrive relationship between the
## main queue and its dead-letter queue.

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

run "defaults" {
  command = apply

  assert {
    condition     = aws_sqs_queue.this.name == "webhook"
    error_message = "Main queue should take the default name."
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "webhook-dlq"
    error_message = "Dead-letter queue should be derived as <queue_name>-dlq."
  }

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled == true
    error_message = "Encryption at rest must be declared, not left to the AWS default."
  }

  assert {
    condition     = aws_sqs_queue.dlq.sqs_managed_sse_enabled == true
    error_message = "The dead-letter queue holds the same payloads and must be encrypted too."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_policy.this.redrive_policy).deadLetterTargetArn == aws_sqs_queue.dlq.arn
    error_message = "The main queue must redrive to the dead-letter queue this module creates."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_policy.this.redrive_policy).maxReceiveCount == 1
    error_message = "Default maxReceiveCount should be 1."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.dlq.redrive_allow_policy).redrivePermission == "byQueue"
    error_message = "The dead-letter queue must restrict which queues may redrive to it."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.dlq.redrive_allow_policy).sourceQueueArns == [aws_sqs_queue.this.arn]
    error_message = "Only the main queue may redrive to the dead-letter queue."
  }
}

run "max_receive_count_override" {
  command = apply

  variables {
    dlq_max_receive_count = 5
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_policy.this.redrive_policy).maxReceiveCount == 5
    error_message = "maxReceiveCount should follow dlq_max_receive_count."
  }
}

run "explicit_dlq_name" {
  command = apply

  variables {
    dlq_queue_name = "custom-dead-letter"
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "custom-dead-letter"
    error_message = "An explicit dlq_queue_name should win over the derived name."
  }
}

run "fifo" {
  command = apply

  variables {
    fifo_queue = true
  }

  assert {
    condition     = aws_sqs_queue.this.name == "webhook.fifo"
    error_message = "A FIFO main queue name must end in .fifo."
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "webhook-dlq.fifo"
    error_message = "A FIFO dead-letter queue name must end in .fifo."
  }
}

run "fifo_with_explicit_names_already_suffixed" {
  command = apply

  variables {
    fifo_queue     = true
    queue_name     = "given.fifo"
    dlq_queue_name = "given-dead.fifo"
  }

  assert {
    condition     = aws_sqs_queue.this.name == "given.fifo"
    error_message = "A name already carrying .fifo must not be double-suffixed."
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "given-dead.fifo"
    error_message = "A dead-letter name already carrying .fifo must not be double-suffixed."
  }
}

run "sse_can_be_disabled" {
  command = apply

  variables {
    sqs_managed_sse_enabled = false
  }

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled == false
    error_message = "sqs_managed_sse_enabled should be honoured when false."
  }

  assert {
    condition     = aws_sqs_queue.dlq.sqs_managed_sse_enabled == false
    error_message = "sqs_managed_sse_enabled should apply to the dead-letter queue too."
  }
}

run "visibility_timeout" {
  command = apply

  variables {
    queue_visibility_timeout_seconds = 300
  }

  assert {
    condition     = aws_sqs_queue.this.visibility_timeout_seconds == 300
    error_message = "Visibility timeout should be configurable."
  }
}
