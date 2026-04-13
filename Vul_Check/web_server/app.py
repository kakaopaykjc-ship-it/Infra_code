from flask import Flask, render_template, request, jsonify, abort
from models import db, Server, CheckRun, CheckItem
from datetime import datetime
import config

app = Flask(__name__)
app.config.from_object(config)
db.init_app(app)

with app.app_context():
    db.create_all()


# ──────────────────────────────────────────────
# 웹 라우트
# ──────────────────────────────────────────────

@app.route("/")
def dashboard():
    servers = Server.query.order_by(Server.last_check_at.desc()).all()
    # 전체 요약 통계
    total_vuln = 0
    total_check = 0
    for s in servers:
        run = s.latest_run
        if run:
            total_vuln  += run.vuln_cnt
            total_check += run.check_cnt

    return render_template(
        "dashboard.html",
        servers=servers,
        total_servers=len(servers),
        total_vuln=total_vuln,
        total_check=total_check,
    )


@app.route("/server/<int:server_id>")
def server_detail(server_id):
    server = Server.query.get_or_404(server_id)
    run    = server.latest_run
    items  = []
    if run:
        items = CheckItem.query.filter_by(run_id=run.id).all()

    vuln_items  = [i for i in items if i.result == "취약"]
    check_items = [i for i in items if i.result == "체크필요"]
    good_items  = [i for i in items if i.result == "양호"]

    return render_template(
        "server_detail.html",
        server=server,
        run=run,
        vuln_items=vuln_items,
        check_items=check_items,
        good_items=good_items,
    )


# ──────────────────────────────────────────────
# API 라우트 (에이전트 → 관리 서버)
# ──────────────────────────────────────────────

def _require_api_key():
    key = request.headers.get("X-API-Key", "")
    if key != app.config["API_KEY"]:
        abort(401, "Invalid API Key")


@app.route("/api/report", methods=["POST"])
def receive_report():
    """에이전트가 점검 결과를 POST 하는 엔드포인트"""
    _require_api_key()

    data = request.get_json(silent=True)
    if not data:
        abort(400, "JSON body required")

    hostname = data.get("hostname", "unknown")
    os_type  = data.get("os", "linux")
    ip       = data.get("ip", "")
    results  = data.get("results", [])

    # 서버 등록 or 업데이트
    server = Server.query.filter_by(hostname=hostname).first()
    if not server:
        server = Server(hostname=hostname, os_type=os_type, ip=ip)
        db.session.add(server)
    else:
        server.ip            = ip
        server.os_type       = os_type
        server.last_check_at = datetime.utcnow()

    db.session.flush()

    # 카운트
    good_cnt  = sum(1 for r in results if r.get("result") == "양호")
    vuln_cnt  = sum(1 for r in results if r.get("result") == "취약")
    check_cnt = sum(1 for r in results if r.get("result") == "체크필요")

    run = CheckRun(
        server_id=server.id,
        check_time=datetime.utcnow(),
        good_cnt=good_cnt,
        vuln_cnt=vuln_cnt,
        check_cnt=check_cnt,
        total_cnt=len(results),
    )
    db.session.add(run)
    db.session.flush()

    for r in results:
        db.session.add(CheckItem(
            run_id=run.id,
            code=r.get("code", ""),
            name=r.get("name", ""),
            result=r.get("result", ""),
            detail=r.get("detail", ""),
        ))

    db.session.commit()
    return jsonify({"status": "ok", "run_id": run.id, "total": len(results)})


@app.route("/api/servers")
def api_servers():
    _require_api_key()
    servers = Server.query.all()
    out = []
    for s in servers:
        run = s.latest_run
        out.append({
            "id": s.id, "hostname": s.hostname, "os": s.os_type, "ip": s.ip,
            "last_check": s.last_check_at.isoformat() if s.last_check_at else None,
            "vuln_cnt": run.vuln_cnt if run else 0,
            "good_cnt": run.good_cnt if run else 0,
            "check_cnt": run.check_cnt if run else 0,
        })
    return jsonify(out)


if __name__ == "__main__":
    app.run(host=config.HOST, port=config.PORT, debug=False)
