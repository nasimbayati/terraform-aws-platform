output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "app_security_group_id" {
  value = aws_security_group.app.id
}

output "s3_endpoint_id" {
  description = "Gateway endpoint ID. The storage module uses it to restrict bucket access to this VPC."
  value       = aws_vpc_endpoint.s3.id
}
