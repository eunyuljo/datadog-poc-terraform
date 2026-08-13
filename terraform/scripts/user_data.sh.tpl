#!/bin/bash
# EC2 bootstrap. Terraform templatefile() 로 렌더링. 인자 정의는 chaos-app.tf 참조.
# 사전 요구: NAT Gateway (dnf/pip/DD Agent installer 가 인터넷 필요).
set -euxo pipefail

# --- 런타임 설치 ---
dnf install -y python3 python3-pip curl

# venv 로 격리 (AL2023 기본 pip 21.x 는 --break-system-packages 미지원).
install -d -m 0755 /opt/chaos-app
python3 -m venv /opt/chaos-app/venv
/opt/chaos-app/venv/bin/pip install --quiet flask

# --- ddtrace (APM 계측 라이브러리) ---
%{ if dd_enabled ~}
/opt/chaos-app/venv/bin/pip install --quiet ddtrace
%{ endif ~}

# --- Datadog Agent 설치 ---
# 공식 install script 사용. API key 는 user_data 에 평문으로 남음 —
# 프로덕션 이전 시 SSM Parameter Store / Secrets Manager 로 이관 필요.
%{ if dd_enabled ~}
DD_API_KEY="${dd_api_key}" \
DD_SITE="${dd_site}" \
DD_ENV="${dd_env}" \
DD_APM_INSTRUMENTATION_ENABLED=host \
bash -c "$(curl -L https://install.datadoghq.com/scripts/install_script_agent7.sh)"

# APM 활성화 보장 (install script 가 이미 켰다면 no-op).
if ! grep -q '^apm_config:' /etc/datadog-agent/datadog.yaml; then
  cat >> /etc/datadog-agent/datadog.yaml <<'APM_EOF'

apm_config:
  enabled: true
APM_EOF
fi

# Unified Service Tagging.
mkdir -p /etc/datadog-agent/datadog.yaml.d
cat > /etc/datadog-agent/datadog.yaml.d/tags.yaml <<TAGS_EOF
tags:
  - env:${dd_env}
  - service:${dd_service}
  - version:${dd_version}
TAGS_EOF

systemctl restart datadog-agent || true
%{ endif ~}

# --- 앱 배치 ---
# chaos-app.py 는 gzip+base64 로 압축된 상태로 전달됨 (user_data 16KB 한도 회피).
# base64 -d | gunzip 으로 복원.
echo "${chaos_app_code_b64gz}" | base64 -d | gunzip > /opt/chaos-app/chaos-app.py
chmod 0755 /opt/chaos-app/chaos-app.py

# --- systemd 등록: chaos-app ---
cat > /etc/systemd/system/chaos-app.service <<UNIT_EOF
[Unit]
Description=Chaos playground app for Datadog PoC
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PORT=${app_port}
%{ if dd_enabled ~}
Environment=DD_SERVICE=${dd_service}
Environment=DD_ENV=${dd_env}
Environment=DD_VERSION=${dd_version}
Environment=DD_LOGS_INJECTION=true
Environment=DD_TRACE_SAMPLE_RATE=1.0
Environment=DD_AGENT_HOST=127.0.0.1
Environment=DD_TRACE_AGENT_PORT=8126
ExecStart=/opt/chaos-app/venv/bin/ddtrace-run /opt/chaos-app/venv/bin/python /opt/chaos-app/chaos-app.py
%{ else ~}
ExecStart=/opt/chaos-app/venv/bin/python /opt/chaos-app/chaos-app.py
%{ endif ~}
Restart=on-failure
RestartSec=5
# 시나리오 #1(orphan) 재현을 위해 main PID 만 정리. 자식 프로세스는 cgroup 정리 대상에서
# 제외 -> PPID=1 로 재부모화되어 진짜 orphan 이 됨.
KillMode=process

[Install]
WantedBy=multi-user.target
UNIT_EOF

systemctl daemon-reload
systemctl enable --now chaos-app.service

# --- 트래픽 제너레이터 ---
# chaos-app 이 뜬 뒤 시작. 시간대별로 다른 RPS 로 /api/* 를 두들겨서
# Bits Detection 이 학습할 "정상 트래픽 프로파일" 을 만든다.
%{ if tg_enabled ~}
cat > /opt/chaos-app/traffic-gen.sh <<'TG_SCRIPT_EOF'
#!/bin/bash
# 시간대별 RPS 배수 (UTC): 야간(0-6)=1x, 새벽(7-9)=2x, 주간(10-18)=4x, 저녁(19-23)=2x.
# Bits 는 이 반복 패턴을 시즈널리티로 학습한다.
set -u
BASE_RPS="$${BASE_RPS:-2}"
APP_PORT="$${APP_PORT:-8080}"

# chaos-app 준비 대기. 부팅 직후 connection refused 스팸 방지.
for _ in $(seq 1 30); do
  if curl -s -m 2 -o /dev/null "http://127.0.0.1:$${APP_PORT}/health"; then
    break
  fi
  sleep 2
done

# 엔드포인트별 호출 비율 — read 가 write 보다 훨씬 많은 실제 웹서비스 프로파일.
ENDPOINTS=(
  "GET /api/products"
  "GET /api/products"
  "GET /api/products"
  "GET /api/products/3"
  "GET /api/products/12"
  "GET /api/products/27"
  "GET /api/products/999"
  "GET /api/orders"
  "GET /api/orders"
  "GET /api/orders/1002"
  "GET /api/orders/1003"
  "GET /api/orders/9999"
  "POST /api/checkout"
  "GET /health"
)

while true; do
  HOUR=$(date -u +%H)
  case "$${HOUR}" in
    00|01|02|03|04|05|06) MULT=1 ;;
    07|08|09) MULT=2 ;;
    10|11|12|13|14|15|16|17|18) MULT=4 ;;
    19|20|21|22|23) MULT=2 ;;
    *) MULT=1 ;;
  esac
  RPS=$(( BASE_RPS * MULT ))
  for _ in $(seq 1 $${RPS}); do
    IDX=$(( RANDOM % $${#ENDPOINTS[@]} ))
    ENTRY="$${ENDPOINTS[$IDX]}"
    METHOD=$(echo "$${ENTRY}" | awk '{print $1}')
    RPATH=$(echo "$${ENTRY}" | awk '{print $2}')
    curl -s -o /dev/null -m 5 -X "$${METHOD}" "http://127.0.0.1:$${APP_PORT}$${RPATH}" &
  done
  wait
  sleep 1
done
TG_SCRIPT_EOF
chmod 0755 /opt/chaos-app/traffic-gen.sh

cat > /etc/systemd/system/chaos-traffic.service <<TG_UNIT_EOF
[Unit]
Description=Traffic generator for chaos-app (baseline for Bits Detection learning)
After=chaos-app.service
Requires=chaos-app.service

[Service]
Type=simple
Environment=BASE_RPS=${tg_base_rps}
Environment=APP_PORT=${app_port}
ExecStart=/opt/chaos-app/traffic-gen.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
TG_UNIT_EOF

systemctl daemon-reload
systemctl enable --now chaos-traffic.service
%{ endif ~}
