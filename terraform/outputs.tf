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
  description = "Chaos playground 앱 엔드포인트. 프라이빗 서브넷이므로 SSM Session Manager 포트포워딩으로 접근 후 curl."
  value = var.enable_chaos_app ? {
    # 관찰용
    health = "GET  http://localhost:${var.chaos_app_port}/health"
    stats  = "GET  http://localhost:${var.chaos_app_port}/chaos/stats"
    # 정상 비즈니스 엔드포인트 (Bits Detection 학습 재료)
    api_products    = "GET  http://localhost:${var.chaos_app_port}/api/products"
    api_product_one = "GET  http://localhost:${var.chaos_app_port}/api/products/3"
    api_orders      = "GET  http://localhost:${var.chaos_app_port}/api/orders"
    api_order_one   = "GET  http://localhost:${var.chaos_app_port}/api/orders/1002"
    api_checkout    = "POST http://localhost:${var.chaos_app_port}/api/checkout"
    # 장애 주입 엔드포인트
    chaos_leak_memory = "POST http://localhost:${var.chaos_app_port}/chaos/leak-memory?mb=50"
    chaos_fork_orphan = "POST http://localhost:${var.chaos_app_port}/chaos/fork-orphan?count=5"
    chaos_fill_disk   = "POST http://localhost:${var.chaos_app_port}/chaos/fill-disk?mb=500"
    chaos_cpu_burn    = "POST http://localhost:${var.chaos_app_port}/chaos/cpu-burn?seconds=60&threads=2"
    chaos_reset       = "POST http://localhost:${var.chaos_app_port}/chaos/reset"
  } : null
}

output "datadog_agent_status" {
  description = "Datadog Agent 활성화 상태와 확인 방법"
  value = var.enable_datadog_agent ? {
    enabled       = true
    service       = var.dd_service
    env           = var.dd_env
    version       = var.dd_version
    site          = var.datadog_site
    check_command = "sudo datadog-agent status | head -50"
    } : {
    enabled       = false
    service       = null
    env           = null
    version       = null
    site          = null
    check_command = "enable_datadog_agent=true 로 재적용 필요"
  }
}

output "traffic_generator_status" {
  description = "트래픽 제너레이터 상태와 확인 방법"
  value = var.enable_traffic_generator ? {
    enabled          = true
    base_rps         = var.traffic_generator_base_rps
    check_command    = "sudo systemctl status chaos-traffic.service"
    tail_log_command = "sudo journalctl -u chaos-traffic.service -f"
  } : null
}

output "ssm_port_forward_command" {
  description = "chaos-app 로컬 접근용 SSM 포트포워딩 명령 (첫 번째 인스턴스 기준)"
  value = length(aws_instance.poc) > 0 ? format(
    "aws ssm start-session --target %s --document-name AWS-StartPortForwardingSession --parameters 'portNumber=[\"%d\"],localPortNumber=[\"%d\"]' --region %s",
    aws_instance.poc[0].id,
    var.chaos_app_port,
    var.chaos_app_port,
    var.region,
  ) : null
}
