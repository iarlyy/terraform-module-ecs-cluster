variable "name" {}
variable "key_name" {}
variable "vpc_id" {}

variable "subnet_ids" {
  type = "list"
}

# ECS AMIs - https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html - eu-central-1
variable "ami" {
  default = "ami-0291ba887ba0d515f"
}

variable "instance_type" {
  default = "t2.medium"
}

variable "desired_capacity" {
  default = 1
}

variable "min_capacity" {
  default = 1
}

variable "max_capacity" {
  default = 1
}

variable "associate_iam_policies" {
  type = "list"

  default = [
    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
    "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess",
  ]
}

variable "security_group_ids" {
  type    = "list"
  default = []
}

variable "associate_public_ip_address" {
  default = true
}
