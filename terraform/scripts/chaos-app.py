#!/usr/bin/env python3
"""
Chaos playground app for Datadog PoC.

시나리오별 엔드포인트를 호출해 EC2에 실제 장애를 유발한다.
Datadog Agent 가 붙은 뒤 이 유발이 어떻게 감지·복구되는지 관찰하는 무대.

지원 시나리오 (메일 스레드 기준):
    #1 fork-orphan  : Zombie/Orphan 프로세스 감지 및 자동 정리
    #2 fill-disk    : 로그/임시 파일 누적에 따른 디스크 고갈 대응
    #3 leak-memory  : Memory Leak / OOM 사전 방지
    #4 cpu-burn     : CPU Throttling/Spike 발생 시 스케일링 연동

설계 원칙:
    - 각 시나리오는 서로 독립적 (하나가 다른 시나리오의 리소스를 훔치지 않음)
    - 재현 가능성 우선 (파라미터로 크기·시간·개수 지정 가능)
    - 의도적 취약함 (재시작 안전성·thread safety 미보장) — 실운영 페인의 시뮬레이션
"""
import os              # 프로세스 kill, 파일 삭제, 환경변수 접근
import time            # 타임스탬프, CPU burn 종료 시각 계산
import threading       # CPU burn 백그라운드 스레드
import subprocess      # fork-orphan 자식 프로세스 spawn
from flask import Flask, jsonify, request

app = Flask(__name__)

# -----------------------------------------------------------------------------
# 전역 상태 — 의도적으로 모듈 레벨 리스트에 저장
# -----------------------------------------------------------------------------
# 데이터베이스도 클래스도 아닌 파이썬 리스트 3개.
# 이 anti-pattern 은 의도된 것:
#   - 프로세스가 죽으면 상태 사라짐 → 시나리오 #1(orphan) 재현의 핵심 조건.
#     chaos-app 이 죽으면 orphan_pids 리스트도 잃어버려 reset 이 이전 orphan 을
#     찾지 못함 (실운영에서 크래시 후 남은 프로세스를 정리할 주체가 없는
#     상황의 축약판).
#   - 재시작 시 상태 초기화가 자연스러움 (chaos 는 매번 새로 시작).
#   - Flask 개발 서버는 단일 프로세스라 대부분의 요청 처리에서 race 없음.
#     CPU burn 백그라운드 스레드는 이 리스트를 만지지 않음.
# 프로덕션 앱이면 이렇게 짜면 안 되지만, chaos 는 취약함 자체가 특징.
leaked_bytes = []   # #3 메모리 누수용. 각 원소가 chunk bytes.
orphan_pids = []    # #1 spawn 한 자식 프로세스 PID 목록.
disk_files = []     # #2 생성한 임시 파일 경로 목록.


# -----------------------------------------------------------------------------
# Health check
# -----------------------------------------------------------------------------
# ELB/K8s 헬스체크 관행. `/health` 는 사실상 표준 경로.
# Datadog 이 붙었을 때 이 엔드포인트가 service check 대상이 됨.
@app.route("/health")
def health():
    return jsonify(status="ok")


# -----------------------------------------------------------------------------
# 현재 상태 조회 — "앱이 뭘 붙잡고 있나" 를 밖에서 관찰
# -----------------------------------------------------------------------------
# ps·free·df 로 OS 관점 확인하기 전에, 앱 자신의 시각으로 먼저 봄.
@app.route("/chaos/stats")
def stats():
    return jsonify(
        leaked_chunks=len(leaked_bytes),
        # sum(len(b) for b in ...) — 각 bytes 객체의 실제 크기를 바이트 단위로 합산.
        leaked_mb=round(sum(len(b) for b in leaked_bytes) / (1024 * 1024), 1),
        orphan_pids=orphan_pids,
        disk_files=disk_files,
    )


# -----------------------------------------------------------------------------
# #3 Memory leak — 할당만 하고 해제 안 함
# -----------------------------------------------------------------------------
@app.route("/chaos/leak-memory", methods=["POST"])
def leak_memory():
    mb = int(request.args.get("mb", 50))

    # b"x" * N — 1바이트짜리 bytes 를 N번 곱해 정확히 N바이트 객체 생성.
    # bytes 선택 이유(문자열 아님):
    #   - 유니코드 오버헤드 없음 → 크기 예측 가능
    #   - 각 원소가 정확히 1바이트
    # 이 할당은 커널이 즉시 물리 메모리를 잡아줌 (RSS 증가).
    chunk = b"x" * (mb * 1024 * 1024)

    # ★ 리스트가 chunk 를 참조하는 한 파이썬 GC 는 이 메모리를 회수하지 않음.
    # 함수 리턴돼도 지역변수 chunk 는 사라지지만 리스트 참조는 남음 → 누수.
    leaked_bytes.append(chunk)

    total_mb = round(sum(len(b) for b in leaked_bytes) / (1024 * 1024), 1)
    return jsonify(leaked_mb=mb, total_leaked_mb=total_mb)


