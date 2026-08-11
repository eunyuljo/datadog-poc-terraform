# iam_instance.tf
# [역할 1] EC2 인스턴스 프로파일
# EC2가 SSM 관리형 노드로 등록되기 위해 AmazonSSMManagedInstanceCore 를 수임.

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name               = "${var.project_name}-ec2-ssm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json

  tags = {
    Name = "${var.project_name}-ec2-ssm-role"
  }
}

# SSM 관리형 노드 등록을 위한 AWS 관리형 정책
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}
