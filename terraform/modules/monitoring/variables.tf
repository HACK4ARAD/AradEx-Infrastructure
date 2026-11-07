variable "alert_email" {
  type = string
}

variable "api_desired_count" {
  description = "Alarma „0 taskuri sănătoase” are sens doar când serviciul ar trebui să ruleze."
  type        = number
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffix" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}
