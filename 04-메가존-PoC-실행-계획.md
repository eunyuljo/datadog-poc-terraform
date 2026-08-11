---
tags: [datadog, poc, megazone, execution, terraform, chaos]
type: playbook
status: in-progress
meeting: 2026-08-13 09:00
created: 2026-08-11
owner: megazone-msp
aliases:
  - "메가존 PoC 실행 계획"
related:
  - "[[Datadog PoC — 진행 방향 및 Terraform 준비]]"
  - "[[Datadog AI 자율운영 스택 — 3개 기능의 원래 목적]]"
---

# 메가존 PoC 실행 계획

> [!info] 한 줄 요약
> Datadog PoC 에서 **메가존(우리) 측이 실제로 수행하는 일** 을 순서대로 정리한 실행 노트. Datadog 제품 이해는 [[Datadog AI 자율운영 스택 — 3개 기능의 원래 목적]] 에, PoC 전체 진행 방향은 [[Datadog PoC — 진행 방향 및 Terraform 준비]] 에 있다. 이 노트는 그 위에서 **"우리 손에서 굴러가는 것"** 만 다룬다.

---

## 0. 이 PoC의 3주체와 역할 분담

같은 PoC 안에 세 주체가 있고, 담당이 겹치지 않는다. 우리가 신경 써야 할 건 첫 번째 열이다.

