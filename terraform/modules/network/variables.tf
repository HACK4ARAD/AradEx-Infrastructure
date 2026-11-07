variable "cidr" {
  description = "CIDR-ul VPC-ului."
  type        = string
  default     = "10.40.0.0/16"
}

variable "azs" {
  description = "Zonele folosite (fixe, ca planul să fie determinist)."
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b"]
}
