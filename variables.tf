variable "api_name" {
  type        = string
  description = "The API name in API Gateway"
  default     = "webhook"
}

variable "iam_role_name" {
  type        = string
  description = "The name of the IAM role for API Gateway"
  default     = "apigateway-webhook"
}

variable "api_title" {
  type        = string
  description = "The `info.title` value in the OpenAPI spec"
  default     = "webhook"
}

variable "api_path" {
  type        = string
  description = "(optional) The API path"
  default     = "/"
  validation {
    condition     = startswith(var.api_path, "/")
    error_message = "api_path must start with a /"
  }
}

variable "api_stage_name" {
  type        = string
  description = "The name of the API Gateway stage"
  default     = "default"
}

variable "api_usage_plan_name" {
  type        = string
  description = "The name of the API Gateway usage plan"
  default     = "default"
}

variable "api_key_name" {
  type        = string
  description = "The name of the API Gateway key"
  default     = "default"
}

variable "queue_name" {
  type        = string
  description = "The queue name"
  default     = "webhook"
}

variable "queue_visibility_timeout_seconds" {
  type        = number
  description = "(Optional) Visibility timeout for the queue (default: 30)"
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Log retention in days"
  default     = 90
}

variable "log_group_name_prefix" {
  type        = string
  description = "Name prefix for the created log group"
  default     = "/aws/apigateway/"

  validation {
    condition     = var.log_group_name_prefix == "" || (startswith(var.log_group_name_prefix, "/") && endswith(var.log_group_name_prefix, "/"))
    error_message = "The input variable `log_group_name_prefix` must start and end with a forward slash (`/`)."
  }
}

variable "log_group_kms_key_id" {
  type        = string
  description = "KMS key ID to use for log group encryption"
  default     = null
}

variable "ssm_parameter_kms_key_id" {
  type        = string
  description = "KMS key ID to use for SSM parameter encryption"
  default     = null
}

variable "ssm_parameter_name_api_key" {
  type        = string
  description = "The name of the SSM parameter to store the API key"
  default     = null
}

variable "ssm_parameter_name_api_url" {
  type        = string
  description = "The name of the SSM parameter to store the API URL"
  default     = null
}

variable "api_key_enabled" {
  type        = bool
  description = "Whether to enable API key for API Gateway"
  default     = true
}

variable "lambda_authorizer_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether to enable Lambda Autorizer for API Gateway.
    If enabled, `lambda_authorizer_openapi_security_scheme` must be set.
  EOT
}

variable "lambda_authorizer_openapi_security_scheme" {
  type        = string
  default     = ""
  description = <<-EOT
    A partial OpenAPI configuration for the Lambda Authorizer.
    This must be a valid JSON string representing a valid OpenAPI security scheme object.
    It will be placed under the `components.securitySchemes.lambda-authorizer`
    field in the OpenAPI spec.
    See:
    <https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-authorizer.html>
  EOT


  validation {
    condition     = var.lambda_authorizer_openapi_security_scheme == "" || (startswith(var.lambda_authorizer_openapi_security_scheme, "{") && endswith(chomp(var.lambda_authorizer_openapi_security_scheme), "}") && can(jsondecode(var.lambda_authorizer_openapi_security_scheme)))
    error_message = "The input variable `lambda_authorizer_openapi_security_scheme` must be a valid JSON object."
  }
}

variable "apigateway_method_parameters" {
  type        = string
  default     = ""
  description = <<-EOT
    A JSON array of API Gateway Method request parameters.
    Each element in the array must be a valid OpenAPI `parameter` object.
    See:
    <https://swagger.io/docs/specification/describing-parameters/>
  EOT

  validation {
    condition     = var.apigateway_method_parameters == "" || (startswith(var.apigateway_method_parameters, "[") && endswith(chomp(var.apigateway_method_parameters), "]") && can(jsondecode(var.apigateway_method_parameters)))
    error_message = "The input variable `apigateway_method_parameters` must be a valid JSON array."
  }
}

variable "apigateway_integration_request_parameters" {
  type        = string
  default     = "{}"
  description = <<-EOT
    A JSON object of API Gateway Integration request parameter mappings.
    These will be placed under the `x-amazon-apigateway-integration.requestParameters`
    field in the OpenAPI spec.
    See:
    <https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-integration-requestParameters.html>
  EOT

  validation {
    condition     = var.apigateway_integration_request_parameters == "" || (startswith(var.apigateway_integration_request_parameters, "{") && endswith(chomp(var.apigateway_integration_request_parameters), "}") && can(jsondecode(var.apigateway_integration_request_parameters)))
    error_message = "The input variable `apigateway_integration_request_parameters` must be a valid JSON object."
  }
}

variable "apigateway_request_templates" {
  type        = string
  default     = ""
  description = <<-EOT
    String to append to the API Gateway integration request templates value.
    If using a FIFO queue, this variable must contain a value similar to the following:
    `&MessageDeduplicationId=$context.requestId&MessageGroupId=$input.json('$.Example'))`
  EOT
}

variable "apigateway_logging_level" {
  type        = string
  description = "API Gateway method settings - logging_level"
  default     = "INFO"

  validation {
    condition     = contains(["OFF", "ERROR", "INFO"], var.apigateway_logging_level)
    error_message = "The logging level must be one of the following: OFF, ERROR, or INFO."
  }
}

variable "apigateway_metrics_enabled" {
  type        = bool
  description = "API Gateway method settings - metrics_enabled"
  default     = true
}

variable "apigateway_data_trace_enabled" {
  type        = bool
  description = "API Gateway method settings - data_trace_enabled"
  default     = false
}

variable "apigateway_caching_enabled" {
  type        = bool
  description = "API Gateway method settings - caching_enabled"
  default     = false
}

variable "fifo_queue" {
  type        = bool
  description = "Whether to use a FIFO queue"
  default     = false
}

variable "ddl_queue_name" {
  type        = string
  description = "Name for the dead-letter queue"
  default     = null
}

variable "ddl_max_receive_count" {
  type        = number
  description = "Number of times a consumer can receive a message from the main queue before it is moved to the dead-letter queue"
  default     = 1
}
