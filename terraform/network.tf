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
  for_each = var.enable_ssm_endpoints ? toset(local.ssm_interface_endpoints) : toset([])

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

# -------------------------------------------------------------------
# NAT Gateway 경로 (선택)
# enable_nat_gateway=true 인 경우에만 IGW + public subnet + NAT 생성.
# PoC 비용 최소화를 위해 NAT 는 첫 번째 AZ 에 단일 배치.
# -------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  count  = var.enable_nat_gateway ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = var.enable_nat_gateway ? length(var.public_subnet_cidrs) : 0
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  count  = var.enable_nat_gateway ? 1 : 0
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route" "public_default" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count          = var.enable_nat_gateway ? length(aws_subnet.public) : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_eip" "nat" {
  count      = var.enable_nat_gateway ? 1 : 0
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

# 기존 private route table 에 NAT 향 default route 를 조건부로 추가.
# route table 자체는 재사용, 라우트만 별도 리소스로 분리.
resource "aws_route" "private_default" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}
