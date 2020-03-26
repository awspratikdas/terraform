variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type        = number
  default     = "80"
}
variable "elb_port" {
  description = "The port elb will use for client HTTP requests"
  type        = number
  default     = "80"
}