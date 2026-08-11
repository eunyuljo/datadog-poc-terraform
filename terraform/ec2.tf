# ec2.tf
# SSM Agent가 기본 내장된 공식 AMI(Amazon Linux 2023)로 EC2 프로비저닝.
# 프라이빗 서브넷에 배치되며, 인스턴스 프로파일로 SSM 관리형 노드에 등록된다.

# 최신 Amazon Linux 2023 AMI 조회
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_instance" "poc" {
  count                  = var.instance_count
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private[count.index % length(aws_subnet.private)].id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  # enable_chaos_app=true 인 경우 chaos-app.tf 의 로컬이 렌더링한 스크립트를 삽입.
  # AL2023 은 SSM Agent 내장이라 별도 설치 불필요.
  user_data = local.chaos_app_user_data

  metadata_options {
    http_tokens   = "required" # IMDSv2 강제
    http_endpoint = "enabled"
  }

  tags = {
    Name = "${var.project_name}-node-${count.index + 1}"
    Role = "ssm-managed-poc"
  }
}
