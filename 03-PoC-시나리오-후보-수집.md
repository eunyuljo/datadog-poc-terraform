---
tags: [datadog, poc, scenarios, backlog, breadth, depth, msp-operations]
type: reference
status: living
created: 2026-08-11
aliases:
  - "PoC 시나리오 후보 수집"
  - "PoC 시나리오 후보 수집 — Breadth & Depth"
related:
  - "[[Datadog PoC — 진행 방향 및 Terraform 준비]]"
  - "[[Datadog AI 자율운영 스택 — 3개 기능의 원래 목적]]"
  - "[[이 PoC 의 성격 — Preview 와 자동화 확장, 그리고 파트너십]]"
  - "[[메가존 PoC 실행 계획]]"
---

# PoC 시나리오 후보 수집 — Breadth & Depth

> [!info] 이 노트의 용도
> 8/13 미팅과 그 이후 Datadog 자율운영 확장 협의에 재사용할 **시나리오 저수지(reservoir)**. 두 축으로 수집:
> - **Breadth (넓이)**: MSP 가 실제 운영에서 마주치는 다양한 도메인의 페인 — *"이런 것들을 자율운영이 커버해야 한다"*
> - **Depth (깊이)**: 자율운영의 본연 기능(감지 정확성·판단 신뢰성·조치 안전성 등) 을 검증하는 어려운 케이스 — *"이걸 못 하면 자율운영이라 부르기 어렵다"*
>
> 이 목록은 **living document** — 미팅과 실측을 반복하며 계속 확장한다.

---

## 0. 두 축을 나누는 이유

- **Breadth** = *얼마나 넓게 커버하는가* — Datadog 로드맵의 우선순위 근거
- **Depth** = *얼마나 신뢰할 수 있는가* — 자율운영 프로덕트 품질 근거

두 축은 목적·청중이 다르다:

| 축 | 청중 | 8/13 미팅에서의 용도 |
|---|---|---|
| **Breadth** | Datadog 로드맵/제품 관리 담당 | "이 시나리오도 지원해달라" — 커버리지 요청 목록 |
| **Depth** | Datadog 프로덕트 PM (AI 담당) | "AI 자율운영이 정말 자율적이려면 이런 케이스도 다뤄야" — 심층 논의 |

---

## 1. Bucket 1 — Breadth (도메인별)

MSP 관점에서 실제 마주치는 운영 이슈. Datadog 현재 스택 대응 상태를 병기.  
(✅ = 지금 가능, 🟡 = 부분/특정 조건 필요, ❌ = 로드맵 대상)

### A. 컴퓨트

| 시나리오 | 대응 (현재 Datadog 스택) |
|---|---|
| JVM heap 이상 증가 → GC pause 폭증 | Bits Detection(APM) ✅ 감지 / BIO ❌ 조치 |
| 파일 디스크립터 고갈 (`too many open files`) | Monitor + Workflow ✅ |
| 커널 패닉 / 인스턴스 상태 이상 | CloudWatch + Workflow 🟡 |
| 노드 disk IOPS 크레딧 소진 | Monitor 🟡 |
| 컨테이너 이미지 pull 실패 반복 | ECS/EKS 컨텍스트 필요 |

### B. 스토리지

| 시나리오 | 대응 |
|---|---|
| EBS 볼륨 사용률 임계 | Monitor + Workflow ✅ |
| S3 5xx / RequestTimeout 급증 | Monitor 🟡 |
| EFS 처리량 크레딧 소진 | Monitor 🟡 |
| 스냅샷 실패 | EventBridge + Workflow |

### C. 네트워크

| 시나리오 | 대응 |
|---|---|
| NAT Gateway 대역폭 스파이크 | Monitor 🟡 |
| VPC Endpoint 스로틀 | 모니터링 어려움 |
| DNS(Route53) 응답 지연 | Synthetic + Monitor |
| CloudFront 캐시 히트율 급락 | Monitor 🟡 |
| ALB target 5xx 급증 | Monitor + Workflow ✅ |

### D. 데이터

| 시나리오 | 대응 |
|---|---|
| RDS 스토리지 오토그로우 임계 도달 | Monitor + Workflow |
| DynamoDB 스로틀 급증 | Monitor + Workflow |
| ElastiCache eviction 급증 | Monitor + Workflow |
| MSK/Kafka 컨슈머 lag | Monitor 🟡 |
| MSK 브로커 다운 시 자동 페일오버 확인 | Monitor + 페일오버 검증 스크립트 |

### E. 서버리스

| 시나리오 | 대응 |
|---|---|
| Lambda concurrency 임계 접근 | Monitor + Workflow (concurrency 조정) |
| Lambda cold start 급증 | Provisioned concurrency 조정 |
| Step Functions 실행 실패율 급증 | Monitor + Workflow |

### F. 보안

| 시나리오 | 대응 |
|---|---|
| GuardDuty findings 급증 | EventBridge + Workflow |
| Root 계정 사용 탐지 | CloudTrail + immediate alert |
| WAF 차단 트래픽 급증 (DDoS 의심) | Shield Advanced + Workflow |
| Secrets Manager rotation 실패 | Monitor + Workflow |
| IAM 정책 부적절 변경 | Config + Workflow |

### G. 배포·릴리스

| 시나리오 | 대응 |
|---|---|
| CodeDeploy/CodePipeline 실패 반복 | Monitor + Workflow |
| Canary 배포 에러율 임계 | Datadog Deployment Tracking |
| 롤백 자동화 | Workflow ✅ |

