# autoscaling.tf
# CPU Spike -> Datadog Workflow -> autoscaling:SetDesiredCapacity 자동조치
# 시나리오를 검증하기 위한 대상 ASG. enable_autoscaling_target=false 면 생성 안 함.

resource "aws_launch_template" "poc" {
  count         = var.enable_autoscaling_target ? 1 : 0
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  # ASG 노드도 chaos playground 앱을 실어서 스케일 아웃 후 신규 인스턴스에서도
  # 시나리오 유발 가능하게 한다. Launch Template 의 user_data 는 base64 필요.
  user_data = local.chaos_app_user_data != null ? base64encode(local.chaos_app_user_data) : null

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm.name
  }

  vpc_security_group_ids = [aws_security_group.instance.id]

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-asg-node"
      Role = "ssm-managed-poc"
    }
  }
}

resource "aws_autoscaling_group" "poc" {
  count               = var.enable_autoscaling_target ? 1 : 0
  name                = "${var.project_name}-asg"
  min_size            = 1
  max_size            = 4
  desired_capacity    = 1
  vpc_zone_identifier = aws_subnet.private[*].id

  launch_template {
    id      = aws_launch_template.poc[0].id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-node"
    propagate_at_launch = true
  }
}
