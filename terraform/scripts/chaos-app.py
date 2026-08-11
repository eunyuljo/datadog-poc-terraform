#!/usr/bin/env python3
"""
Chaos playground app for Datadog PoC.

시나리오별 엔드포인트를 호출해 EC2에 실제 장애를 유발한다.
Datadog Agent가 붙은 뒤 이 유발이 어떻게 감지·복구되는지 관찰하는 무대.

지원 시나리오 (메일 스레드 기준):
    #1 fork-orphan  : Zombie/Orphan 프로세스 감지 및 자동 정리
    #2 fill-disk    : 로그/임시 파일 누적에 따른 디스크 고갈 대응
    #3 leak-memory  : Memory Leak / OOM 사전 방지
    #4 cpu-burn     : CPU Throttling/Spike 발생 시 스케일링 연동
"""
import os
import time
import threading
import subprocess
from flask import Flask, jsonify, request

app = Flask(__name__)

# --- 유발된 상태 (프로세스가 살아있는 동안 누적) ---
leaked_bytes = []   # #3
orphan_pids = []    # #1
disk_files = []     # #2


@app.route("/health")
def health():
    return jsonify(status="ok")


@app.route("/chaos/stats")
def stats():
    return jsonify(
        leaked_chunks=len(leaked_bytes),
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
    chunk = b"x" * (mb * 1024 * 1024)
    leaked_bytes.append(chunk)
    total_mb = round(sum(len(b) for b in leaked_bytes) / (1024 * 1024), 1)
    return jsonify(leaked_mb=mb, total_leaked_mb=total_mb)


# -----------------------------------------------------------------------------
# #1 Orphan/zombie 프로세스 — 자식 프로세스를 spawn 하고 reap 안 함
# -----------------------------------------------------------------------------
@app.route("/chaos/fork-orphan", methods=["POST"])
def fork_orphan():
    count = int(request.args.get("count", 5))
    duration = int(request.args.get("duration", 3600))
    spawned = []
    for _ in range(count):
        p = subprocess.Popen(
            ["sleep", str(duration)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        orphan_pids.append(p.pid)
        spawned.append(p.pid)
    return jsonify(spawned=spawned, total_orphans=len(orphan_pids))


# -----------------------------------------------------------------------------
# #2 Disk fill — /tmp 에 대용량 파일 생성
# -----------------------------------------------------------------------------
@app.route("/chaos/fill-disk", methods=["POST"])
def fill_disk():
    mb = int(request.args.get("mb", 500))
    path = f"/tmp/chaos-fill-{int(time.time())}.dat"
    block = b"0" * (1024 * 1024)  # 1MB
    with open(path, "wb") as f:
        for _ in range(mb):
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

    def burn():
        end = time.time() + seconds
        while time.time() < end:
            _ = sum(i * i for i in range(10000))

    for _ in range(threads):
        threading.Thread(target=burn, daemon=True).start()
    return jsonify(burning_for_seconds=seconds, threads=threads)


# -----------------------------------------------------------------------------
# Reset — 데모 iteration 사이에 상태 초기화
# -----------------------------------------------------------------------------
@app.route("/chaos/reset", methods=["POST"])
def reset():
    leaked_bytes.clear()
    for pid in list(orphan_pids):
        try:
            os.kill(pid, 9)
        except ProcessLookupError:
            pass
    orphan_pids.clear()
    for path in list(disk_files):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    disk_files.clear()
    return jsonify(reset=True)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    app.run(host="0.0.0.0", port=port)
