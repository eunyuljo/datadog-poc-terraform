---
tags: [datadog, poc, terraform, ssm, workflow-automation]
type: playbook
status: in-progress
meeting: 2026-08-13 09:00
created: 2026-08-11
owner: megazone-msp
aliases:
  - "Datadog PoC — 진행 방향 및 Terraform 준비"
---

# Datadog PoC — 진행 방향 및 Terraform 준비

> [!info] 한 줄 요약
> 메가존클라우드 ↔ Datadog 제품팀 간 **AI 기반 모니터링·자율운영 솔루션(Bits / BIO / Workflow Automation)** 도입 PoC. **8/13(목) 09:00 데모 미팅** 확정. 이 노트는 (1) 메일 스레드 진행 방향, (2) 검증에 필요한 Terraform 인프라, (3) 미팅 전 액션아이템을 정리한다.

---

## 1. 전체 진행 방향

현재는 **PoC(개념 증명) 준비 단계**로, 메가존이 제시한 시나리오를 바탕으로 Datadog 제품팀의 기능 담당 PM들과 기술 검증 범위를 조율 중이다. 8/13 데모에서 최초 기능 확인 후 검증 범위를 확정한다.

### 솔루션별 검증 계획

| 솔루션 | 성격 | 8/13 검증 내용 | 전제 조건 |
|---|---|---|---|
| **Bits Detection** | 핵심 리소스 이상 탐지 | 최초 데모 확인 | **APM 설정 필수** |
| **BIO** (Bits Infrastructure Operations) | 인프라 자율 운영 | 1차 프리뷰는 **ECS Fargate** 중심. 메가존 관심사인 **EC2** 시나리오를 제품팀도 관심 있어 깊이 논의 | EC2는 추후 지원 예정 |
| **Workflow Automation** | 운영 자동화 | **즉시 테스트 가능**. 감지 → Slack 승인 요청 → Webhook 타 플랫폼 연동 검증 | 자동조치 대상 IAM/SSM 필요 |

> [!note] 관전 포인트
> BIO 1차 프리뷰는 **ECS Fargate**가 대상이지만, 메가존의 실제 페인은 **EC2 환경**이다. 제품팀이 이 EC2 시나리오에 관심이 크므로, 8/13 미팅은 "EC2 자동조치 시나리오를 어떻게 구성하는 것이 적절한가"를 구체적 그림으로 제시할수록 유리하다.

---

## 2. Terraform으로 준비할 인프라 요소

인프라 자동조치 시나리오 검증의 핵심은 **AWS Systems Manager(SSM) 기반 환경**을 IaC로 완결성 있게 구성하는 것이다. 아래는 이번 저장소(`terraform/`)에 구현된 구성이며, **서울 리전(ap-northeast-2) / 프라이빗 서브넷 + VPC 엔드포인트 / EC2·SSM 우선** 방침으로 작성했다.

### ① EC2 + SSM Agent — `ec2.tf`

- **공식 AMI 사용**: Amazon Linux 2023(SSM Agent 기본 내장)을 `data.aws_ami`로 조회해 프로비저닝. AL2 / Ubuntu 16.04+ 도 동일하게 내장.
- **UserData(선택)**: 커스텀 AMI를 쓸 경우 `user_data`에 SSM Agent 설치·기동 스크립트를 포함 — 코드에 주석 예시로 남겨둠.
- IMDSv2 강제(`http_tokens = required`).

### ② IAM — **역할 2종 분리** (가장 중요)

> [!important] 두 역할을 반드시 분리한다
> 하나는 "EC2가 SSM에 등록되기 위한" 역할이고, 다른 하나는 "Datadog이 우리 계정에서 자동조치를 하기 위한" 크로스계정 역할이다. 성격과 신뢰 주체(Principal)가 완전히 다르다.

**역할 1 — EC2 인스턴스 프로파일** (`iam_instance.tf`)
- EC2를 SSM **관리형 노드**로 등록하기 위해 필수.
- AWS 관리형 정책 `AmazonSSMManagedInstanceCore`를 attach → `aws_iam_instance_profile`로 EC2에 연결.

**역할 2 — Datadog 연동용 IAM Role** (`iam_datadog.tf`)
- Datadog(Workflow/BIO)이 AWS API를 호출해 자동조치(스케일링·명령 전송 등)를 수행할 때 **AssumeRole**로 수임.
- `Principal = Datadog 공식 계정(464622532012)`, `Condition = sts:ExternalId` 로 confused-deputy 방어.
- 시나리오별 최소 권한:
  - `ssm:SendCommand`, `ssm:GetCommandInvocation` — 호스트 내부 스크립트 실행
  - `autoscaling:SetDesiredCapacity`, `autoscaling:DescribeAutoScalingGroups` — **CPU Spike → ASG 스케일**
  - `rds:ModifyDBInstance`, `rds:DescribeDBInstances` — **Slow Query → RDS 스케일업**

