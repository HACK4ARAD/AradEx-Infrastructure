output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "isolated_subnet_ids" {
  value = aws_subnet.isolated[*].id
}

output "alb_sg_id" {
  value = aws_security_group.alb.id
}

output "task_sg_id" {
  value = aws_security_group.task.id
}

output "web_sg_id" {
  value = aws_security_group.web.id
}

output "db_sg_id" {
  value = aws_security_group.db.id
}
