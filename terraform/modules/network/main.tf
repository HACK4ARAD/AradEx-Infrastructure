# VPC dedicat FĂRĂ NAT: subneturi publice (ALB-ul public, taskurile Fargate care ies prin IGW) și izolate (RDS).

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "aradex" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "aradex" }
}

resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = cidrsubnet(var.cidr, 8, count.index)
  map_public_ip_on_launch = true
  tags                    = { Name = "aradex-public-${var.azs[count.index]}" }
}

resource "aws_subnet" "isolated" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = var.azs[count.index]
  cidr_block              = cidrsubnet(var.cidr, 8, 10 + count.index)
  map_public_ip_on_launch = false
  tags                    = { Name = "aradex-isolated-${var.azs[count.index]}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "aradex-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Fără rute: subneturile izolate nu ies nicăieri în afara VPC-ului.
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "aradex-isolated" }
}

resource "aws_route_table_association" "isolated" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.isolated[count.index].id
  route_table_id = aws_route_table.isolated.id
}

# --- Security groups -------------------------------------------------------

resource "aws_security_group" "alb" {
  name        = "aradex-alb"
  description = "ALB public: doar HTTP si HTTPS"
  vpc_id      = aws_vpc.this.id

  # Descrierea nu se poate modifica în AWS fără a recrea grupul (iar recrearea l-ar șterge cât timp regulile
  # taskurilor încă trimit la el). Grupul existent are descrierea veche, din varianta cu CloudFront; o ignorăm.
  lifecycle {
    ignore_changes = [description]
  }
}

resource "aws_security_group" "task" {
  name        = "aradex-api-task"
  description = "API Fargate: doar din ALB"
  vpc_id      = aws_vpc.this.id
}

resource "aws_security_group" "web" {
  name        = "aradex-web-task"
  description = "PWA nginx Fargate: doar din ALB"
  vpc_id      = aws_vpc.this.id
}

resource "aws_security_group" "db" {
  name        = "aradex-db"
  description = "RDS Postgres: doar din API"
  vpc_id      = aws_vpc.this.id
}

# Singurele porturi deschise spre internet: 80 (redirect spre HTTPS) și 443.
resource "aws_vpc_security_group_ingress_rule" "alb_public" {
  for_each          = { http = 80, https = 443 }
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  description       = "internet ${each.key}"
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  description                  = "ALB to API"
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  description                  = "ALB to PWA"
}

resource "aws_vpc_security_group_ingress_rule" "db_from_task" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.task.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "API to Postgres"
}

# Ieșire liberă: taskul trebuie să ajungă la ECR, Secrets Manager, CloudWatch, Claude API, OSRM.
resource "aws_vpc_security_group_egress_rule" "all" {
  for_each          = { alb = aws_security_group.alb.id, task = aws_security_group.task.id, web = aws_security_group.web.id, db = aws_security_group.db.id }
  security_group_id = each.value
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "egress"
}