### ③ VPC 및 SSM 통신 경로 — `network.tf`

프라이빗 서브넷의 SSM Agent가 SSM 컨트롤 플레인과 HTTPS(443)로 통신할 수 있어야 한다. 본 구성은 **NAT/IGW 없이 VPC 엔드포인트**로 처리한다.

- **3개 Interface 엔드포인트**(Private DNS 활성):
  - `com.amazonaws.ap-northeast-2.ssm`
  - `com.amazonaws.ap-northeast-2.ssmmessages`
  - `com.amazonaws.ap-northeast-2.ec2messages`
- 엔드포인트 전용 보안그룹은 VPC CIDR로부터 443 인바운드 허용. 인스턴스 SG는 인바운드 없음.

> [!tip] 인터넷 경로를 쓰는 대안
> 빠른 PoC가 목적이라면 퍼블릭 서브넷 + IGW 라우팅으로도 SSM Agent 통신이 가능하다(엔드포인트 불필요). 본 구성은 메일에서 강조된 **보안(프라이빗) 경로**를 채택했다. 필요 시 `network.tf`를 IGW 방식으로 교체.

### ④ ECS Fargate — **추후 모듈로 분리 (이번 범위 제외)**

BIO 1차 프리뷰가 Fargate 대상이므로 `aws_ecs_cluster` + Fargate `aws_ecs_service`를 선언적으로 준비해두면 프리뷰 오픈 시 즉시 결합 가능하다. 이번엔 **EC2/SSM 우선** 방침에 따라 별도 모듈로 남겨둔다.

### 자동조치 대상 — `autoscaling.tf`
CPU Spike → `SetDesiredCapacity` 시나리오 검증용 Launch Template + ASG. `enable_autoscaling_target = false`로 끌 수 있다.

---

## 3. 파일 구성 (`terraform/`)

| 파일 | 내용 |
|---|---|
| `versions.tf` | Terraform ≥1.5, AWS provider ~>5.40 |
| `providers.tf` | 리전·default_tags |
| `variables.tf` | 리전/네트워크/EC2/Datadog 연동 변수 |
| `terraform.tfvars.example` | 실제 값 채우기용 템플릿 |
| `network.tf` | VPC·프라이빗 서브넷·SG·SSM 엔드포인트 3종 |
| `iam_instance.tf` | 역할1: EC2 인스턴스 프로파일 |
| `iam_datadog.tf` | 역할2: Datadog 크로스계정 Role |
| `ec2.tf` | AL2023 EC2 |
| `autoscaling.tf` | 자동조치 대상 ASG |
| `outputs.tf` | Role ARN, 인스턴스 ID 등 |

### 적용 절차
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # 값 채우기
# datadog_external_id 를 Datadog 통합 화면 발급값으로 교체
terraform init
terraform plan
terraform apply
```
적용 후 `datadog_integration_role_arn` 출력값을 Datadog Integrations > AWS 화면에 등록한다.

> [!warning] 검증 상태
> 이 저장소는 정적 검증(괄호 균형 / `var`·`data`·`local` 참조 일관성 / 리소스 중복 정의 없음)을 통과했다. 다만 작업 샌드박스의 네트워크 제한으로 **`terraform init/validate`는 실행하지 못했다.** 실제 환경에서 `terraform init && terraform validate`를 한 번 돌려 provider 스키마 기준 최종 확인 권장. 또한 IAM 정책의 `Resource = "*"`는 PoC 편의를 위한 초안이므로 운영 전 특정 ARN으로 좁힐 것.

---

## 4. 미팅 전 액션 아이템 (발신 필요)

Terraform 외에, 현재 메일 스레드에서 **우리 측(조은율 님 포함 팀원)이 Datadog에 회신**해야 하는 항목:

- [ ] 8/13 데모 미팅 **메가존 측 최종 참석자 명단** 공유
- [ ] Datadog 샌드박스(megazone cloud) 초대용 **테스트 담당자 이메일 주소** 취합·전달
- [ ] Bits Detection 데모를 위한 **APM 설정** 사전 확인
- [ ] (선택) EC2 자동조치 시나리오 그림 — CPU Spike→ASG, Slow Query→RDS — 미팅 논의자료로 준비

---

## 관련 노트
- [[Control Tower 운영 플레이북]]
- 3층 구조(정책→운영모델→도구) 관점에서 이 PoC는 **"도구(Datadog 자동조치)를 운영모델에 결합하는 협의"**의 실증 사례에 해당