| 주체 | 담당 |
|---|---|
| **메가존 MSP팀 (우리)** | 실험 인프라 구축(Terraform), 장애 유발 무대(chaos playground), 시나리오 유발, 시연 준비 |
| **MZC 데이터독팀** | Workflow Automation 자동화 실측(#4 CPU→ASG), 샌드박스 계정 초대 관리, 설정 가이드 배포 |
| **Datadog 제품팀 (PM)** | Bits Detection 데모, BIO EC2 로드맵 협의 |

---

## 1. 이 라운드에서 우리가 만든 것 (완료)

Terraform 저장소(`terraform/`) 에 다음이 코드로 완성되어 있다. 모두 토글 가능.

### 1.1 인프라 뼈대

| 리소스 | 파일 | 토글 |
|---|---|---|
| VPC + 프라이빗 서브넷 2개 (AZ a/c) | `network.tf` | 상시 |
| SSM Interface 엔드포인트 3종 | `network.tf` | `enable_ssm_endpoints` |
| NAT Gateway + IGW + public subnet | `network.tf` | `enable_nat_gateway` |
| Amazon Linux 2023 EC2 (SSM 관리형) | `ec2.tf` | 상시 (`instance_count`) |
| CPU Spike 대상 ASG | `autoscaling.tf` | `enable_autoscaling_target` |

### 1.2 IAM 2역할 분리

| 역할 | 파일 | 목적 |
|---|---|---|
| 역할1 — EC2 인스턴스 프로파일 | `iam_instance.tf` | EC2 가 SSM 관리형 노드로 등록. `AmazonSSMManagedInstanceCore` |
| 역할2 — Datadog 크로스계정 Role | `iam_datadog.tf` | Datadog 이 AssumeRole 로 우리 계정에 진입해 자동조치. External ID 로 confused-deputy 방어 |

역할1은 EC2 부팅과 함께 자동으로 인스턴스에 붙는다. 역할2는 **Datadog 콘솔 > Integrations > AWS** 에 ARN + External ID 를 등록해야 활성화된다.

### 1.3 장애 유발 무대 — Chaos playground

Terraform 이 EC2 부팅 시 자동으로 Flask 앱을 배포한다. 4개 시나리오 유발 엔드포인트 제공.

| 경로 | 파일 |
|---|---|
| Flask 앱 원본 | `terraform/scripts/chaos-app.py` |
| 부트스트랩 스크립트 | `terraform/scripts/user_data.sh.tpl` |
| Terraform 결합 로컬 | `terraform/chaos-app.tf` |

**배포 방식**: user_data 가 `dnf` 로 python3·pip 설치 → **venv 격리 환경**(`/opt/chaos-app/venv`) 에 Flask 설치 → `chaos-app.py` 배치 → systemd 유닛 `chaos-app.service` 등록·기동. 시스템 파이썬을 오염시키지 않고, AL2023 기본 pip 21.x 에서 `--break-system-packages` 미지원 문제도 우회한다.

---

## 2. 커버 가능한 시나리오

메일에서 낸 6개 시나리오 중 **이번 라운드는 4개 실증 무대** 가 완성된 상태.

| # | 시나리오 | 유발 방법 | 이번 라운드 커버 |
|---|---|---|---|
| 1 | 좀비/고아 프로세스 감지 → 자동 kill | `POST /chaos/fork-orphan` | ✅ |
| 2 | 디스크 고갈 → 자동 청소 | `POST /chaos/fill-disk` | ✅ |
| 3 | Memory Leak → OOM 사전 조치 | `POST /chaos/leak-memory` | ✅ |
| 4 | CPU Spike → ASG SetDesiredCapacity | `POST /chaos/cpu-burn` (+ ASG 토글) | ✅ (ASG 활성화 시) |
| 5 | DB Connection 누수 정리 | RDS 필요 | ❌ 다음 라운드 |
| 6 | RDS Slow Query → 스케일업 | RDS 필요 | ❌ 다음 라운드 |

> [!note] RDS 는 왜 이번 라운드에서 뺐는가
> 미팅(8/13) 까지 이틀. RDS 인스턴스 + 시드 데이터 + 앱 DB 로직까지 안정화하는 게 부담. 우선 인프라 시나리오 4개로 실험 무대를 검증하고, RDS 는 미팅 후 안정된 시점에 붙인다.

---

## 3. 지금 `terraform apply` 를 돌리면 만들어지는 상태

현재 `terraform.tfvars` 기준:

```hcl
enable_nat_gateway        = true    # Datadog Agent 다운로드 등 인터넷 아웃바운드
enable_ssm_endpoints      = true    # SSM 통신을 백본으로 유지
enable_autoscaling_target = false   # ASG 는 아직 미생성 (원하면 true)
enable_chaos_app          = true    # chaos playground 자동 배포
datadog_external_id       = "PASTE_REAL_EXTERNAL_ID_HERE"   # ← 실제 값 교체 필요
```

Plan: **27 to add** (VPC/서브넷/IGW/NAT/EIP/SG/RT/EC2/IAM 두 역할/SSM 엔드포인트 3종). `enable_autoscaling_target=true` 로 켜면 ASG 3개 리소스 추가되어 30 to add.

---

## 4. 실험 실행 절차 (Datadog 연결 전 단독 검증)

> [!important] 사전 요구사항 (로컬 도구)
> 아래 절차를 실행하는 머신에 다음이 설치되어 있어야 한다:
> - **AWS CLI** — 프로필/크리덴셜 세팅 완료
> - **Session Manager plugin** — `aws ssm start-session` 이 WebSocket 채널을 유지하는 데 필요 (별도 바이너리)
> - **jq** — Terraform output(JSON) 파싱
> - **terraform** ≥ 1.5
>
> Session Manager plugin 이 없으면 `SessionManagerPlugin is not found` 에러가 뜬다. AWS CLI 는 SSM `StartSession` API 호출까지만 담당하고, 실제 세션의 WebSocket 채널은 이 플러그인 바이너리가 처리하기 때문에 두 개가 다 있어야 한다.
>
> OS 별 설치:
> ```bash
> # Amazon Linux 2023 / RHEL / Fedora
> sudo dnf install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
>
> # Amazon Linux 2 / CentOS 7
> sudo yum install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
>
> # Ubuntu / Debian
> curl -o /tmp/sm.deb https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb \
>   && sudo dpkg -i /tmp/sm.deb
>
> # macOS (Homebrew)
> brew install --cask session-manager-plugin
> ```
> 설치 확인: `session-manager-plugin --version`

### 4.1 배포

```bash
cd terraform
# 필요 시 datadog_external_id 를 실제 값으로 교체
terraform init
terraform plan
terraform apply
```

Apply 완료 후 다음 출력 확인:

```bash
terraform output ec2_instance_ids            # 시나리오 유발 대상 (list)
terraform output datadog_integration_role_arn # Datadog 콘솔에 등록할 ARN
terraform output chaos_app_endpoints          # curl 대상 URL
```

> [!note] user_data 변경 시 재배포
> `terraform/scripts/*` (chaos-app.py, user_data.sh.tpl) 를 수정한 뒤 `terraform apply` 만 돌리면 인스턴스가 replace 되지 않아 새 user_data 가 실행되지 않는다. 명시적으로 강제해야 함:
> ```bash
> terraform apply -replace='aws_instance.poc[0]'
> ```

> [!note] 부팅 후 준비 완료까지 1~2분
> `apply` 완료 시점부터 chaos-app 이 응답하기까지 `dnf install python3-pip` → `python3 -m venv` → `pip install flask` → systemd start 순으로 진행되어 **1~2 분** 소요된다. 준비 상태는 셸 세션에서 `sudo cloud-init status` 가 `status: done` 인지로 확인.

### 4.2 EC2 접속 (Session Manager 포트포워딩)

```bash
# ec2_instance_ids 는 리스트라 -json 으로 뽑아 jq 로 첫 원소 추출
INSTANCE_ID=$(terraform output -json ec2_instance_ids | jq -r '.[0]')

aws ssm start-session --target "$INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8080"],"localPortNumber":["8080"]}'
```

포트포워딩 세션을 유지한 채 다른 터미널에서 curl.

### 4.3 시나리오 유발과 검증

각 시나리오는 **유발(curl) → OS 레벨 검증(EC2 셸)** 순으로 확인한다. Datadog 이 없어도 실제 장애가 재현됨을 눈으로 검증 가능하며, 이후 Datadog 이 붙었을 때 이 지점들이 자동 관측 대상이 된다.

#### 한 눈에 보는 관찰 지점

| 시나리오 | 어디를 보는가 | 성공 판정 |
|---|---|---|
| #3 메모리 누수 | `ps -o rss`, `free -h` | Python RSS 증가, available 감소 |
| #1 좀비/고아 | `ps -o pid,ppid`, `pgrep sleep` | 자식 sleep 프로세스가 남아있음 |
| #2 디스크 고갈 | `df -h /`, `ls /tmp` | 파티션 사용률 상승 |
| #4 CPU spike | `top`, `uptime` | CPU 사용률 지속 100%, load average 상승 |

포트포워딩 세션은 유지하고, 검증은 **별도 SSM 셸 세션** 에서 수행한다:

```bash
aws ssm start-session --target "$INSTANCE_ID"
# 세션 안에서 sudo -i 로 root 전환하면 편함
```

---

#### 시나리오 #3 — 메모리 누수 / OOM 사전 방지

**증상**  
Python 프로세스가 요청받은 만큼 메모리를 할당해 붙잡아 둠. 반복되면 시스템 `available` 이 고갈되고 커널 OOM Killer 가 개입해 프로세스 강제 종료. 실제 운영에서는 서비스 latency 상승, GC 폭주, 반복 재시작으로 이어진다.

**유발**
```bash
curl -X POST 'http://localhost:8080/chaos/leak-memory?mb=200'
```

**검증 (EC2 셸에서)**
```bash
# Python 프로세스의 RSS
ps -o pid,user,rss,vsz,comm -C python
#   RSS ≈ 요청 MB + ~28 MB (인터프리터·Flask 오버헤드)

# 전체 메모리
free -h
#   used 증가, available 감소
```

**OOM 유도까지 밀어보기** (t3.small = 2 GiB 기준 5~8회 누적 시)
```bash
for i in $(seq 1 8); do
  curl -s -X POST 'http://localhost:8080/chaos/leak-memory?mb=200'
done

# EC2 셸에서
dmesg | tail -20                    # oom_reaper 로그
sudo journalctl -u chaos-app -n 30  # systemd 재시작 이력
```

---

#### 시나리오 #1 — 좀비/고아 프로세스

**증상**  
`sleep` 자식 프로세스를 spawn 만 하고 `wait()` 하지 않음. 부모(chaos-app) 가 살아있는 동안은 자식이 chaos-app 아래 매달림. 부모가 죽으면 자식이 PPID=1(systemd) 로 재부모화되어 **진짜 orphan**. 실제 운영에서는 PID 자원 서서히 고갈, `fork()` 실패, 정체불명 프로세스 유령이 문제가 된다.

> [!important] systemd `KillMode=process` 가 전제
> 이 시나리오가 진짜 orphan(PPID=1)을 만들려면 systemd 유닛이 `KillMode=process` 로 설정되어 있어야 한다. 기본값(`control-group`)이면 main PID 가 죽을 때 systemd 가 cgroup 전체를 정리해서 자식이 함께 죽고 orphan 상태가 되지 않는다. 이 저장소의 `user_data.sh.tpl` 은 이미 `KillMode=process` 를 포함하고 있음.

**유발**
```bash
curl -X POST 'http://localhost:8080/chaos/fork-orphan?count=10'
```

**1단계 검증: 자식 상태 (부모 살아있음)**
```bash
CHAOS_PID=$(sudo systemctl show chaos-app --property MainPID --value)
echo "chaos-app PID: $CHAOS_PID"

# 10개 sleep 프로세스가 chaos-app 자식으로 매달림
pgrep -P "$CHAOS_PID" -a

# 상세: PPID = chaos-app PID
ps -o pid,ppid,stat,comm -C sleep
```

**2단계 검증: 진짜 orphan 만들기**
```bash
# chaos-app 만 kill (systemctl stop 아님)
sudo kill -9 "$CHAOS_PID"

# 2~3초 안에 재확인 — systemd 가 재시작하기 전
ps -o pid,ppid,stat,comm -C sleep
# → 모든 sleep 의 PPID 가 1 로 바뀜 = 진짜 orphan
```

이 상태에서:
- 원 chaos-app 은 죽음
- systemd 가 곧 재시작하지만(`Restart=on-failure`), sleep 들은 새 서비스와 무관하게 **살아남음**
- 새 chaos-app 은 자기 `orphan_pids` 리스트가 비어있음 → `/chaos/reset` 을 호출해도 이 orphan 들을 못 찾음

**정리 방법 3가지**

- **A. 수동 kill (운영 인력)**
  ```bash
  sudo pkill -f 'sleep 3600'
  ```
- **B. `/chaos/reset` — 재시작 전에만 유효**
  chaos-app 이 살아있을 때 자기 자식들을 SIGKILL. 재시작 후엔 무효.
- **C. Datadog + BIO/Workflow (미래)**
  orphan 감지 → Workflow 로 SSM SendCommand `pkill` 자동 실행. 시나리오 #1 자동조치의 원본 그림.

**관찰 지점 요약**

| 시점 | ps 로 봐야 할 것 |
|---|---|
| fork-orphan 직후 | sleep 10개, PPID = chaos-app PID |
| chaos-app kill 직후 | sleep 10개, **PPID = 1** ← 이게 진짜 orphan |
| chaos-app 재시작 후 | sleep 10개 여전히 PPID = 1 (새 chaos-app 은 자기 자식 아님) |
| `pkill -f sleep` 후 | sleep 0개 |

---

#### 시나리오 #2 — 디스크 고갈

**증상**  
`/tmp` 에 대용량 파일이 쌓임. 지속되면 파티션 사용률이 임계를 넘고, 앱은 로그·임시 파일 쓰기 실패로 hang 하거나 5xx 반환. 실제 운영에서는 debug 로그 폭주, 배치 결과 파일 누적이 원인.

**유발**
```bash
curl -X POST 'http://localhost:8080/chaos/fill-disk?mb=1000'
```

**검증 (EC2 셸에서)**
```bash
# 생성된 파일들
ls -lh /tmp/chaos-fill-*

# 루트 파티션 사용률
df -h /

# /tmp 총 용량
du -sh /tmp
```

**연속 유발로 사용률 90% 넘기기**
```bash
for i in $(seq 1 5); do
  curl -s -X POST 'http://localhost:8080/chaos/fill-disk?mb=1000'
done
df -h /
```

---

#### 시나리오 #4 — CPU Spike / 스케일 트리거

**증상**  
지정한 threads 수만큼 CPU 100% 소진. load average 상승, 동일 인스턴스의 다른 프로세스(SSM Agent, systemd 등) 응답성 저하. 실제 운영에서는 트래픽 폭주와 동일한 프로파일이며, ASG 스케일 트리거 조건이 된다.

**유발**
```bash
curl -X POST 'http://localhost:8080/chaos/cpu-burn?seconds=60&threads=2'
```

**검증 (EC2 셸에서)**
```bash
# 스냅샷 (헤더 + 상위 프로세스)
top -bn 1 | head -20

# load average 추이 (1/5/15 분)
uptime

# 지속 관찰
top    # q 로 종료
```

t3.small 은 vCPU 2 개이므로 `threads=2` 면 이론상 2 코어 완전 소진. **`enable_autoscaling_target=true`** 로 ASG 를 켜둔 상태에서 유발해야 ASG 스케일 시나리오(#4)의 원본 그림이 재현된다.

---

#### 공용: 상태 조회와 정리

```bash
# 앱이 인지한 현재 상태 (leaked_mb, orphan_pids, disk_files)
curl -s http://localhost:8080/chaos/stats | python3 -m json.tool

# 다음 실험 전 상태 초기화
curl -X POST http://localhost:8080/chaos/reset
```

이 단계에서 EC2 콘솔이나 SSH 없이도 **각 시나리오가 실제로 유발되는지** 확인 가능. Datadog 은 아직 없어도 됨.

### 4.4 트러블슈팅

배포 초기에 부딪히기 쉬운 문제와 대응.

**A. `SessionManagerPlugin is not found`**

로컬에 Session Manager plugin 미설치. §4 상단 `[!important]` 콜아웃의 OS 별 설치 명령 참조. AWS CLI 는 API 호출까지만 담당하고, WebSocket 채널은 이 플러그인이 처리하므로 두 개가 다 있어야 한다.

**B. `Connection to destination port failed, check SSM Agent logs`**

포트포워딩 세션은 열렸지만 EC2 안 8080 에 리스너가 없음. chaos-app 이 아직 안 떴거나 실패. 셸 세션으로 진단:

```bash
aws ssm start-session --target "$INSTANCE_ID"
# 세션 안에서:
sudo cloud-init status                            # status: done 이어야 완료
sudo systemctl status chaos-app                   # active (running) 이어야 정상
sudo tail -100 /var/log/cloud-init-output.log     # 실패 시 원인 여기
```

**C. `curl: (52) Empty reply from server`**

B 와 사실상 동일. SSM 터널은 살아있고 EC2 쪽 포트에 응답 없음. 위 셸 진단으로 서비스 상태 확인.

**D. `Unit chaos-app.service could not be found`**

user_data 가 systemd 유닛 작성 지점 이전에 실패한 상태. 대부분 pip 설치 단계에서 에러. `/var/log/cloud-init-output.log` 마지막 줄 확인. 이번 저장소는 이 문제를 예방하기 위해 **venv 방식** 을 채택했지만, 만약 재발하면 여기서 원인 잡음.

**E. user_data 변경했는데 반영 안 됨**

Terraform 은 user_data 변경만으로는 인스턴스를 replace 하지 않는다:

```bash
terraform apply -replace='aws_instance.poc[0]'
```

**F. `SessionManagerPlugin` 은 있는데 `TargetNotConnected`**

EC2 가 아직 SSM 에 등록되지 않음. 부팅 후 30초~1분 대기. `enable_ssm_endpoints=true` (기본) 라면 프라이빗 서브넷에서도 정상 등록되어야 함.

### 4.5 정리

데모/실험 종료 후:

```bash
terraform destroy
```

NAT Gateway 는 시간당 과금이라 놀리지 말 것.

---

## 5. 다음 라운드 (Datadog 연결)

이 실험 무대 위에 다음을 얹으면 **감지·조치 폐루프 검증** 이 가능해진다. 미팅 이후 순차 진행 예정.

### 5.1 Datadog Agent 설치 (EC2 자동화)
- `ec2.tf` 의 user_data 에 Datadog Agent 원라이너 삽입 (또는 SSM Document 로 분리)
- 변수 `datadog_api_key`, `datadog_site` 신설
- Agent 가 인프라 지표 자동 수집 → 콘솔 관측 가능

### 5.2 APM 계측 (Bits Detection 준비)
- chaos-app.py 에 `ddtrace` 데코레이터 부착
- APM 트레이스 수집 → Bits Detection 활성화 시 서비스 커버리지 대상

### 5.3 Monitor / Workflow 정의
- 콘솔에서 GUI 로 만들거나 `DataDog/datadog` provider 도입해 코드화
- 우선은 **콘솔 GUI** 로 만들어 재현성은 스크린샷·수동 문서화

### 5.4 (선택) RDS 확장
- 시나리오 #5, #6 커버 목적
- 앱 확장(DB 접속 엔드포인트) + RDS 시드 데이터 필요

---

## 6. 미팅 전 액션 아이템 (2026-08-13 기준)

메가존 측에서 회신·준비 필요한 항목:

- [ ] 8/13 미팅 **메가존 참석자 명단** Datadog 측에 회신 (인비 발송용)
- [ ] Datadog 샌드박스(`megazone cloud`) 초대용 **테스트 담당자 이메일 주소** 취합·전달
- [ ] Datadog 담당자에게 **Bits Detection Preview 액세스 활성화** 요청 (조직 단위)
- [ ] `terraform.tfvars` 의 `datadog_external_id` 를 Datadog 통합 화면에서 발급받은 실제 값으로 교체
- [ ] (선택) 실험 무대 dry-run — `terraform apply` → chaos playground 유발 → 각 지표가 EC2 콘솔에서 관측되는지 확인 (Datadog 없이도 이 단계 검증 가능)

---

## 7. 미팅 중 우리가 얻어야 할 것

논의 위주 미팅이라 실측보다 **정보 확보** 가 우선. 미팅 종료 시점에 아래를 손에 쥐어야 한다.

- **Bits Detection Preview** 우리 조직에 언제 열리는지, 지원되는 site (`app.datadoghq.com` / `ap1.datadoghq.com` 등) 확인
- **BIO EC2 지원 로드맵** — 시나리오 #1·#3·#5 를 우리 페인으로 제출했을 때 제품팀 반응. 개략 시점
- **Workflow Automation** 활성화 방법과 우리 샌드박스 상태 확인
- Datadog Slack 연동 프로세스 (Workflow 승인 스텝용)

---

## 8. 미팅 이후 우리가 할 일

미팅 결과에 따라 갈래가 나뉜다.

### 시나리오 A: Bits Detection Preview 우리 조직에 열림
- 5.2 (APM 계측) 우선 진행 → 실측
- 우리 EC2 위 chaos-app 에 트래픽 유발 → Bits Detection 자동 큐레이션 관찰

### 시나리오 B: BIO EC2 지원 로드맵 확인만 되고 개방은 이후
- 5.1 (Datadog Agent 설치) 만 완료
- Workflow Automation 으로 #4 CPU→ASG 시나리오 실측 (MZC 데이터독팀 가이드 기반)
- 나머지 시나리오(#1·#2·#3) 는 콘솔 Monitor + Workflow 조합으로 대체 실측

### 시나리오 C: 전부 이후 (가장 보수적)
- 실험 무대 유지·검증 계속
- 미팅에서 확인한 BIO EC2 오픈 예정일까지 대기하며 논의 자료 정련

---

## 관련 노트

- [[Datadog PoC — 진행 방향 및 Terraform 준비]] — PoC 전체 진행 방향과 인프라 요약
- [[Datadog AI 자율운영 스택 — 3개 기능의 원래 목적]] — Bits Detection / BIO / Workflow Automation 각각이 왜 존재하는가
