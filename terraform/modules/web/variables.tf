variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Subneturile în care rulează nginx (IP public doar pentru ieșire: ECR, CloudWatch)."
  type        = list(string)
}

variable "web_sg_id" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "listener_arn" {
  description = "Listener-ul HTTPS care trimite traficul spre target group-ul web; serviciul se creează după el."
  type        = string
}

variable "target_group_arn" {
  description = "Target group-ul web, creat de modulul api lângă ALB."
  type        = string
}

variable "desired_count" {
  description = "0 până există o imagine în ECR (primul deploy din AradEx-Frontend), apoi 1."
  type        = number
  default     = 0
}
