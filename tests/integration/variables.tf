variable "name_prefix" {
  description = <<-EOT
    Unique prefix for every name this fixture creates. `run.bash` derives one per
    run, because SQS refuses to reuse a deleted queue's name for 60 seconds and
    a re-run inside that window would otherwise fail.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{4,48}$", var.name_prefix))
    error_message = "name_prefix must be 4 to 48 characters of lowercase letters, digits and hyphens."
  }
}
