# Datadog Bits AI Demo — 정리 노트

> **미팅**: [Datadog x Megazone Cloud] Bits AI Demo — Detection & Infra Ops
> **일시**: 2026-08-13 (목)
> **참가자**: Patrick Lee (MZC, 진행), Samantha Scaglione (Datadog, Detection PM), Jace Harker (Datadog, InfraOps PM), Whiwon Cho (MZC), AWS MSP 팀 외 다수

---

## 1. 미팅 목적

- MZC CEO의 지시로 **모든 팀이 Datadog · Bits AI를 데일리 워크플로우에 통합**할 방법을 평가 중
- 오늘 세션의 타깃은 **AWS MSP 팀** (Datadog 플랫폼 자체가 처음인 그룹)
- 관리 대상 규모: **약 4,000 hosts**
- 관심 시나리오 6가지 (예: **disk full, zombie process, memory leak** 등)

---

## 2. Bits AI 큰 그림 — Production Operations Loop

Datadog은 운영 사이클을 다음 루프로 정의:

```
[Detection] → [Investigation] → [Action / Remediation] → [Validation] → 반복
```

각 단계에 Bits AI가 붙음:

| 단계 | Bits 기능 | 역할 |
|---|---|---|
| Detection | **Bits Detection** | 액션이 필요한 이슈를 자동 식별 |
| Investigation | **Bits Investigation** | Root cause 자동 분석 |
| Action | **Bits Remediation** | 가드레일 기반의 자동 대응 |

---

## 3. Bits Detection (Samantha 데모)

### 3.1 해결하려는 문제

모니터링의 두 가지 실패 모드:

- **Gap (커버리지 부족)**: 문제가 나는데 알림이 안 옴
- **Noise (알림 과다)**: 액션 불필요한 알림 / 중복 알림 → 팀 신뢰도 붕괴

### 3.2 동작 방식

**A. 자동 모니터 프로비저닝 (Managed Monitor)**

- 시스템을 스캔해 **critical service · resource path** 자동 식별
- 근거 데이터:
  - APM 텔레메트리 (traffic pattern)
  - Service metadata
  - Internal Developer Portal 정보
  - 연동된 integrations
- 임계값은 **historical telemetry + incident response 행동**으로 자동 캘리브레이션
- **1주간 학습 기간** 필요 (신규 서비스도 1주 대기 후 알림 시작)

**B. Triage 레이어 (핵심 차별점)**

전통적 모니터: `threshold breach → 즉시 alert`
Bits Managed Monitor: `threshold breach → Bits triage → 액션 필요 여부 판단 → alert 발화`

Triage에서 하는 일:
- Actionability 판단 (진짜 대응이 필요한가)
- 중복 억제 (사용자 자체 모니터와의 dedup 포함)
- 알림 라우팅 & 옵션 auto-investigation 트리거

**C. 사용자 피드백 채널**

- Endpoint criticality 수동 조정 (추가/제거)
- **BitsChat**에 자연어로 피드백 → Bits가 학습
- Ask Bits 버튼 or `Ctrl + I` 단축키

### 3.3 Bits vs Watchdog

| 항목 | Watchdog | Bits Managed Monitor |
|---|---|---|
| 관점 | 이상치(anomaly) 탐지 | 비즈니스 임팩트 |
| 학습 모델 | Datadog 표준 ML (조직 무관) | 조직별 맞춤 |
| 조직 피드백 반영 | 제한적 | ✅ 시즈널리티 · expected behavior 반영 |

### 3.4 Managed Monitor 편집 규칙

| 항목 | 편집 가능? | 결과 |
|---|---|---|
| Monitor message body | ✅ | Bits 관리 유지 |
| Monitor tags | ✅ | Bits 관리 유지 |
| Monitor title | ❌ | (팀 검토 예정) |
| Threshold | 자연어로 BitsChat에 요청하거나, 편집 시 self-managed로 이탈 |
| Query scope | 편집 시 self-managed monitor로 분리 |

### 3.5 Lifecycle

- 트래픽이 없는 서비스는 약 **1주 후** Managed Monitor 자동 정리
- 단, **doomsday monitor** (거의 안 울리지만 심각 상황용)는 알림 빈도만으로 제거하지 않음

---

## 4. Bits Investigation (간략 데모)

### 4.1 동작 흐름

1. Monitor alert 트리거 시 자동 시작
2. Bits가 **hypothesis set**를 생성 → 각각 검증/기각
3. 사용된 tool call, 참조 telemetry를 모두 노출 (**transparency 강조**)
4. Datadog 외부 데이터도 활용: 예) **GitHub 소스코드 integration**
5. 최종적으로 root cause + 임팩트 타임라인 + **remediation 제안** 도출

