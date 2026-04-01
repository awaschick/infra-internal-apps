variable "dependency" {
  description = "Placeholder value that can receive a value from a previous module, forcing terraform order of execution"
  default     = "foo"
}

output "dependency" {
  value = "foo"
}
