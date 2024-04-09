data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_sqs_queue" "this" {
  name = var.queue_name
}

data "aws_iam_policy_document" "apigw_service_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["apigateway.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "apigw_service" {
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
  apigw_sqs_integration_uri = "arn:${local.partition}:apigateway:${local.region}:sqs:path/${local.account_id}/${aws_sqs_queue.this.name}"
  openapi_spec = templatefile("${path.module}/tpl/openapi.spec.json.tftpl", {
    api_title                       = var.api_title
    base_path                       = "/${var.api_stage_name}"
    api_path                        = var.api_path
    apigateway_integration_uri      = local.apigw_sqs_integration_uri
    apigateway_integration_role_arn = aws_iam_role.apigw_service.arn
    api_key_enabled                 = var.api_key_enabled
  })
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
  name              = "/aws/apigateway/${var.api_name}"
  retention_in_days = var.log_retention_days
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
        "apigateway.amazonaws.com",
        "delivery.logs.amazonaws.com",
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
    metrics_enabled = true
    logging_level   = "INFO"
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
  count = var.api_key_enabled ? 1 : 0
  name  = var.ssm_parameter_name_api_key
  type  = "SecureString"
  value = aws_api_gateway_api_key.this[0].value
}

resource "aws_ssm_parameter" "url" {
  name  = var.ssm_parameter_name_url
  type  = "String"
  value = "${aws_api_gateway_stage.this.invoke_url}${var.api_path}"
}
