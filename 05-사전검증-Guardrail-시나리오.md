---
tags: [poc, guardrail, pre-action, policy-as-code, opa, sentinel, msp-operations]
type: reference
status: living
created: 2026-08-11
aliases:
  - "사전 검증 Guardrail 시나리오"
  - "Pre-action Guardrail 저수지"
related:
  - "[[Datadog PoC — 진행 방향 및 Terraform 준비]]"
  - "[[PoC 시나리오 후보 수집]]"
  - "[[이 PoC 의 성격 — Preview 와 자동화 확장, 그리고 파트너십]]"
---

# 사전 검증 (Guardrail) 시나리오 저수지

> [!info] 왜 별도 문서인가
> 이 노트는 **[[PoC 시나리오 후보 수집]] 과 분리된 축**을 담는다. 앞 문서(03) 는 **Datadog 감지·조치** 축의 시나리오 저수지이고, 이 문서(05) 는 **작업 사전 검증(guardrail)** 축의 저수지다. 둘은 트리거 모델·담당 도구·Datadog 역할이 근본적으로 다르다.

---

## 0. 감지 vs 사전 검증 — 근본 차이

| 축 | 감지·조치 (문서 03) | 사전 검증 (이 문서) |
|---|---|---|
| **트리거** | 시스템 상태 (지표·추세) | 작업자 요청 (사람·시스템 액션) |
| **아키텍처** | Push 기반 · 비동기 | Pull 기반 · 동기 |
| **주체** | Datadog 이 능동적 관찰자 | Datadog 은 수동적 응답자 |
| **시점** | 문제 발생 후 or 조짐 | **작업 실행 순간** |
| **응답 유형** | 알림·자동 조치 | 진행·차단·수정 판정 |
| **핵심 도구** | Datadog (native) | **OPA/Sentinel/SCP** 등 (Datadog 은 통합 지점) |
| **가치 명제** | AI 관측·판단 | 정책 강제·안전망 |

**감지 축**: [Metric 소스] → Datadog → Monitor → Workflow → 액션  
**사전 검증 축**: [작업 요청] → 외부 시스템 → Datadog API 참조 → 판정 → 액션 진행·차단

---

## 1. Native pre-action 이 강한 도구들 (Datadog 이 아닌 것들)

이 영역의 진짜 강자들. Datadog 은 여기 native 아니라 **정책 판정의 근거 데이터·감사 저장소** 역할.

### A. Policy-as-Code 엔진

| 도구 | 트리거 지점 | 특징 |
|---|---|---|
| **HashiCorp Sentinel** | Terraform Cloud/Enterprise plan → apply 사이 | Terraform 사전 검증 gold standard |
| **Open Policy Agent (OPA)** | K8s admission, Terraform, HTTP/gRPC | CNCF graduated. Rego 언어. 범용 |
| **OPA Gatekeeper** | K8s Admission Webhook | OPA 의 K8s 특화판 |
| **Kyverno** | K8s Admission Webhook | YAML 기반, K8s 커뮤니티 친화 |
| **Checkov / Terrascan / tfsec** | CI 파이프라인 IaC 정적 분석 | 오픈소스, 광범위 룰셋 |

### B. Cloud Provider Guardrail

| 도구 | 계층 | 특징 |
|---|---|---|
| **AWS Service Control Policies (SCP)** | AWS Organization 상위 IAM | 계정 전체 API Deny. 실수 원천 차단 |
| **AWS IAM Permission Boundaries** | IAM 최대 권한 상한 | 위임 관리자 권한 상한 |
| **AWS Control Tower Guardrails** | 다중 계정 landing zone | 조직 표준 자동 강제 |
| **AWS Config Rules + SSM Automation** | 리소스 변경 이벤트 감지 후 즉시 원복 | 진짜 pre-action 은 아니지만 초 단위 원복 |
| **AWS Service Catalog** | 사전 승인된 템플릿만 배포 가능 | 자유도 낮추고 안전성 높임 |
| **Azure Policy / GCP Org Policy** | 각 클라우드 동등 기능 | 유사 패턴 |

