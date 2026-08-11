# network.tf
# 프라이빗 서브넷 + VPC 엔드포인트(SSM) 구성.
# NAT/IGW 없이 SSM Agent가 Interface 엔드포인트를 통해 SSM 컨트롤 플레인과 통신.

# -------------------------------------------------------------------
# VPC
# -------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true # 엔드포인트 Private DNS 사용에 필수

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# -------------------------------------------------------------------
# 프라이빗 서브넷 (AZ별)
# -------------------------------------------------------------------
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = {
    Name = "${var.project_name}-private-${var.azs[count.index]}"
    Tier = "private"
  }
}

# -------------------------------------------------------------------
# 라우팅 테이블 (프라이빗 - 외부 경로 없음)
# 엔드포인트 방식이므로 0.0.0.0/0 default route 를 두지 않는다.
# -------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# -------------------------------------------------------------------
# 보안그룹: EC2 인스턴스용
# 아웃바운드 전체 허용(엔드포인트 SG로 443 도달). 인바운드 없음.
# -------------------------------------------------------------------
resource "aws_security_group" "instance" {
  name        = "${var.project_name}-instance-sg"
  description = "SSM managed EC2 instances - no inbound, egress to endpoints"
  vpc_id      = aws_vpc.this.id

  egress {
    description = "All outbound (reaches VPC endpoints for SSM)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-instance-sg"
  }
}

# -------------------------------------------------------------------
# 보안그룹: VPC Interface 엔드포인트용
# VPC 내부에서의 HTTPS(443) 인바운드 허용.
# -------------------------------------------------------------------
resource "aws_security_group" "endpoint" {
  name        = "${var.project_name}-vpce-sg"
  description = "Allow HTTPS from VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from within VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-vpce-sg"
  }
}

# -------------------------------------------------------------------
# SSM 통신에 필요한 3개 Interface 엔드포인트
#   - ssm          : SSM 서비스 API
#   - ssmmessages  : Session Manager / 명령 채널
#   - ec2messages  : EC2 <-> SSM 메시지 채널
# -------------------------------------------------------------------
locals {
  ssm_interface_endpoints = [
    "ssm",
    "ssmmessages",
    "ec2messages",
  ]
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(local.ssm_interface_endpoints)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-vpce-${each.value}"
  }
}
