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
  default     = "/webhook/api-key"
}

variable "ssm_parameter_name_url" {
  type        = string
  description = "The name of the SSM parameter to store the webhook URL"
  default     = "/webhook/url"
}

variable "api_key_enabled" {
  type        = bool
  description = "Whether to enable API key"
  default     = true
}
