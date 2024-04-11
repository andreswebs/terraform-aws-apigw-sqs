variable "api_name" {
  type        = string
  description = "The API name in API Gateway"
  default     = "webhook"
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

variable "log_retention_days" {
  type        = number
  description = "Log retention in days"
  default     = 30
}

variable "ssm_parameter_name_api_key" {
  type        = string
  description = "The name of the SSM parameter to store the API key"
  default     = null
}

variable "ssm_parameter_name_url" {
  type        = string
  description = "The name of the SSM parameter to store the webhook URL"
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
  description = <<-EOT
    A partial OpenAPI configuration for the Lambda Authorizer.
    This must be a valid JSON string representing a valid OpenAPI security scheme object.
    It will be placed under the `components.securitySchemes.lambda-authorizer`
    field in the OpenAPI spec.
    See:
    <https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-swagger-extensions-authorizer.html>
  EOT

  default = ""

  validation {
    condition     = var.lambda_authorizer_openapi_security_scheme == "" || (startswith(var.lambda_authorizer_openapi_security_scheme, "{") && endswith(chomp(var.lambda_authorizer_openapi_security_scheme), "}") && can(jsondecode(var.lambda_authorizer_openapi_security_scheme)))
    error_message = "The input variable `lambda_authorizer_openapi_security_scheme` must be a valid JSON string."
  }
}