### C. CI/CD 파이프라인 게이트

| 도구 | 무엇을 검증 | 특징 |
|---|---|---|
| **GitHub branch protection + required checks** | 병합 전 검증 필수 | PR 승인 룰 |
| **GitLab MR approval rules** | 위와 유사 | MR 승인 |
| **Terraform Cloud Run Tasks** | plan 후 외부 시스템 호출 | 판정 결과 받아 apply 진행/차단 |
| **Snyk / Trivy / Checkov CI** | 파이프라인 단계 스캔 | 취약점·정책 위반 감지 |
| **PagerDuty Change Events + Approval** | 변경 발생 전 승인 절차 | 조직 change management |

### D. Kubernetes 특화

| 도구 | 트리거 | 특징 |
|---|---|---|
| **Kyverno** | Admission Webhook | K8s YAML policy |
| **OPA Gatekeeper** | Admission Webhook | 범용 OPA 의 K8s 판 |
| **Kubewarden** | Admission | WebAssembly 기반 |
| **Pod Security Admission** | K8s 내장 | 파드 보안 표준 강제 |

---

## 2. 사전 검증 시나리오 저수지 (5 하위 카테고리)

### G-1. 파괴적 작업 전 dependency 체크

| 시나리오 | 가치 |
|---|---|
| EC2 종료 전 활성 세션·트랜잭션·in-flight 요청 확인 | 진행 중 작업 손실 방지 |
| EBS 볼륨 detach/삭제 전 마운트 사용 여부 | 프로세스 crash 방지 |
| Security Group 삭제 전 참조 중인 리소스 나열 | 네트워크 격리 실수 방지 |
| Subnet/VPC 삭제 전 종속 리소스(ENI, LB, DB) 나열 | 인프라 붕괴 방지 |
| AMI 삭제 전 Launch Template/ASG 참조 여부 | 신규 인스턴스 시작 실패 방지 |
| EIP 해제 전 DNS/외부 참조 확인 | 서비스 접근 불가 방지 |
| RDS 인스턴스 삭제 전 스냅샷 정책 확인 | 데이터 복구 가능성 확보 |

### G-2. 정책·권한 변경 전 영향 예측

| 시나리오 | 가치 |
|---|---|
| IAM 정책 변경 전 영향받는 서비스·역할 목록 | 권한 손실로 인한 다운 방지 |
| KMS 키 정책 변경 전 암호화 사용 리소스 스캔 | 데이터 접근 불가 방지 |
| S3 버킷 정책 변경 전 public 노출 위험 시뮬레이션 | 데이터 유출 방지 |
| WAF 룰 변경 전 최근 트래픽 기반 false positive 예상 | 정상 트래픽 차단 방지 |
| Route53 레코드 변경 전 TTL 기반 전파 시간·영향 범위 예측 | 롤백 창구 예측 |

### G-3. 배포·릴리스 전 사전 조건 검증

| 시나리오 | 가치 |
|---|---|
| 배포 전 필수 환경변수·시크릿 존재 확인 | Config 누락 실패 방지 |
| 배포 전 의존 서비스(DB/Redis/외부 API) 헬스 확인 | 다운스트림 연쇄 실패 예방 |
| DB 마이그레이션 dry-run 결과 검토 | 마이그레이션 롤백 불가 상태 예방 |
| Certificate 유효성 및 chain 검증 | HTTPS 접근 불가 방지 |
| ECS 배포 전 configuration 검증 (max/min × desired vs 클러스터 capacity) | 배포 실패 예방 |
| 배포 전략 ↔ 아키텍처 불일치 감지 (Blue-Green 인데 replacement group 미준비 등) | 배포 정책 리뷰 트리거 |
| Kubernetes admission webhook 유사 사전 검증 (매니페스트 문법·정책 통과) | 클러스터 배포 전 안전망 |

### G-4. 용량·쿼터 여유 사전 확인

