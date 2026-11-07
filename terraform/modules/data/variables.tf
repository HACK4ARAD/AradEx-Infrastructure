variable "isolated_subnet_ids" {
  description = "Subneturile izolate în care stă RDS."
  type        = list(string)
}

variable "db_sg_id" {
  description = "Security group-ul bazei de date (intrare doar din API)."
  type        = string
}