### 4.2 Remediation 제안 형태

- Code fix (예: payment rejection gate 이슈)
- Infrastructure provisioning action
- 절차형 스텝
- **Private Action Runner** → 고객 자체 환경에서 액션 실행

### 4.3 학습 요구사항

| 기능 | 학습 기간 |
|---|---|
| Detection | **1주 필수** |
| Investigation | 필요 없음 (시간 지날수록 정밀도 향상) |
| Remediation | 필요 없음 |

> 참고: **Unified Service Tagging** (service/env 태그 일관 적용)이 되어 있으면 Bits가 컨텍스트 조합을 훨씬 잘함.

---

## 5. Bits InfraOps (Jace, 데모 도입부만 확인됨)

### 5.1 컨셉

- 인프라 이슈 전용 **프론트라인 responder**
- 흐름: `Detect → Investigate → Propose fix → Approval → Remediate`
- 사후 재발 방지를 위한 **root cause fix**까지 시도

### 5.2 예시 시나리오 (Disk Pressure)

1. 특정 호스트 디스크가 로그로 가득 참
2. Bits가 어떤 로그가 디스크를 채우는지 조사
3. **로그 truncate**로 즉시 대응
4. 이후 원인 분석 → `log rotate` 미설정 확인
5. 로그 로테이션 설정 변경 → **재발 방지**

> ⚠️ **대본 이 지점에서 종료됨**. Zombie process, Memory leak 등 나머지 시나리오 데모는 확보 필요.

---

## 6. 주요 Q&A 하이라이트

### Q. 모니터 메시지 (troubleshooting 안내)도 Bits가 쓰는가?
- ✅ Bits가 작성. 조직 정책(SLA, 추가 리소스 링크 등)을 위해 편집 가능.
- 응답 시 관련 telemetry를 link. Responder 행동을 학습해 **runbook 품질이 시간이 갈수록 개선**.

### Q. 고객이 이미 유사 모니터를 가진 경우 중복은?
- 여전히 Bits가 모니터 프로비저닝 (방법론이 다를 수 있으므로).
- **Triage 단계에서 dedup**하여 알림 중복 방지.

### Q. 알림 수신자 설정은?
- Managed Monitor 자체엔 recipient 없음.
- **Triage Rule**로 destination 지정 + optional auto-investigation 트리거.

### Q. **모니터를 한국어로 지원할 수 있나?**
- ❌ 현재 영어만. BitsChat은 한국어 대응 가능.
- Samantha가 팀에 가져가서 검토 예정. **타임라인 없음**.

### Q. 모니터 메시지를 템플릿으로 규칙화할 수 있나?
- 현재 개별 편집만 가능, **템플릿화는 로드맵**.
- 근시일 로드맵: `bits.md` 유사 파일로 모니터 governance / message formatting 지시 → 로컬라이제이션도 이 경로에서 해결 검토.

### Q. 커버리지 확장 로드맵?
- 현재: APM 기반 HTTP · gRPC
- 예정: **Front-end / RUM / DEM**, service monitoring 다음은 **Envoy**

### Q. 모니터 생성 한도?
- Bits Managed Monitor는 **표준 monitor limit과 별도**로 관리.
- 단, **Preview 기간엔 최대 100 critical services** 상한.

---

## 7. 액션 아이템

| # | 담당 | 내용 | 상태 |
|---|---|---|---|
| 1 | Samantha (Datadog) | Bits Monitor 다국어(한국어) 지원 팀 내 검토 | Open |
| 2 | MZC | 사용자 설정 가능한 monitor governance / message formatting 로드맵 요구사항 지속 평가 | Open |
| 3 | MZC | InfraOps 데모 뒷부분 (Zombie process / Memory leak) 확보 및 검증 | 필요 |

---

## 8. POC 관점 체크리스트

이 미팅에서 드러난, POC 진행 시 반드시 확인해야 할 항목:

- [ ] **한국어 모니터 미지원** — 운영팀 UX에 미치는 영향 평가 (블로커 후보)
- [ ] **Preview 100 서비스 상한** — 4,000 host 중 우선순위 대상 선정 필요
- [ ] **1주 학습 기간** — POC 스케줄에 반영
- [ ] Managed Monitor 편집 정책 (title 편집 불가 등) 워크어라운드
- [ ] Unified Service Tagging 준비 상태 점검 (Investigation 정확도 직결)
- [ ] Triage Rule 설계 — 알림 destination · auto-investigation 조합
- [ ] InfraOps 관심 시나리오 6가지의 실제 remediation 흐름 검증
- [ ] Private Action Runner 필요 여부 판단 (고객 자체 환경 대응)