| 시나리오 | 가치 |
|---|---|
| 스케일업 요청 전 클러스터 capacity 확인 | 스케일링 실패 방지 |
| 신규 리소스 생성 전 AWS 서비스 쿼터 여유 | API throttling 방지 |
| VPC 서브넷 IP 여유 확인 (신규 ENI 필요 리소스 배포 전) | ENI 생성 실패 방지 |
| NAT Gateway 대역폭 여유 (예상 트래픽 vs 현재 사용률) | 스로틀링 방지 |
| RDS 스토리지 여유 확인 (auto-grow 임박 전 신규 워크로드 배포) | 스토리지 이슈 예방 |

### G-5. 비용·리스크 승인 게이트

| 시나리오 | 가치 |
|---|---|
| 비싼 인스턴스 타입(예: p4d, x2iedn) 생성 시 승인 요구 | 실수·오남용 방지 |
| Cross-region 데이터 전송 시 비용 사전 예측 | 예상 밖 비용 폭탄 방지 |
| 대용량 쿼리 실행 전 DB 부하·예상 시간 예측 | 서비스 영향 예방 |
| 정기 유지보수 창구 진입 전 진행 중 배치·트랜잭션 확인 | 롤백 불가 상태 방지 |
| 프로덕션 리소스 삭제 시 태그 기반 승인 워크플로 | 실수 삭제 방지 |

---

## 3. 5가지 트리거 패턴

같은 시나리오라도 어떤 지점에서 잡느냐에 따라 구현이 달라진다.

### Pattern A — CI/CD 파이프라인 게이트
```
[git push] → GitHub Actions / GitLab CI → 배포 스텝 전 검증 훅 → 통과 시 배포
```
- **정책 엔진**: Sentinel, OPA, Checkov, Snyk
- **Datadog 역할**: 검증 로직에 관측 데이터 제공 (예: 현재 트래픽 조회)
- **자연스러운 시나리오**: G-3 (배포 사전 조건)

### Pattern B — Terraform / IaC 훅
```
[terraform plan] → plan 결과를 정책 엔진에 POST → 판정 → apply 진행/차단
```
- **정책 엔진**: Sentinel (Terraform Cloud), OPA, Terrascan
- **Datadog 역할**: 영향 리소스의 현재 상태 조회, 감사 로그 저장
- **자연스러운 시나리오**: G-1, G-2, G-5

### Pattern C — ChatOps (Slack/Teams)
```
[/terminate ec2-abc] → Slack bot → Datadog Workflow (or custom bot) → 
컨텍스트 조회 → "위험 요소" 응답 → 사람 확인 → 실행
```
- **정책 엔진**: 커스텀 워크플로 (Datadog Workflow, StackStorm, Rundeck)
- **Datadog 역할**: 여기서는 상대적으로 큼 (컨텍스트 조회 + 승인 UX)
- **자연스러운 시나리오**: G-1 (사람 판단 개입 유용한 것)

### Pattern D — Kubernetes Admission Webhook
```
[kubectl apply] → K8s API server → Admission Webhook → 정책 판정 → 승인/거부
```
- **정책 엔진**: Kyverno, OPA Gatekeeper, Kubewarden
- **Datadog 역할**: 매우 제한적. 감사·이벤트 수집 정도
- **자연스러운 시나리오**: G-3 (K8s 매니페스트), G-4 (K8s 리소스)

### Pattern E — AWS Config Rules + 즉시 remediate (post-action + rapid rollback)
```
[AWS API 호출로 리소스 변경] → CloudTrail → EventBridge → 
정책 위반 판정 시 즉시 원복 API 호출
```
- **정책 엔진**: AWS Config Rules + SSM Automation Runbook
- **Datadog 역할**: 이벤트 수집·알림, 사후 감사
- **자연스러운 시나리오**: G-2 (실행된 정책 변경 즉시 원복), G-5 (실행된 고비용 리소스 즉시 정리)

---

## 4. 시나리오 × 트리거 패턴 매트릭스

각 시나리오에 자연스러운 트리거 패턴을 태그로:

