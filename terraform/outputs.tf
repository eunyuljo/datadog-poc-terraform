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
  description = "SSM 통신용 Interface 엔드포인트 ID (enable_ssm_endpoints=false 시 빈 map)"
  value       = { for k, v in aws_vpc_endpoint.ssm : k => v.id }
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (enable_nat_gateway=true 시)"
  value       = try(aws_nat_gateway.this[0].id, null)
}

output "internet_gateway_id" {
  description = "Internet Gateway ID (enable_nat_gateway=true 시)"
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "public_subnet_ids" {
  description = "NAT 배치용 퍼블릭 서브넷 ID 목록 (enable_nat_gateway=true 시)"
  value       = aws_subnet.public[*].id
}

output "chaos_app_endpoints" {
  description = "Chaos playground 앱 엔드포인트 예시. 프라이빗 서브넷이므로 SSM Session Manager 포트포워딩으로 접근 후 curl. (포트는 var.chaos_app_port)"
  value = var.enable_chaos_app ? {
    health      = "GET  http://localhost:${var.chaos_app_port}/health"
    stats       = "GET  http://localhost:${var.chaos_app_port}/chaos/stats"
    leak_memory = "POST http://localhost:${var.chaos_app_port}/chaos/leak-memory?mb=50"
    fork_orphan = "POST http://localhost:${var.chaos_app_port}/chaos/fork-orphan?count=5"
    fill_disk   = "POST http://localhost:${var.chaos_app_port}/chaos/fill-disk?mb=500"
    cpu_burn    = "POST http://localhost:${var.chaos_app_port}/chaos/cpu-burn?seconds=60&threads=2"
    reset       = "POST http://localhost:${var.chaos_app_port}/chaos/reset"
  } : null
}
