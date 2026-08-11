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

# AL2023 는 PEP 668 로 시스템 파이썬을 보호. --break-system-packages 로 우회.
pip3 install --break-system-packages flask

# --- 앱 배치 ---
install -d -m 0755 /opt/chaos-app
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
ExecStart=/usr/bin/python3 /opt/chaos-app/chaos-app.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT_EOF

systemctl daemon-reload
systemctl enable --now chaos-app.service
