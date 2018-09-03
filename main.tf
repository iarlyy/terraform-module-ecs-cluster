data "template_file" "ecs_user_data_main" {
  template = "${file("${path.module}/files/ecs_user_data.sh")}"

  vars {
    cluster_name = "${var.name}"
  }
}

resource "aws_security_group" "ecs" {
  name   = "ECS-${var.name}"
  vpc_id = "${var.vpc_id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name          = "ECS-${var.name}"
    Cluster       = "ECS-${var.name}"
    InstanceGroup = "ECS-${var.name}"
    Terraform     = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM
resource "aws_iam_role" "ecs_cluster" {
  name        = "ECSClusterRole-${var.name}"
  description = "Managed by Terraform"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ec2.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_cluster" {
  count      = "${length(var.associate_iam_policies)}"
  role       = "${aws_iam_role.ecs_cluster.name}"
  policy_arn = "${element(var.associate_iam_policies, count.index)}"
}

resource "aws_iam_instance_profile" "ecs_cluster" {
  name = "ECSClusterInstanceProfile-${var.name}"
  path = "/"
  role = "${aws_iam_role.ecs_cluster.name}"
}

# ECS Cluster
resource "aws_launch_configuration" "ecs_launch_conf" {
  name_prefix                 = "ECS-${var.name}"
  image_id                    = "${var.ami}"
  instance_type               = "${var.instance_type}"
  security_groups             = ["${concat(list(aws_security_group.ecs.id), var.security_group_ids)}"]
  associate_public_ip_address = "${var.associate_public_ip_address}"
  user_data                   = "${data.template_file.ecs_user_data_main.rendered}"
  iam_instance_profile        = "${aws_iam_instance_profile.ecs_cluster.arn}"
  key_name                    = "${var.key_name}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                 = "ECS-${var.name}"
  desired_capacity     = "${var.desired_capacity}"
  min_size             = "${var.min_capacity}"
  max_size             = "${var.max_capacity}"
  launch_configuration = "${aws_launch_configuration.ecs_launch_conf.name}"
  force_delete         = true
  vpc_zone_identifier  = ["${var.subnet_ids}"]

  lifecycle {
    create_before_destroy = true
  }

  tags = ["${concat(
    list(
      map("key", "Name", "value", "ECS-${var.name}", "propagate_at_launch", true),
      map("key", "Cluster", "value", "${var.name}", "propagate_at_launch", true),
      map("key", "InstanceGroup", "value", "ECS-${var.name}", "propagate_at_launch", true),
      map("key", "Terraform", "value", true, "propagate_at_launch", true)
      )
    )}"]
}

resource "aws_autoscaling_policy" "ecs_asg_scale_up" {
  name                   = "scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 60
  autoscaling_group_name = "${aws_autoscaling_group.ecs_asg.name}"
}

resource "aws_autoscaling_policy" "ecs_asg_scale_down" {
  name                   = "scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 900
  autoscaling_group_name = "${aws_autoscaling_group.ecs_asg.name}"
}

resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.name}"
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "ECS_Cluster-${var.name}_CPUUsage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Maximum"
  threshold           = "70"
  alarm_description   = "Managed by Terraform"
  alarm_actions       = ["${aws_autoscaling_policy.ecs_asg_scale_up.arn}"]

  dimensions {
    ClusterName = "${var.name}"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_mem" {
  alarm_name          = "ECS_Cluster-${var.name}_HighMEMUsage"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "70"
  alarm_description   = "Managed by Terraform"
  alarm_actions       = ["${aws_autoscaling_policy.ecs_asg_scale_up.arn}"]

  dimensions {
    ClusterName = "${var.name}"
  }
}

resource "aws_cloudwatch_metric_alarm" "high_mem_reservation" {
  alarm_name          = "ECS_Cluster-${var.name}_MEMReservation"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "3"
  metric_name         = "MemoryReservation"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "85"
  alarm_description   = "Managed by Terraform"
  alarm_actions       = ["${aws_autoscaling_policy.ecs_asg_scale_up.arn}"]

  dimensions {
    ClusterName = "${var.name}"
  }
}

resource "aws_cloudwatch_metric_alarm" "low_mem_usage" {
  alarm_name          = "ECS_Cluster-${var.name}_LowMEMUsage"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = "900"
  statistic           = "Average"
  threshold           = "20"
  alarm_description   = "Managed by Terraform"
  alarm_actions       = ["${aws_autoscaling_policy.ecs_asg_scale_down.arn}"]

  dimensions {
    ClusterName = "${var.name}"
  }
}