---

## 8-1. 미팅에서 놓친 질문 (다음 세션에 확인 필요)

MZC AWS MSP 컨텍스트(4,000 hosts, 다수 end-customer, 한국 규제 환경) 기준으로 이번 미팅에서 다뤄지지 않았지만 POC 진행 전 확답이 필요한 항목.

### 🚨 High — POC 진행 전 확답 필수

- [ ] **멀티테넌시 / 서브 조직 스코핑**
  - Managed monitor · triage rule을 **child org · 팀 단위**로 스코핑 가능한가?
  - Customer A의 피드백 학습이 Customer B에 새어 들어가지 않는지 (학습 격리)
- [ ] **데이터 프라이버시 / LLM 추론 경로**
  - 텔레메트리 · 소스코드(GitHub 연동) · 모니터 컨텍스트가 어느 리전 / 어떤 모델로 전송되는가?
  - 데이터 리텐션, SOC 2 / ISO / KISA 관련 문서
  - 한국 규제(개인정보, 금융 망분리 등) 대응 상태
- [ ] **라이선싱 / 과금 모델**
  - Bits Detection · Investigation · Remediation · InfraOps 각 SKU와 과금 단위 (per host / per investigation / per action)
  - 4,000 hosts 규모의 대략 비용 시나리오
- [ ] **Private Action Runner 상세 (블라스트 라디우스)**
  - 승인 워크플로우 (auto vs manual gate)
  - 실행 IAM · 권한 모델
  - **감사 로그 / 실행 이력 replay**
  - Emergency kill switch, rollback 경로
  - **처리이력 (audit trail) 세부 질문:**
    - [ ] Bits가 실행한 모든 remediation의 **audit log 저장 위치 · 리텐션 · export 포맷** (SIEM 연동 가능?)
    - [ ] **승인 / 거절 / 실행 / 실패 상태 전이**가 이력으로 남는가, 각 이벤트에 actor(사람 or Bits) 태깅되는가
    - [ ] 실행된 액션을 **누가 어떤 권한으로 replay / revert** 할 수 있는가
    - [ ] **한 인시던트당 처리이력 타임라인** 뷰가 UI에 있는가 (Detection → Investigation → Approval → Action → Validation)
    - [ ] 처리이력이 **Datadog Incident Management** 또는 외부 ITSM(ServiceNow 등)과 연동되는가

### ⚠️ Medium — 파일럿 설계 시 필요

- [ ] **Bits 자기 관측성 / 성공 지표** — precision · recall · MTTR 개선 대시보드 내장 여부. "놓친 알림 / 잘못 억제한 알림" 추적 방법.
- [ ] **Dry-run / Observe-only 모드** — POC 초기 shadow mode 지원 여부
- [ ] **Preview → GA 이행 경로** — 100 서비스 상한이 GA에서도 유지되는지, Preview 기간 학습·모니터가 GA로 그대로 이관되는지
- [ ] **APM 없는 워크로드 커버리지** — 배치, cron, DB, legacy, 상용 SW 등. Detection의 사각지대인지, InfraOps가 대체하는지 경계 확인

### 💡 Low — 있으면 좋음

- [ ] **저트래픽 서비스 임계값 신뢰도** — 하루 몇 건 수준 서비스의 캘리브레이션 방식
- [ ] **Investigation 결과물 다국어** — Root cause 리포트가 영어 고정인가?
- [ ] **기존 MZC 자동화(chatops · runbook)와의 통합** — Bits Remediation과의 역할 분담 · 핸드오프 규칙
- [ ] **On-prem / 망분리 고객 지원** — Bits가 SaaS-only인지, Private Action Runner가 gap을 어디까지 메우는지
- [ ] **RBAC / 권한 모델** — Managed monitor 편집 · 삭제 · override 권한의 팀 · 역할 단위 분리

---

## 9. 참고

- **원본 파일**:
  - `[Datadog x Megazone Cloud] Bits AI Demo_ 요약.txt`
  - `[Datadog x Megazone Cloud] Bits AI Demo_ 대본.txt`
- 대본은 **57:51 지점 (Jace InfraOps 데모 도입부)에서 종료**되어 있음 — 이후 내용은 별도 확보 필요.