# -----------------------------------------------------------------------------
# #1 Orphan/zombie 프로세스 — 자식 프로세스를 spawn 하고 reap 안 함
# -----------------------------------------------------------------------------
# 이 함수는 Unix 프로세스 관리의 세밀한 부분을 건드림.
# subprocess.Popen 의 각 옵션이 왜 필요한지가 이 시나리오의 실체.
@app.route("/chaos/fork-orphan", methods=["POST"])
def fork_orphan():
    count = int(request.args.get("count", 5))
    duration = int(request.args.get("duration", 3600))
    spawned = []
    for _ in range(count):
        p = subprocess.Popen(
            # sleep 3600 — 1시간짜리 sleeping 프로세스. 오래 살아있어야 관찰 가능.
            ["sleep", str(duration)],

            # 자식의 3대 표준 스트림을 /dev/null 로 리다이렉트.
            # 부모(Flask 앱)의 stdout/stderr 를 상속하면 자식이 systemd journal
            # 을 오염시키므로 격리. 진짜 daemon 화의 관행.
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,

            # ★ 가장 중요한 옵션 ★
            # Python 내부적으로 setsid() 시스템 콜을 실행.
            # 자식을 새 세션 리더 + 새 프로세스 그룹 리더로 만듦.
            # 효과 3가지:
            #   1) 부모의 controlling terminal 상속 안 함 → 터미널 죽어도 자식 생존
            #   2) 부모가 죽어도 SIGHUP 안 받음 → 자동 정리에서 벗어남
            #   3) cgroup 소속은 여전히 부모 것 (systemd 가 cgroup 정리하면 함께 죽음.
            #      이 저장소는 systemd 유닛에 KillMode=process 로 대응 — user_data.sh.tpl 참조)
            # 위 세 조건이 합쳐져야 부모 죽었을 때 진짜 orphan(PPID=1) 이 됨.
            start_new_session=True,
        )

        # 나중에 /chaos/reset 에서 SIGKILL 보내려고 PID 저장.
        # 주의: chaos-app 이 재시작되면 이 리스트를 잃어버림 → orphan 을 못 찾음.
        # 이 취약함이 곧 실운영 페인(부모 크래시 후 남은 프로세스)의 재현.
        orphan_pids.append(p.pid)
        spawned.append(p.pid)

    # Popen 은 자식 생성만 하고 wait() 하지 않음 → 부모가 자식을 reap 하지 않음.
    # 부모(chaos-app) 가 살아있는 동안은 unwaited children,
    # 부모가 죽으면 PPID=1(systemd) 로 재부모화되어 진짜 orphan.
    return jsonify(spawned=spawned, total_orphans=len(orphan_pids))


# -----------------------------------------------------------------------------
# #2 Disk fill — /tmp 에 대용량 파일 생성
# -----------------------------------------------------------------------------
@app.route("/chaos/fill-disk", methods=["POST"])
def fill_disk():
    mb = int(request.args.get("mb", 500))

    # 파일명에 unix timestamp 삽입 → 여러 번 호출 시 이름 충돌 방지.
    # "chaos-fill-" prefix 는 나중에 `rm /tmp/chaos-fill-*` glob 정리 편의.
    path = f"/tmp/chaos-fill-{int(time.time())}.dat"

    # ★ 1MB 블록을 한 번 만들고 반복 write.
    # 대안(안 쓰는 방식): b"0" * (mb * 1024 * 1024) 로 통째 생성 후 한 번 write
    #   → 이 대안은 mb×MB 만큼 메모리 압박 (특히 시나리오 #3 이 이미 진행됐다면 OOM 위험)
    # 이 방식은 메모리 사용을 1MB 로 상수화 → 디스크·메모리 시나리오 독립성 유지.
    block = b"0" * (1024 * 1024)

    # "wb" = write binary. 텍스트 모드로 열면 인코딩 오버헤드.
    # with 문으로 예외 발생해도 파일 핸들 leak 방지.
    with open(path, "wb") as f:
        for _ in range(mb):
            # 디스크 full 이면 여기서 OSError(Errno 28) 발생.
            # 예외가 이 시점에 나면 아래 disk_files.append(path) 가 실행되지 않아
            # /chaos/reset 이 이 파일을 못 찾음 → 사용자가 수동으로 `rm` 필요.
            # (실운영에서 부분 실패의 그림)
            f.write(block)

    disk_files.append(path)
    return jsonify(path=path, size_mb=mb, total_files=len(disk_files))