| 시나리오 | 자연스러운 패턴 |
|---|---|
| EC2 종료 전 세션 확인 | C (ChatOps) |
| EBS detach 전 마운트 확인 | C (ChatOps) |
| Security Group 삭제 전 참조 리소스 | B (IaC 훅) or C |
| Subnet/VPC 삭제 전 종속 리소스 | B (IaC 훅) |
| AMI 삭제 전 Launch Template 참조 | B (IaC 훅) |
| IAM 정책 변경 전 영향 | B (IaC 훅) + E (사후 원복) |
| S3 public 노출 위험 | B + E |
| WAF 룰 변경 전 FP 예상 | B + C |
| 배포 전 환경변수·시크릿 | A (CI 게이트) |
| 배포 전 의존 서비스 헬스 | A |
| DB 마이그레이션 dry-run | A |
| Certificate 유효성 | A |
| ECS 배포 configuration 검증 | A + B |
| K8s 매니페스트 검증 | D (Admission) |
| 스케일업 전 capacity | B or C |
| 서비스 쿼터 여유 확인 | B |
| VPC IP 여유 | B |
| 비싼 인스턴스 생성 승인 | B + E |
| Cross-region 비용 예측 | B |
| 대용량 쿼리 부하 예측 | A + C |
| 유지보수 창구 진입 전 확인 | C |
| 프로덕션 리소스 삭제 태그 검사 | B + E |

---

## 5. Datadog 이 이 영역에서 하는 역할

Datadog 은 **정책 판정 엔진이 아님**. 대신 다음 역할로 결합됨:

| 역할 | 설명 |
|---|---|
| **컨텍스트 제공자** | 정책 엔진이 판정 시 참조할 관측 데이터 제공 (트래픽, 헬스, 사용률 등) |
| **감사 저장소** | 판정 결과·이벤트 로그를 시간 순으로 축적. 사후 감사 가능 |
| **알림 채널** | 판정 결과를 Slack·이메일·PagerDuty 로 전달 |
| **워크플로 오케스트레이션** | 판정 실행을 Datadog Workflow 로 조율 (Pattern C 에서 특히) |

즉 **"정책 판정은 OPA/Sentinel/SCP 가, 관측·감사·알림은 Datadog 이"** 조합이 자연스러움.

예시 결합:
```
[terraform apply]
  → Sentinel 정책: "prod 리소스 삭제 시 태그 확인"
    ↓ Sentinel → Datadog API: "이 EC2 최근 1시간 트래픽 있었나?"
  → Datadog 응답: "지난 30분간 active requests 있음"
    ↓ Sentinel: "traffic 있으면 삭제 금지"
  → apply 차단
  ↓
[Datadog 감사 로그]: "prod ec2 삭제 시도 차단됨 (traffic active)"
```

---

## 6. 미팅 관점 활용

8/13 미팅에서 Datadog PM 에게 물어볼 만한 질문:

- **"Datadog Workflow Automation 이 OPA / Sentinel / Kyverno 와 어떻게 통합되나?"**
- **"AWS Config Rules 의 non-compliance 이벤트를 Datadog 이 어떻게 수신·처리하나?"**
- **"CI/CD 파이프라인에서 Datadog Workflow 를 pre-deployment 게이트로 호출하는 표준 패턴이 있나?"**
- **"BIO 가 pre-action 검증 영역까지 확장할 계획이 있나, 아니면 감지·조치에 집중하나?"**
- **"Terraform Cloud Run Tasks 에 Datadog 이 등록된 파트너인가?"**

이 질문들은 **"Datadog 을 어떻게 우리 guardrail 스택에 통합할지"** 의 답을 얻는 재료.

---

## 관련 노트

- [[Datadog PoC — 진행 방향 및 Terraform 준비]] — PoC 전체 진행 방향
- [[PoC 시나리오 후보 수집]] (문서 03) — 감지·조치 축의 시나리오 저수지
- [[이 PoC 의 성격 — Preview 와 자동화 확장, 그리고 파트너십]] — PoC 성격·포지셔닝
