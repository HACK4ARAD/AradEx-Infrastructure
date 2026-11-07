mock_provider "aws" {}

run "network" {
  command = apply
  module {
    source = "./modules/network"
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.40.0.0/16" && aws_vpc.this.enable_dns_hostnames && aws_vpc.this.enable_dns_support
    error_message = "vpc cidr / dns"
  }
  assert {
    condition     = length(aws_subnet.public) == 2 && alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch])
    error_message = "2 public subnets with public ip"
  }
  assert {
    condition     = toset([for s in aws_subnet.public : s.availability_zone]) == toset(["eu-north-1a", "eu-north-1b"])
    error_message = "public subnets in fixed AZs"
  }
  assert {
    condition     = length(aws_subnet.isolated) == 2 && alltrue([for s in aws_subnet.isolated : !s.map_public_ip_on_launch])
    error_message = "2 isolated subnets"
  }
  assert {
    condition     = length(aws_route_table.isolated.route) == 0
    error_message = "isolated route table must have no routes (no NAT)"
  }
  assert {
    condition     = aws_route.public_internet.destination_cidr_block == "0.0.0.0/0" && aws_route.public_internet.gateway_id == aws_internet_gateway.this.id
    error_message = "public default route via IGW"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.alb_from_cloudfront.prefix_list_id == "pl-fab65393" && aws_vpc_security_group_ingress_rule.alb_from_cloudfront.from_port == 80 && aws_vpc_security_group_ingress_rule.alb_from_cloudfront.to_port == 80 && aws_vpc_security_group_ingress_rule.alb_from_cloudfront.security_group_id == aws_security_group.alb.id
    error_message = "alb ingress only from CloudFront prefix list on 80"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.task_from_alb.referenced_security_group_id == aws_security_group.alb.id && aws_vpc_security_group_ingress_rule.task_from_alb.from_port == 8080 && aws_vpc_security_group_ingress_rule.task_from_alb.security_group_id == aws_security_group.task.id
    error_message = "task ingress only from alb on 8080"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.db_from_task.referenced_security_group_id == aws_security_group.task.id && aws_vpc_security_group_ingress_rule.db_from_task.from_port == 5432 && aws_vpc_security_group_ingress_rule.db_from_task.security_group_id == aws_security_group.db.id
    error_message = "db ingress only from task on 5432"
  }
  assert {
    condition     = alltrue([for r in [aws_vpc_security_group_ingress_rule.alb_from_cloudfront, aws_vpc_security_group_ingress_rule.task_from_alb, aws_vpc_security_group_ingress_rule.db_from_task] : r.cidr_ipv4 == null])
    error_message = "no cidr-based ingress"
  }
  assert {
    condition     = length(output.public_subnet_ids) == 2 && length(output.isolated_subnet_ids) == 2
    error_message = "subnet outputs"
  }
}
