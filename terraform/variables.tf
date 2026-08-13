# variables.tf

variable "region" {
  description = "배포 리전"
  type        = string
  default     = "ap-northeast-2" # 서울
}

variable "project_name" {
  description = "리소스 네이밍 및 태깅 prefix"
  type        = string
  default     = "ddog-poc"
}

variable "owner" {
  description = "리소스 소유자 태그 (담당자 식별용)"
  type        = string
  default     = "megazone-msp"
}

# -------------------------------------------------------------------
# 네트워크
# -------------------------------------------------------------------
variable "vpc_cidr" {
  description = "PoC VPC의 CIDR 블록"
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록 (AZ 수만큼)"
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "azs" {
  description = "사용할 가용영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

# -------------------------------------------------------------------
# EC2
# -------------------------------------------------------------------
variable "instance_type" {
  description = "PoC EC2 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "instance_count" {
  description = "SSM 관리형 노드로 등록할 EC2 대수"
  type        = number
  default     = 1
}

# -------------------------------------------------------------------
# Datadog 연동 IAM Role
# -------------------------------------------------------------------
variable "datadog_aws_account_id" {
  description = "Datadog가 AssumeRole에 사용하는 AWS 계정 ID (기본: Datadog 공식 계정)"
  type        = string
  default     = "464622532012" # Datadog 공식 통합 계정
}

variable "datadog_external_id" {
  description = "Datadog 통합 설정 화면에서 발급되는 External ID. PoC 시작 시 실제 값으로 교체"
  type        = string
  default     = "REPLACE_WITH_DATADOG_EXTERNAL_ID"
}

# -------------------------------------------------------------------
# 자동조치 시나리오 대상 (Workflow Automation 검증용)
# -------------------------------------------------------------------
variable "enable_autoscaling_target" {
  description = "CPU Spike -> ASG SetDesiredCapacity 시나리오 검증용 ASG 생성 여부"
  type        = bool
  default     = true
}

# -------------------------------------------------------------------
# 아웃바운드 경로 토글
# -------------------------------------------------------------------
# NAT Gateway 와 SSM VPC 엔드포인트는 SSM 통신 관점에서 상호 대체재.
# 세 조합(NAT-only / Endpoint-only / Both) 모두 지원.
variable "enable_nat_gateway" {
  description = "NAT Gateway + IGW + public subnet 생성 여부. Datadog Agent 등 인터넷 아웃바운드가 필요하면 true"
  type        = bool
  default     = false
}

variable "enable_ssm_endpoints" {
  description = "SSM Interface 엔드포인트 3종 생성 여부. NAT만으로도 SSM 통신은 가능하지만 보안상 백본 유지를 원하면 true"
  type        = bool
  default     = true
}

variable "public_subnet_cidrs" {
  description = "NAT Gateway 배치용 퍼블릭 서브넷 CIDR. enable_nat_gateway=true 일 때만 사용"
  type        = list(string)
  default     = ["10.20.101.0/24", "10.20.102.0/24"]
}

# -------------------------------------------------------------------
# Chaos playground 앱 (EC2 자동 배포)
# -------------------------------------------------------------------
# 시나리오 #1 orphan / #2 disk / #3 memory / #4 cpu 를 유발할 수 있는
# Flask 앱을 user_data 로 자동 설치·기동한다.
# NOTE: pip 설치가 필요해 인터넷 아웃바운드(enable_nat_gateway=true) 가 요구된다.
variable "enable_chaos_app" {
  description = "EC2 부팅 시 chaos playground Flask 앱 자동 배포 여부"
  type        = bool
  default     = true
}

variable "chaos_app_port" {
  description = "Chaos playground 앱 리슨 포트 (Session Manager 포트포워딩 대상)"
  type        = number
  default     = 8080
}

# -------------------------------------------------------------------
# Datadog Agent + APM 계측
# -------------------------------------------------------------------
# Bits Detection 은 APM 데이터를 재료로 삼는다. 따라서 chaos-app 을
# Datadog "서비스" 로 인식시키려면 Agent 설치 + ddtrace-run 계측이 필요하다.
#
# API key 미확보 시(예: Datadog 회신 대기 중) 는 enable_datadog_agent=false
# 로 두면 인프라·앱은 그대로 돌아가고 Agent 만 빠진다.
variable "enable_datadog_agent" {
  description = "EC2 부팅 시 Datadog Agent 설치 + chaos-app APM 계측 활성화 여부. false 면 앱만 실행."
  type        = bool
  default     = false
}

variable "datadog_api_key" {
  description = "Datadog API Key. enable_datadog_agent=true 일 때만 사용. terraform.tfvars 에 넣고 커밋 금지."
  type        = string
  default     = ""
  sensitive   = true
}

variable "datadog_site" {
  description = "Datadog 사이트 (예: datadoghq.com, us5.datadoghq.com, datadoghq.eu, ap1.datadoghq.com)"
  type        = string
  default     = "datadoghq.com"
}

variable "dd_service" {
  description = "APM 서비스 이름. Bits Detection 이 이 이름으로 서비스를 식별."
  type        = string
  default     = "chaos-app"
}

variable "dd_env" {
  description = "APM 환경 태그 (Unified Service Tagging)"
  type        = string
  default     = "poc"
}

variable "dd_version" {
  description = "APM 버전 태그 (Unified Service Tagging). 배포 트래킹에 사용."
  type        = string
  default     = "0.1.0"
}

# -------------------------------------------------------------------
# 트래픽 제너레이터 (Bits Detection 학습용 정상 트래픽)
# -------------------------------------------------------------------
# chaos-app 과 같은 EC2 에 systemd 유닛으로 배포. localhost:8080/api/* 를
# 시간대별 다른 빈도로 호출해 realistic 한 baseline 트래픽 프로파일을 만든다.
variable "enable_traffic_generator" {
  description = "chaos-app 의 /api/* 엔드포인트를 지속 호출하는 트래픽 제너레이터 활성화 여부"
  type        = bool
  default     = true
}

variable "traffic_generator_base_rps" {
  description = "트래픽 제너레이터의 기준 요청/초 (야간 최저치). 주간엔 최대 4배까지 상승."
  type        = number
  default     = 2
}
