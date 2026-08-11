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
**"AI가 관리하는 모니터 큐레이션 레이어"**. Bits Detection은 감시를 수행하는 도구가 아니라 **감시 계획을 세워주는** 도구다. 동작 흐름은:

1. 어떤 서비스/엔드포인트가 **중요한지 AI가 판단**
2. 그 대상에 맞는 **Monitor를 자동 생성·튜닝**
3. 사용자 피드백(중요/노이즈)으로 **재학습**

산출물은 **"잘 튜닝된 Monitor의 집합"** 이며, 발화·알림은 기존 **Datadog Monitors** 가 담당한다. 사람은 룰이 아니라 **피드백**을 준다.

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
**"AI 오퍼레이터"**. Datadog이 상황을 이해하고 *"이 스크립트 실행할까요?"* 를 Slack으로 물어보고, "예" 누르면 자동으로 SSM 등을 통해 실행한다. BIO의 핵심 가치는 **판단(진단·제안)** 에 있고, 실제 실행은 결정론적 엔진(§3 Workflow Automation)에 위임할 수 있다. 즉 **BIO = 판단 레이어**, **Workflow = 실행 레이어** — 조치 축의 같은 라인에 있지만 층이 다르다.

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
**"자동화된 런북(runbook) 엔진"**. 다른 표현으로는 "Datadog 이벤트를 시작점으로 하는 Zapier / IFTTT / GitHub Actions". 사람이 대본(트리거 → 액션 시퀀스)을 짜놓고 기계가 그대로 실행한다. **규칙 기반이고 결정론적. AI 아님**. 판단은 사람이, 실행은 엔진이 담당.

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

## 5. 한 문장 정리와 관계도

### 한 문장씩

- **Workflow Automation**: 자동화 **런북**. 사람이 짠 대본대로 실행.
- **Bits Detection**: AI **관제 계획 수립자**. 무엇을 감시할지 AI가 결정하고 Monitor를 자동 생성.
- **BIO**: AI **대응 오퍼레이터**. 감지된 이슈에 대해 조치안을 판단·제안 → 승인받아 실행.

### 각 기능이 담당하는 질문

세 기능은 **서로 다른 질문**에 답한다. 이 표 하나로 배치가 정리된다.

| 질문 | 담당 기능 | 방식 |
|---|---|---|
| *"무엇을 감시할지"* | **Bits Detection** | AI가 결정, Monitor를 자동 생성 |
| *"무엇을 조치할지"* | **BIO** | AI가 판단·제안, 사람이 승인 |
| *"어떻게 실행할지"* | **Workflow Automation** | 사람이 짠 대본을 결정론적으로 실행 |

### 관계도

```
[Bits Detection]  ──감지 신호──→  [BIO]           ──Slack 승인──→  [실행]
   (무엇을 볼지)                    (무엇을 할지)                       │
                                                                        │
                                    [Workflow Automation]  ─────────────┘
                                    (어떻게 실행할지 — 사람이 짠 대본)
```

- **왼쪽 축(Bits Detection → BIO)**: AI 폐루프. 감지도 AI, 조치도 AI.
- **오른쪽 축(Workflow Automation)**: 사람이 짠 대본을 결정론적으로 실행. AI 없음.
- **판단(BIO) 위에 실행(Workflow)이 얹혀 있는 구조**. 같은 조치 축이지만 서로 다른 층을 담당한다.

Datadog은 **"관찰 → 자율운영"** 이라는 큰 서사를 3층 스택으로 구현하는 중이며, 아래층(Workflow)은 이미 GA, 위 두 층(Bits Detection, BIO)은 프리뷰 단계다.

---

## 6. PoC 관점의 함의 (요약)

이 3층 구조가 우리 PoC의 트랙 분리를 그대로 설명한다.

| 트랙 | 대응 기능 | 8/13 성격 |
|---|---|---|
| Bits Detection 데모 관람 | 감지 자동화 (프리뷰) | 제품 이해 |
| BIO EC2 시나리오 심층 논의 | 조치 자동화 **AI 판단** (프리뷰, EC2 미지원) | 로드맵 협의 |
| Workflow Automation 샌드박스 실습 | 조치 자동화 **대본 실행** (GA) | 실측 |

세 트랙이 왜 성격이 다른지, 왜 어떤 건 실측이고 어떤 건 논의인지는 이 3층 스택 각각의 성숙도·대상 범위 차이에서 나온다.

### 결합의 그림

Bits Detection의 산출물은 **Monitor** 다. 그 Monitor가 발화하면 **Workflow** 로 이어붙여 조치할 수 있다 — 이게 **"Bits + Workflow 조합"**. BIO는 이 조합 전체를 **AI가 대신 판단·실행**하는 상위 레이어. 즉 *"Bits Detection + Workflow"* 를 사람이 이어붙이는 대신 BIO 하나가 담당한다.

그래서 **8/13 미팅의 BIO EC2 시나리오 논의**는 실질적으로 *"Bits+Workflow 조합을 EC2 환경에서 AI로 대체하는 그림을 논의"* 이고, 그 준비 단계로 **Workflow만 먼저 EC2에서 실측**해두는 것이 이 PoC의 실전 트랙이다.

---

## 관련 노트
- [[Datadog PoC — 진행 방향 및 Terraform 준비]] — 이 3개 기능을 검증하기 위한 PoC 인프라 준비물(Terraform)
