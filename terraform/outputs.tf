# outputs.tf

output "vpc_id" {
  description = "생성된 PoC VPC ID"
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = aws_subnet.private[*].id
}

output "ec2_instance_ids" {
  description = "SSM 관리형 EC2 인스턴스 ID (Session Manager 접속/SendCommand 대상)"
  value       = aws_instance.poc[*].id
}

output "datadog_integration_role_arn" {
  description = "Datadog 통합 화면에 등록할 IAM Role ARN"
  value       = aws_iam_role.datadog_integration.arn
}

output "ec2_ssm_role_arn" {
  description = "EC2 인스턴스 프로파일에 연결된 SSM Role ARN"
  value       = aws_iam_role.ec2_ssm.arn
}

output "autoscaling_group_name" {
  description = "CPU Spike 자동조치 대상 ASG 이름 (생성된 경우)"
  value       = try(aws_autoscaling_group.poc[0].name, null)
}

output "ssm_vpc_endpoint_ids" {
  description = "SSM 통신용 Interface 엔드포인트 ID"
  value       = { for k, v in aws_vpc_endpoint.ssm : k => v.id }
}
