---
tags: [datadog, product-overview, bits-detection, bio, workflow-automation, ai-ops]
type: reference
status: draft
created: 2026-08-11
related:
  - "[[Datadog PoC — 진행 방향 및 Terraform 준비]]"
---

# Datadog AI 자율운영 스택 — 3개 기능의 원래 목적

> [!info] 한 줄 요약
> Datadog은 **"관찰(Observability) → 자율운영(Autonomous Operations)"** 이라는 큰 서사를 3층 스택으로 실현 중이다. 이 노트는 **Bits Detection · BIO · Workflow Automation** 이 **각각 원래 어떤 문제를 풀려고 만들어진 제품인지** 를 PoC 맥락과 분리해 정리한다. 우리 PoC 시나리오가 각 기능에 왜 그렇게 매핑되는지의 근거가 여기서 나온다.

---

## 0. 배경 — 왜 3층 스택인가

Datadog은 원래 **관찰(Observability)** 회사였다. 지표·로그·트레이스를 수집하고 대시보드·모니터로 보여주는 것이 본업. 최근 몇 년간 Datadog은 이 위에 두 레이어를 얹어 **"AI가 감시를 관리하고, AI가 조치를 제안·수행하는 자율운영"** 으로 스택을 확장하고 있다.

세 기능을 **감지 축**과 **조치 축**으로 나누면 다음과 같은 지도가 나온다.

```
             감지 축                                     조치 축
──────────────────────                          ──────────────────────

  [기존 Monitors]  ←── 사람이 룰 작성           [Workflow Automation]  ← 사람이 워크플로 작성
        ↑                                                ↑
        │ 자동 관리                                       │ 자동 판단
        │                                                │
  [Bits Detection]  ← AI가 큐레이션              [BIO]  ← AI가 조치 제안
  (APM services)                                  (Fargate/Serverless 우선, EC2 로드맵)
```

- **Workflow Automation**: 이미 GA. 결정론적 자동화 엔진.
- **Bits Detection**: 프리뷰. 모니터 큐레이션을 AI가 담당.
- **BIO (Bits Infrastructure Operations)**: 프리뷰. 조치 판단·수행을 AI가 담당.

세 기능은 **경쟁 관계가 아니라 스택 관계**다. 아래에서 각각의 원래 설계 의도를 살핀다.

---

## 1. Bits Detection — "감지의 AI 자동화"

### 원래 목적
사람이 일일이 "이 지표를 이 임계값으로 감시하라"고 지정하는 대신, **AI가 무엇이 중요한지 판단하고 모니터를 자동 생성·튜닝** 하게 만드는 것.

### 해결하려는 문제
- **모니터 스프롤(sprawl)** — 서비스 수백 개가 되면 각 팀이 만든 모니터가 수천 개로 폭증. 노이즈·중복·구멍이 공존.
- **정적 임계값의 무의미함** — "CPU > 80%" 같은 룰이 시간·환경별로 안 맞음.
- **커버리지 사각지대** — 새로 배포된 엔드포인트나 새 종속성이 감시망에 안 잡히는 문제.

### 핵심 포지셔닝
**"AI가 관리하는 모니터 큐레이션 레이어"**. 사람은 "이거 중요/안 중요"라는 피드백만 준다. 정적 임계값 대신 프로덕션 실제 동작에 튜닝된 모니터가 자동으로 만들어진다.

### 대상 범위
**APM 계측된 HTTP/gRPC 서비스** (인프라 아님). 즉 "서비스 헬스" 축이지 "인스턴스 헬스" 축이 아니다.

### Datadog 내 위치
기존 Datadog Monitors는 사람이 만드는 방식. Bits Detection은 그 위에 얹혀서 **"모니터를 만들고 유지하는 일 자체를 AI가 담당"** 하는 상위 레이어.

> [!important] 사전조건
> Bits Detection은 **Preview** 상태다. Datadog 담당자에게 조직(Organization) 단위로 액세스 활성화를 요청해야 콘솔에 나타난다. Terraform이나 AWS 리소스와 무관하며, `app.ddog-gov.com` / `us2.ddog-gov.com` (GovCloud) 는 미지원.

---

## 2. BIO (Bits Infrastructure Operations) — "조치의 AI 자동화"

### 원래 목적
감지된 이슈를 **AI가 원인 진단 → 조치안 제시 → 승인 후 실행** 까지 이어주는 자율운영 루프. 사람이 runbook을 손으로 실행하지 않아도 되게 만드는 것.

### 해결하려는 문제
- **알림 → 조치 사이의 인간 개입 지연** — 새벽에 알람 울리면 사람이 SSH로 붙어서 명령 치는 시간 낭비.
- **Runbook 유지·전파의 어려움** — 문서화된 대응 절차가 안 지켜지거나 사람마다 다르게 해석됨.
- **On-call 피로** — 반복 조치를 자동화해서 인간은 판단만 하도록(Slack에서 승인 클릭).

