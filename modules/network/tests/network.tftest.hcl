mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

variables {
  name = "test"
}

run "two_azs_no_nat_by_default" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "Expected two public and two private subnets."
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0
    error_message = "NAT Gateway must be off unless asked for."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.map_public_ip_on_launch == false])
    error_message = "Public subnets must not auto-assign public IPs."
  }

  assert {
    condition     = aws_subnet.private[0].cidr_block == "10.0.10.0/24" && aws_subnet.public[0].cidr_block == "10.0.0.0/24"
    error_message = "Subnet CIDRs do not follow the documented layout."
  }

  assert {
    condition     = aws_subnet.public[0].availability_zone != aws_subnet.public[1].availability_zone
    error_message = "Subnets must be in different AZs."
  }
}

run "nat_gateway_when_enabled" {
  command = plan

  variables {
    enable_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_route.private_nat) == 1
    error_message = "enable_nat_gateway should add one NAT Gateway and a default route."
  }
}

run "rejects_non_slash16" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/20"
  }

  expect_failures = [var.cidr_block]
}
