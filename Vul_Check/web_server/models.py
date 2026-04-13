from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

db = SQLAlchemy()


class Server(db.Model):
    """점검 대상 서버"""
    id             = db.Column(db.Integer, primary_key=True)
    hostname       = db.Column(db.String(100), unique=True, nullable=False)
    os_type        = db.Column(db.String(20),  nullable=False)   # linux | windows
    ip             = db.Column(db.String(50),  default="")
    last_check_at  = db.Column(db.DateTime,    default=datetime.utcnow)
    runs           = db.relationship("CheckRun", backref="server",
                                     lazy=True, cascade="all, delete-orphan")

    @property
    def latest_run(self):
        return (CheckRun.query
                .filter_by(server_id=self.id)
                .order_by(CheckRun.check_time.desc())
                .first())


class CheckRun(db.Model):
    """한 번의 점검 실행 결과 요약"""
    id         = db.Column(db.Integer, primary_key=True)
    server_id  = db.Column(db.Integer, db.ForeignKey("server.id"), nullable=False)
    check_time = db.Column(db.DateTime, default=datetime.utcnow)
    good_cnt   = db.Column(db.Integer, default=0)
    vuln_cnt   = db.Column(db.Integer, default=0)
    check_cnt  = db.Column(db.Integer, default=0)
    total_cnt  = db.Column(db.Integer, default=0)
    items      = db.relationship("CheckItem", backref="run",
                                  lazy=True, cascade="all, delete-orphan")

    @property
    def vuln_rate(self):
        if self.total_cnt == 0:
            return 0
        return round(self.vuln_cnt / self.total_cnt * 100, 1)

    @property
    def good_rate(self):
        if self.total_cnt == 0:
            return 0
        return round(self.good_cnt / self.total_cnt * 100, 1)


class CheckItem(db.Model):
    """개별 점검 항목"""
    id     = db.Column(db.Integer, primary_key=True)
    run_id = db.Column(db.Integer, db.ForeignKey("check_run.id"), nullable=False)
    code   = db.Column(db.String(20))
    name   = db.Column(db.String(200))
    result = db.Column(db.String(20))   # 양호 | 취약 | 체크필요
    detail = db.Column(db.Text, default="")