### 핵심 포지셔닝
**"AI 오퍼레이터"**. Datadog이 상황을 이해하고 *"이 스크립트 실행할까요?"* 를 Slack으로 물어보고, "예" 누르면 자동으로 SSM 등을 통해 실행한다.

### 대상 범위 (현재)
**ECS Fargate + Serverless 1차 프리뷰**. EC2는 로드맵.

### Datadog 내 위치
Bits Detection이 신호를 만들면 BIO가 그 신호에 반응해서 인프라를 조작. **"AI가 만든 신호를 AI가 받아 처리"** 하는 폐루프의 조치 담당.

> [!warning] EC2 미지원
> BIO 1차 프리뷰는 **ECS Fargate/Serverless** 대상. EC2 자동조치 시나리오는 현재 실측 불가하며 **논의·로드맵 협의 대상**이다. 그래서 이 PoC의 EC2 시나리오는 8/13 미팅에서 "실측"이 아니라 "제품팀과의 방향성 논의" 재료로 쓰인다.

---

## 3. Workflow Automation — "규칙 기반 조치 자동화"

### 원래 목적
Datadog 내부의 이벤트(알림·HTTP 트리거·스케줄 등)를 시작점으로 **AWS·Slack·PagerDuty·Jira 등 외부 도구를 조율(orchestrate)** 하는 워크플로 엔진.

### 해결하려는 문제
- **"알람 → 티켓 발행 → Slack 알림 → 임시 조치"** 를 사람이 여러 콘솔 오가며 수행하던 반복.
- Datadog에서 감지된 상황을 **다른 도구의 액션**으로 이어붙이는 접착제 부재.
- 정형화된 대응 절차(스케일아웃, 롤백, 재시작)를 코드가 아닌 GUI 워크플로로 만들고 싶은 요구.

### 핵심 포지셔닝
**"Datadog 이벤트를 시작점으로 하는 Zapier / IFTTT / GitHub Actions"**. 규칙 기반이고 결정론적. **AI 아님**.

### 대상 범위
**이미 GA(정식 출시)**. 오늘 켜서 씀. 300+ 액션 카탈로그(AWS/Slack/PagerDuty/Jira/Terraform Cloud 등).

### Datadog 내 위치
BIO보다 하위 레이어. **"AI가 없어도 자동조치를 할 수 있게 해주는 결정론적 엔진"**. BIO가 내부적으로 이걸 실행 백엔드로 재사용할 가능성도 있음.

> [!tip] 즉시 사용 가능
> 세 기능 중 유일하게 GA. 이 PoC의 실측 트랙("CPU Spike → ASG SetDesiredCapacity")이 여기서 돌아간다. Bits/BIO 오픈을 기다릴 필요 없이 오늘 켜서 실증 가능.

---

## 4. 요약 매트릭스

| 축 | 원래 풀려는 문제 | 방식 | 성숙도 | 대상 |
|---|---|---|---|---|
| **Bits Detection** | 모니터 만들고 유지하는 노동 | AI가 대신 | Preview | APM 계측 HTTP/gRPC 서비스 |
| **BIO** | 알람 → 조치 사이 사람 개입 | AI가 진단·제안, 사람은 승인만 | Preview (Fargate·Serverless 1차) | ECS/Serverless, 향후 EC2 |
| **Workflow Automation** | Datadog 이벤트를 외부 도구 액션으로 잇기 | 결정론적 규칙 엔진 | **GA** | 300+ 액션 카탈로그 |

---

## 5. 한 문장 정리

- **Bits Detection**: *"무엇을 감시할지"* 를 AI가 결정.
- **BIO**: *"무엇을 조치할지"* 를 AI가 제안 + 실행.
- **Workflow Automation**: *"무엇을 조치할지"* 를 사람이 룰로 정의 + 실행.

Datadog은 **"관찰 → 자율운영"** 이라는 큰 서사를 3층 스택으로 구현하는 중이며, 아래층(Workflow)은 이미 있고 위 두 층(Bits Detection, BIO)은 프리뷰 단계다.

---

## 6. PoC 관점의 함의 (요약)

이 3층 구조가 우리 PoC의 트랙 분리를 그대로 설명한다.

| 트랙 | 대응 기능 | 8/13 성격 |
|---|---|---|
| Bits Detection 데모 관람 | 감지 자동화 (프리뷰) | 제품 이해 |
| BIO EC2 시나리오 심층 논의 | 조치 자동화 (프리뷰, EC2 미지원) | 로드맵 협의 |
| Workflow Automation 샌드박스 실습 | 결정론적 조치 자동화 (GA) | 실측 |

세 트랙이 왜 성격이 다른지, 왜 어떤 건 실측이고 어떤 건 논의인지는 이 3층 스택 각각의 성숙도·대상 범위 차이에서 나온다.

---

## 관련 노트
- [[Datadog PoC — 진행 방향 및 Terraform 준비]] — 이 3개 기능을 검증하기 위한 PoC 인프라 준비물(Terraform)
