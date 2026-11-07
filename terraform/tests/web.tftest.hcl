mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::712710404828:role/mock" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:eu-north-1:712710404828:task-definition/aradex-web:1" }
  }
  override_resource {
    target = aws_ecr_repository.web
    values = { repository_url = "712710404828.dkr.ecr.eu-north-1.amazonaws.com/aradex-web" }
  }
}

variables {
  vpc_id            = "vpc-1"
  public_subnet_ids = ["subnet-pub-a", "subnet-pub-b"]
  web_sg_id         = "sg-web"
  cluster_arn       = "arn:aws:ecs:eu-north-1:712710404828:cluster/aradex"
  listener_arn      = "arn:aws:elasticloadbalancing:eu-north-1:712710404828:listener/app/aradex-api/0123456789abcdef/fedcba9876543210"
  target_group_arn  = "arn:aws:elasticloadbalancing:eu-north-1:712710404828:targetgroup/aradex-web/0123456789abcdef"
  desired_count     = 0
}

run "web" {
  command = apply
  module {
    source = "./modules/web"
  }

  assert {
    condition     = aws_ecr_repository.web.name == "aradex-web" && aws_ecr_repository.web.force_delete
    error_message = "ecr repo"
  }
  assert {
    condition = (
      aws_ecs_task_definition.web.family == "aradex-web" &&
      aws_ecs_task_definition.web.cpu == "256" && aws_ecs_task_definition.web.memory == "512" &&
      aws_ecs_task_definition.web.runtime_platform[0].cpu_architecture == "X86_64"
    )
    error_message = "small x86 nginx task"
  }
  assert {
    condition = (
      local.container.name == "web" &&
      local.container.portMappings[0].containerPort == 80 &&
      local.container.image == "712710404828.dkr.ecr.eu-north-1.amazonaws.com/aradex-web:latest"
    )
    error_message = "container web on port 80 from ecr"
  }
  assert {
    condition = (
      aws_ecs_service.web.name == "aradex-web" && aws_ecs_service.web.desired_count == 0 &&
      aws_ecs_service.web.cluster == var.cluster_arn &&
      aws_ecs_service.web.network_configuration[0].security_groups == toset(["sg-web"]) &&
      aws_ecs_service.web.network_configuration[0].assign_public_ip &&
      aws_ecs_service.web.deployment_circuit_breaker[0].rollback
    )
    error_message = "web service"
  }
  assert {
    condition     = one(aws_ecs_service.web.load_balancer).target_group_arn == var.target_group_arn && one(aws_ecs_service.web.load_balancer).container_port == 80
    error_message = "service registers in the web target group"
  }
  assert {
    condition     = aws_cloudwatch_log_group.web.name == "/aradex/web" && aws_cloudwatch_log_group.web.retention_in_days == 7
    error_message = "logs 7 days"
  }
  # Serviciul se creează după ce target group-ul e legat de listener-ul HTTPS (altfel CreateService pică).
  assert {
    condition     = terraform_data.listener.input == var.listener_arn
    error_message = "service waits for the listener"
  }
}
