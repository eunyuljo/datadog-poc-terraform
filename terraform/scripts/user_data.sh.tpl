#!/bin/bash
# EC2 bootstrap for Datadog PoC chaos playground.
# 이 스크립트는 Terraform templatefile()에 의해 렌더링된다.
# 인터페이스:
#   $${app_port}       — Flask 리슨 포트
#   $${chaos_app_code} — chaos-app.py 의 원본 문자열 (heredoc으로 삽입)
#
# 사전 요구: NAT Gateway 또는 다른 인터넷 아웃바운드 경로.
# (dnf 패키지 저장소와 pip 설치가 인터넷을 필요로 함)
set -euxo pipefail

# --- 런타임 설치 ---
dnf install -y python3 python3-pip

# venv 로 격리 (AL2023 기본 pip 21.x 는 --break-system-packages 미지원).
# 시스템 파이썬을 오염시키지 않고 flask 만 담아 실행한다.
install -d -m 0755 /opt/chaos-app
python3 -m venv /opt/chaos-app/venv
/opt/chaos-app/venv/bin/pip install --quiet flask

# --- 앱 배치 ---
cat > /opt/chaos-app/chaos-app.py <<'CHAOS_APP_EOF'
${chaos_app_code}
CHAOS_APP_EOF
chmod 0755 /opt/chaos-app/chaos-app.py

# --- systemd 등록 ---
cat > /etc/systemd/system/chaos-app.service <<UNIT_EOF
[Unit]
Description=Chaos playground app for Datadog PoC
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PORT=${app_port}
ExecStart=/opt/chaos-app/venv/bin/python /opt/chaos-app/chaos-app.py
Restart=on-failure
RestartSec=5
# 시나리오 #1(orphan) 재현을 위해 main PID 만 정리. 자식 프로세스는 cgroup 정리 대상에서 제외 -> PPID=1 로 재부모화되어 진짜 orphan 이 됨.
KillMode=process

[Install]
WantedBy=multi-user.target
UNIT_EOF

systemctl daemon-reload
systemctl enable --now chaos-app.service