### H. 관측성 자체 (Meta-observability)

| 시나리오 | 대응 |
|---|---|
| Datadog Agent 자체 down | 우회 채널 필요 (다른 모니터링) |
| 로그 수집 급감 (파이프 이슈) | Monitor 🟡 |
| Metric 급감 (수집 이슈 vs 실제 다운 구분) | 판단 어려움 — **AI 가치 큼** |

### I. 비용·거버넌스 (FinOps)

| 시나리오 | 대응 |
|---|---|
| 특정 서비스 24h 비용 스파이크 | Cost Explorer + Workflow |
| Zombie 리소스(EBS, EIP, NAT) 누적 | 정기 스캔 + Workflow |
| Tag 컴플라이언스 위반 | Config + Workflow |

---

## 2. Bucket 2 — Depth (자율운영 본연 기능)

### 2.1 자율운영의 본연 요건 5가지

| 요건 | 왜 중요한가 |
|---|---|
| ① **감지의 정확성** | False positive(불필요 조치) / false negative(놓침) 최소화 |
| ② **판단의 신뢰성** | 복합 원인 상황에서 올바른 원인 지목 |
| ③ **조치의 안전성** | 잘못된 조치가 상황을 악화시키지 않을 것 |
| ④ **롤백 가능성** | 조치 후 되돌리기 가능 |
| ⑤ **컨텍스트 인지** | 유지보수 창구·정상 배포 등을 이상으로 오판하지 않기 |

### 2.2 각 요건을 검증하는 어려운 시나리오

#### ① 감지 정확성
- **정상 트래픽 스파이크** — 마케팅 캠페인, 세일 이벤트로 인한 정상 급증. 자동조치 하면 안 됨. AI 가 컨텍스트로 구분해야 함
- **점진적 열화(gradual degradation)** — 몇 시간에 걸친 서서히 나빠짐. 임계값 기반은 놓치기 쉬움. 추세 감지 필요
- **주기적 정상 이상치** — 매일 새벽 배치로 인한 CPU 스파이크. 정상 패턴 학습 필요

#### ② 판단 신뢰성
- **복합 원인** — DB 느려짐이 원인인지, 앱 코드 이슈인지, 네트워크 이슈인지 구분
- **연쇄 실패(cascading failure)** — 앞선 실패의 후유증(캐시 stampede, 재시도 폭주) 을 원인 이슈로 오판하지 않기
- **다중 인스턴스 중 하나만 이상** — 특정 노드만 문제인지 전체 문제인지 구분

#### ③ 조치 안전성
- **재시작으로 캐시 warm-up 소실** — 재시작 자체가 다음 리퀘스트에 문제 유발
- **스케일 아웃이 DB 커넥션 폭증 유발** — 조치의 부작용
- **디스크 청소가 활성 로그 삭제** — 진행 중인 파일 지우는 위험
- **프로세스 kill 이 트랜잭션 손실 유발** — graceful shutdown 필요

#### ④ 롤백 필요
- **조치 후 상황 악화** — 조치했는데 지표 더 나빠짐. 즉시 되돌려야 함
- **잘못된 롤백** — 새 배포로 문제 해결됐는데 이전 버전으로 되돌리면 재발

#### ⑤ 컨텍스트 인지
- **유지보수 창구 중 이상치** — 계획된 작업 중엔 알람 억제 (maintenance window)
- **배포 중 이상치** — 배포 5분 이내 이상은 배포 이슈로 판단
- **의도된 부하 테스트** — 테스트 트래픽인지 실 트래픽인지 구분
- **다중 리전 페일오버 중** — 페일오버 중엔 트래픽 이상이 정상

---

## 3. 이 목록의 활용 방법

### 3.1 8/13 미팅 자료로

- Datadog PM 에게 **Bucket 1** 을 카테고리별로 열어 보이며 *"이 중 지금 BIO Preview 에서 커버되는 게 무엇이고, 로드맵에 있는 게 무엇인지"* 질의
- **Bucket 2** 를 별도로 열어 *"자율운영의 신뢰성을 위해 이런 케이스들은 어떻게 다루는지"* 심층 질의

### 3.2 미팅 이후 지속 활용

- 새로 발견한 페인 → Bucket 1 해당 카테고리에 append
- 자율운영 시도 중 발견한 신뢰성 이슈 → Bucket 2 해당 요건에 append
- 각 시나리오별로 [[메가존 PoC 실행 계획]] 의 실증 무대(chaos-app 등) 로 이관 가능한지 검토

### 3.3 시나리오 승격 조건 (여기 → 실증)

Bucket 1/2 에 있던 시나리오가 **저장소의 chaos-app 이나 Terraform 으로 실증 가능해질 때** 는 [[메가존 PoC 실행 계획]] 의 §2 (커버 시나리오) 로 이동한다.

이 문서는 **아직 실증 안 된 후보 저수지** 역할이고, 저기는 **실증 완료된 시나리오 리스트** 역할이다. 두 문서가 시나리오의 수명 주기(**후보 → 실증**) 를 함께 담는다.

---

## 관련 노트

- [[Datadog PoC — 진행 방향 및 Terraform 준비]] — PoC 전체 진행 방향과 인프라 개요
- [[Datadog AI 자율운영 스택 — 3개 기능의 원래 목적]] — 3개 자동화 층의 제품 정의
- [[이 PoC 의 성격 — Preview 와 자동화 확장, 그리고 파트너십]] — PoC 성격·포지셔닝
- [[메가존 PoC 실행 계획]] — 실증 무대와 실행 절차
