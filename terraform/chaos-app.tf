# chaos-app.tf
# EC2 부팅 시 자동 배포되는 Flask "chaos playground" 앱.
# 시나리오 #1(orphan) / #2(disk) / #3(memory) / #4(cpu) 를 실제로 유발할 수 있는
# HTTP 엔드포인트를 제공한다. Datadog 연결은 별개 라운드에서 처리한다.
#
# 필수 의존: 인터넷 아웃바운드 (NAT Gateway) — dnf/pip 설치에 필요.
# 관련 토글: var.enable_nat_gateway (network.tf)

locals {
  chaos_app_user_data = var.enable_chaos_app ? templatefile(
    "${path.module}/scripts/user_data.sh.tpl",
    {
      chaos_app_code = file("${path.module}/scripts/chaos-app.py")
      app_port       = var.chaos_app_port
    }
  ) : null
}
