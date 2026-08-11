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
  default     = "t3.small"
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
