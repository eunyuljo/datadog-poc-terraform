# iam_datadog.tf
# [역할 2] Datadog 연동용 IAM Role
# Datadog(Workflow Automation / BIO)이 AWS API를 호출해 자동조치를 수행할 때
# AssumeRole 로 수임하는 크로스계정 역할. External ID 로 confused-deputy 방어.

data "aws_iam_policy_document" "datadog_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.datadog_aws_account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.datadog_external_id]
    }
  }
}

resource "aws_iam_role" "datadog_integration" {
  name               = "${var.project_name}-datadog-integration-role"
  assume_role_policy = data.aws_iam_policy_document.datadog_assume.json

  tags = {
    Name = "${var.project_name}-datadog-integration-role"
  }
}

# 자동조치 시나리오별 최소 권한
# 주의: PoC 검증용 최소권한 초안. 운영 적용 시 Resource 를 특정 ARN 으로 좁힐 것.
data "aws_iam_policy_document" "datadog_actions" {

  # (1) 호스트 내부 스크립트 실행: SSM SendCommand
  statement {
    sid    = "SSMRunCommand"
    effect = "Allow"
    actions = [
      "ssm:SendCommand",
      "ssm:GetCommandInvocation",
      "ssm:ListCommandInvocations",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"]
  }

  # (2) CPU Spike 대응: ASG SetDesiredCapacity
  statement {
    sid    = "AutoScalingScale"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeScalingActivities",
    ]
    resources = ["*"]
  }

  # (3) Slow Query 대응: RDS 스케일업
  statement {
    sid    = "RDSScaleUp"
    effect = "Allow"
    actions = [
      "rds:ModifyDBInstance",
      "rds:DescribeDBInstances",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "datadog_actions" {
  name   = "${var.project_name}-datadog-actions"
  role   = aws_iam_role.datadog_integration.id
  policy = data.aws_iam_policy_document.datadog_actions.json
}
