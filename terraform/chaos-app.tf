# chaos-app.tf
# EC2 부팅 시 자동 배포되는 Flask "chaos playground" 앱.
# 시나리오 #1(orphan) / #2(disk) / #3(memory) / #4(cpu) 를 실제로 유발할 수 있는
# HTTP 엔드포인트를 제공한다. Datadog 연결은 별개 라운드에서 처리한다.
#
# 필수 의존: 인터넷 아웃바운드 (NAT Gateway) — dnf/pip 설치에 필요.
# 관련 토글: var.enable_nat_gateway (network.tf)

locals {
  # chaos-app.py 는 코멘트 포함 16KB 를 넘어 EC2 user_data 한도(16KB)를 위협.
  # gzip+base64 로 압축해 담고 부팅 시 gunzip 으로 풀어 사용한다.
  chaos_app_user_data = var.enable_chaos_app ? templatefile(
    "${path.module}/scripts/user_data.sh.tpl",
    {
      chaos_app_code_b64gz = base64gzip(file("${path.module}/scripts/chaos-app.py"))
      app_port             = var.chaos_app_port

      # Datadog Agent + APM 계측 파라미터
      dd_enabled = var.enable_datadog_agent
      dd_api_key = var.datadog_api_key
      dd_site    = var.datadog_site
      dd_service = var.dd_service
      dd_env     = var.dd_env
      dd_version = var.dd_version

      # 트래픽 제너레이터 파라미터
      tg_enabled  = var.enable_traffic_generator
      tg_base_rps = var.traffic_generator_base_rps
    }
  ) : null
}