# -----------------------------------------------------------------------------
# #4 CPU burn — 지정 시간 동안 CPU 소진 (백그라운드 스레드)
# -----------------------------------------------------------------------------
@app.route("/chaos/cpu-burn", methods=["POST"])
def cpu_burn():
    seconds = int(request.args.get("seconds", 60))
    threads = int(request.args.get("threads", 2))

    # closure: 외부 스코프의 seconds 변수를 참조.
    def burn():
        # 상대적 종료 시각 (지금 + seconds).
        end = time.time() + seconds
        # 순수 파이썬 CPU-bound 계산. 결과를 저장 안 함(_) — 오직 CPU 시간 소모용.
        # sum(i*i for i in range(10000)) 는 GIL 을 놓지 않는 순수 계산.
        while time.time() < end:
            _ = sum(i * i for i in range(10000))

    # 백그라운드 스레드로 실행 → HTTP 응답을 기다리지 않고 즉시 리턴.
    # daemon=True: 메인 프로세스 종료 시 이 스레드도 함께 종료.
    #
    # ★ GIL 의 미묘함 ★
    # 파이썬 GIL 때문에 순수 Python CPU-bound 코드는 threading 으로 진짜 병렬 안 됨.
    # threads=2 로 호출해도 실제로는 GIL 경합으로 CPU 사용률 ~100% (1 코어) 근처.
    # 진짜 200% 를 원하면 multiprocessing 이 필요.
    # 하지만 데모 목적으로는 CPU 지속 사용률과 load average 상승 관찰에 충분.
    for _ in range(threads):
        threading.Thread(target=burn, daemon=True).start()

    return jsonify(burning_for_seconds=seconds, threads=threads)


# -----------------------------------------------------------------------------
# Reset — 데모 iteration 사이에 상태 초기화
# -----------------------------------------------------------------------------
@app.route("/chaos/reset", methods=["POST"])
def reset():
    # 리스트 비우면 chunk 참조 해제 → GC 대상.
    # 다만 즉시는 아님 (GC 사이클 필요). `free -h` 로 available 회복은 몇 초 지연 가능.
    leaked_bytes.clear()

    # list(orphan_pids) — 반복 중 원본 리스트 수정 방지를 위한 스냅샷 복사.
    for pid in list(orphan_pids):
        try:
            # SIGKILL(9) — 자식 강제 종료. SIGTERM(15) 이 아닌 이유:
            # sleep 프로세스가 SIGTERM 을 처리하지 않는 경우가 있어 확실하게 죽이려고.
            os.kill(pid, 9)
        except ProcessLookupError:
            # 자식이 이미 죽어있는 경우 → 정상 케이스로 취급하고 넘어감.
            pass
    orphan_pids.clear()

    for path in list(disk_files):
        try:
            os.remove(path)
        except FileNotFoundError:
            # 파일이 이미 삭제된 경우 (예: OS 재부팅 후 /tmp 초기화) → 정상.
            pass
    disk_files.clear()

    return jsonify(reset=True)


if __name__ == "__main__":
    # PORT 환경변수는 systemd 유닛(user_data.sh.tpl) 에서 주입 (기본 8080).
    # 환경변수는 항상 문자열이라 int() 변환 필요.
    port = int(os.environ.get("PORT", "8080"))

    # host="0.0.0.0" — 모든 네트워크 인터페이스에서 리슨.
    # 기본값(127.0.0.1) 은 로컬 프로세스에서만 접근 가능 → SSM 포트포워딩이 도달하려면
    # 0.0.0.0 이 필수. 프라이빗 서브넷 안이라 외부 노출 걱정 없음.
    #
    # 참고: app.run() 은 Flask 개발 서버. 프로덕션이면 gunicorn/uwsgi 를 써야 하지만
    # PoC 이므로 이대로 사용.
    app.run(host="0.0.0.0", port=port)
