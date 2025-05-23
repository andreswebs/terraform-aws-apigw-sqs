data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
  dns_suffix = data.aws_partition.current.dns_suffix
}

locals {
  queue_name_norm = try(replace(var.queue_name, ".fifo", ""), var.queue_name)
  queue_name      = var.queue_name != null && var.queue_name != "" ? (var.fifo_queue ? "${local.queue_name_norm}.fifo" : local.queue_name_norm) : null
}

resource "aws_sqs_queue" "this" {
  name = local.queue_name

  fifo_queue = var.fifo_queue

  visibility_timeout_seconds = var.queue_visibility_timeout_seconds
}

locals {
  ddl_queue_name_norm = var.ddl_queue_name != null && var.ddl_queue_name != "" ? try(replace(var.ddl_queue_name, ".fifo", ""), var.ddl_queue_name) : (local.queue_name_norm != null && local.queue_name_norm != "" ? "${local.queue_name_norm}-ddl" : null)
  ddl_queue_name      = var.fifo_queue ? "${local.ddl_queue_name_norm}.fifo" : local.ddl_queue_name_norm
}

resource "aws_sqs_queue" "ddl" {
  name = local.ddl_queue_name

  fifo_queue = var.fifo_queue

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue",
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

resource "aws_sqs_queue_redrive_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ddl.arn
    maxReceiveCount     = var.ddl_max_receive_count
  })
}

data "aws_iam_policy_document" "apigw_service_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.${local.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "apigw_service" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.apigw_service_trust.json
}

data "aws_iam_policy_document" "apigw_permissions" {
  statement {
    actions = [
      "sqs:SendMessage",
      "sqs:SendMessageBatch",
    ]
    resources = [aws_sqs_queue.this.arn]
  }
}

resource "aws_iam_role_policy" "apigw_permissions" {
  name   = "apigateway-permissions"
  role   = aws_iam_role.apigw_service.id
  policy = data.aws_iam_policy_document.apigw_permissions.json
}

locals {
  apigateway_integration_uri_sqs = "arn:${local.partition}:apigateway:${local.region}:sqs:path/${local.account_id}/${aws_sqs_queue.this.name}"

  apigateway_integration_request_parameters_default = <<-EOT
    {
      "integration.request.header.Content-Type": "'application/x-www-form-urlencoded'"
    }
  EOT

  apigateway_integration_request_parameters = jsonencode(merge(
    jsondecode(local.apigateway_integration_request_parameters_default),
    jsondecode(var.apigateway_integration_request_parameters),
  ))

  openapi_spec = jsonencode(jsondecode(templatefile("${path.module}/tpl/openapi.spec.json.tftpl", {
    api_title                                 = var.api_title
    api_path                                  = var.api_path
    api_key_enabled                           = var.api_key_enabled
    apigateway_method_parameters              = var.apigateway_method_parameters
    apigateway_integration_request_parameters = local.apigateway_integration_request_parameters
    apigateway_integration_uri                = local.apigateway_integration_uri_sqs
    apigateway_integration_role_arn           = aws_iam_role.apigw_service.arn
    apigateway_request_templates              = var.apigateway_request_templates
    base_path                                 = "/${var.api_stage_name}"
    lambda_authorizer_enabled                 = var.lambda_authorizer_enabled
    lambda_authorizer_openapi_security_scheme = var.lambda_authorizer_openapi_security_scheme
  })))
}

resource "aws_api_gateway_rest_api" "this" {
  name = var.api_name
  body = local.openapi_spec
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode(aws_api_gateway_rest_api.this.body))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "${var.log_group_name_prefix}${var.api_name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.log_group_kms_key_id
}

data "aws_iam_policy_document" "apigw_access_logs" {
  statement {

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [aws_cloudwatch_log_group.this.arn]

    principals {
      type = "Service"
      identifiers = [
        "apigateway.${local.dns_suffix}",
        "delivery.logs.${local.dns_suffix}",
      ]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_api_gateway_rest_api.this.arn]
    }

  }
}

resource "aws_api_gateway_stage" "this" {
  depends_on = [aws_cloudwatch_log_group.this]

  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.api_stage_name

  xray_tracing_enabled = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.this.arn
    format = jsonencode({
      httpMethod     = "$context.httpMethod"
      ip             = "$context.identity.sourceIp"
      protocol       = "$context.protocol"
      requestId      = "$context.requestId"
      requestTime    = "$context.requestTime"
      responseLength = "$context.responseLength"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
    })
  }
}

resource "aws_api_gateway_method_settings" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = "*/*"

  settings {
    logging_level      = var.apigateway_logging_level
    metrics_enabled    = var.apigateway_metrics_enabled
    data_trace_enabled = var.apigateway_data_trace_enabled
  }
}

resource "aws_api_gateway_usage_plan" "this" {
  count = var.api_key_enabled ? 1 : 0
  name  = var.api_usage_plan_name

  api_stages {
    api_id = aws_api_gateway_rest_api.this.id
    stage  = aws_api_gateway_stage.this.stage_name
  }
}

resource "aws_api_gateway_api_key" "this" {
  count = var.api_key_enabled ? 1 : 0
  name  = var.api_key_name
}

resource "aws_api_gateway_usage_plan_key" "this" {
  count         = var.api_key_enabled ? 1 : 0
  usage_plan_id = aws_api_gateway_usage_plan.this[0].id
  key_id        = aws_api_gateway_api_key.this[0].id
  key_type      = "API_KEY"
}

resource "aws_ssm_parameter" "api_key" {
  count  = var.api_key_enabled ? 1 : 0
  name   = var.ssm_parameter_name_api_key
  key_id = var.ssm_parameter_kms_key_id
  type   = "SecureString"
  value  = aws_api_gateway_api_key.this[0].value
}

locals {
  api_url = replace("${aws_api_gateway_stage.this.invoke_url}${var.api_path}", "/\\/$/", "")
}

resource "aws_ssm_parameter" "api_url" {
  name  = var.ssm_parameter_name_api_url
  type  = "String"
  value = local.api_url
}
