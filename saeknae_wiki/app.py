import os
import uuid
import markdown
from datetime import datetime
from flask import (Flask, render_template, request, redirect, url_for,
                   flash, abort, send_from_directory, jsonify)
from flask_login import LoginManager, login_user, logout_user, login_required, current_user
from werkzeug.utils import secure_filename

from config import Config
from models import db, User, Category, Document, Attachment, Revision

app = Flask(__name__)
app.config.from_object(Config)

db.init_app(app)

login_manager = LoginManager(app)
login_manager.login_view = "login"
login_manager.login_message = "로그인이 필요합니다."
login_manager.login_message_category = "warning"


@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))


def allowed_file(filename):
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    return ext in app.config["ALLOWED_EXTENSIONS"]


def is_image(filename):
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    return ext in {"png", "jpg", "jpeg", "gif", "webp"}


def admin_required(f):
    from functools import wraps
    @wraps(f)
    def decorated(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin:
            abort(403)
        return f(*args, **kwargs)
    return decorated


# ─────────────────────────────────────────────
# 인증
# ─────────────────────────────────────────────
@app.route("/login", methods=["GET", "POST"])
def login():
    if current_user.is_authenticated:
        return redirect(url_for("index"))
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        user = User.query.filter_by(username=username).first()
        if user and user.is_active and user.check_password(password):
            login_user(user, remember=request.form.get("remember"))
            next_page = request.args.get("next")
            return redirect(next_page or url_for("index"))
        flash("아이디 또는 비밀번호가 틀렸습니다.", "danger")
    return render_template("login.html")


@app.route("/logout")
@login_required
def logout():
    logout_user()
    return redirect(url_for("login"))


# ─────────────────────────────────────────────
# 메인 / 검색
# ─────────────────────────────────────────────
@app.route("/")
@login_required
def index():
    categories = Category.query.order_by(Category.name).all()
    recent = Document.query.filter_by(is_public=True).order_by(Document.updated_at.desc()).limit(10).all()
    if current_user.is_admin:
        recent = Document.query.order_by(Document.updated_at.desc()).limit(10).all()
    return render_template("index.html", categories=categories, recent=recent)


@app.route("/search")
@login_required
def search():
    q = request.args.get("q", "").strip()
    results = []
    if q:
        like = f"%{q}%"
        query = Document.query.filter(
            (Document.title.ilike(like)) | (Document.content.ilike(like))
        )
        if not current_user.is_admin:
            query = query.filter_by(is_public=True)
        results = query.order_by(Document.updated_at.desc()).all()
    return render_template("search.html", q=q, results=results)


# ─────────────────────────────────────────────
# 문서 CRUD
# ─────────────────────────────────────────────
@app.route("/doc/new", methods=["GET", "POST"])
@login_required
def doc_new():
    categories = Category.query.order_by(Category.name).all()
    if request.method == "POST":
        title = request.form.get("title", "").strip()
        content = request.form.get("content", "")
        cat_id = request.form.get("category_id") or None
        is_public = request.form.get("is_public", "1") == "1"

        if not title:
            flash("제목을 입력해주세요.", "warning")
            return render_template("doc_edit.html", categories=categories, doc=None)

        doc = Document(
            title=title,
            content=content,
            category_id=cat_id,
            author_id=current_user.id,
            updated_by_id=current_user.id,
            is_public=is_public,
        )
        db.session.add(doc)
        db.session.commit()
        flash("문서가 생성되었습니다.", "success")
        return redirect(url_for("doc_view", doc_id=doc.id))

    return render_template("doc_edit.html", categories=categories, doc=None)


@app.route("/doc/<int:doc_id>")
@login_required
def doc_view(doc_id):
    doc = Document.query.get_or_404(doc_id)
    if not doc.is_public and not current_user.is_admin:
        abort(403)
    html_content = markdown.markdown(
        doc.content,
        extensions=["fenced_code", "tables", "toc", "nl2br", "sane_lists"]
    )
    return render_template("doc_view.html", doc=doc, html_content=html_content)


@app.route("/doc/<int:doc_id>/edit", methods=["GET", "POST"])
@login_required
def doc_edit(doc_id):
    doc = Document.query.get_or_404(doc_id)
    if not doc.is_public and not current_user.is_admin:
        abort(403)
    categories = Category.query.order_by(Category.name).all()

    if request.method == "POST":
        # 수정 이력 저장
        rev = Revision(
            document_id=doc.id,
            content=doc.content,
            edited_by_id=current_user.id,
            edited_at=datetime.utcnow(),
            summary=request.form.get("summary", ""),
        )
        db.session.add(rev)

        doc.title = request.form.get("title", doc.title).strip()
        doc.content = request.form.get("content", doc.content)
        doc.category_id = request.form.get("category_id") or None
        doc.is_public = request.form.get("is_public", "1") == "1"
        doc.updated_by_id = current_user.id
        doc.updated_at = datetime.utcnow()
        db.session.commit()
        flash("문서가 저장되었습니다.", "success")
        return redirect(url_for("doc_view", doc_id=doc.id))

    return render_template("doc_edit.html", categories=categories, doc=doc)


@app.route("/doc/<int:doc_id>/delete", methods=["POST"])
@login_required
@admin_required
def doc_delete(doc_id):
    doc = Document.query.get_or_404(doc_id)
    # 첨부파일 실제 삭제
    for att in doc.attachments:
        path = os.path.join(app.config["UPLOAD_FOLDER"], att.filename)
        if os.path.exists(path):
            os.remove(path)
    db.session.delete(doc)
    db.session.commit()
    flash("문서가 삭제되었습니다.", "success")
    return redirect(url_for("index"))


@app.route("/doc/<int:doc_id>/history")
@login_required
def doc_history(doc_id):
    doc = Document.query.get_or_404(doc_id)
    revisions = Revision.query.filter_by(document_id=doc_id).order_by(Revision.edited_at.desc()).all()
    return render_template("doc_history.html", doc=doc, revisions=revisions)


# ─────────────────────────────────────────────
# 파일 첨부
# ─────────────────────────────────────────────
@app.route("/doc/<int:doc_id>/upload", methods=["POST"])
@login_required
def upload_file(doc_id):
    doc = Document.query.get_or_404(doc_id)
    file = request.files.get("file")
    if not file or file.filename == "":
        return jsonify({"error": "파일을 선택해주세요."}), 400
    if not allowed_file(file.filename):
        return jsonify({"error": "허용되지 않는 파일 형식입니다."}), 400

    original_name = secure_filename(file.filename)
    ext = original_name.rsplit(".", 1)[-1].lower() if "." in original_name else ""
    saved_name = f"{uuid.uuid4().hex}.{ext}"
    save_path = os.path.join(app.config["UPLOAD_FOLDER"], saved_name)
    file.save(save_path)

    att = Attachment(
        document_id=doc.id,
        filename=saved_name,
        original_name=original_name,
        file_size=os.path.getsize(save_path),
        mime_type=file.content_type,
        uploaded_by_id=current_user.id,
    )
    db.session.add(att)
    db.session.commit()

    file_url = url_for("download_file", att_id=att.id)
    return jsonify({
        "id": att.id,
        "name": original_name,
        "url": file_url,
        "is_image": is_image(original_name),
    })


@app.route("/file/<int:att_id>")
@login_required
def download_file(att_id):
    att = Attachment.query.get_or_404(att_id)
    return send_from_directory(app.config["UPLOAD_FOLDER"], att.filename,
                               download_name=att.original_name)


@app.route("/file/<int:att_id>/delete", methods=["POST"])
@login_required
def delete_file(att_id):
    att = Attachment.query.get_or_404(att_id)
    doc_id = att.document_id
    if not current_user.is_admin and att.uploaded_by_id != current_user.id:
        abort(403)
    path = os.path.join(app.config["UPLOAD_FOLDER"], att.filename)
    if os.path.exists(path):
        os.remove(path)
    db.session.delete(att)
    db.session.commit()
    flash("파일이 삭제되었습니다.", "success")
    return redirect(url_for("doc_edit", doc_id=doc_id))


# ─────────────────────────────────────────────
# 카테고리 관리 (관리자)
# ─────────────────────────────────────────────
@app.route("/categories")
@login_required
def categories():
    cats = Category.query.order_by(Category.name).all()
    return render_template("categories.html", cats=cats)


@app.route("/category/new", methods=["POST"])
@login_required
@admin_required
def category_new():
    name = request.form.get("name", "").strip()
    desc = request.form.get("description", "").strip()
    if not name:
        flash("카테고리 이름을 입력해주세요.", "warning")
        return redirect(url_for("categories"))
    if Category.query.filter_by(name=name).first():
        flash("이미 존재하는 카테고리입니다.", "warning")
        return redirect(url_for("categories"))
    db.session.add(Category(name=name, description=desc))
    db.session.commit()
    flash("카테고리가 추가되었습니다.", "success")
    return redirect(url_for("categories"))


@app.route("/category/<int:cat_id>/delete", methods=["POST"])
@login_required
@admin_required
def category_delete(cat_id):
    cat = Category.query.get_or_404(cat_id)
    db.session.delete(cat)
    db.session.commit()
    flash("카테고리가 삭제되었습니다.", "success")
    return redirect(url_for("categories"))


# ─────────────────────────────────────────────
# 사용자 관리 (관리자)
# ─────────────────────────────────────────────
@app.route("/admin/users")
@login_required
@admin_required
def admin_users():
    users = User.query.order_by(User.created_at.desc()).all()
    return render_template("admin_users.html", users=users)


@app.route("/admin/users/new", methods=["POST"])
@login_required
@admin_required
def admin_user_new():
    username = request.form.get("username", "").strip()
    display_name = request.form.get("display_name", "").strip()
    password = request.form.get("password", "")
    role = request.form.get("role", "member")

    if not username or not password or not display_name:
        flash("모든 항목을 입력해주세요.", "warning")
        return redirect(url_for("admin_users"))
    if User.query.filter_by(username=username).first():
        flash("이미 존재하는 아이디입니다.", "warning")
        return redirect(url_for("admin_users"))

    u = User(username=username, display_name=display_name, role=role)
    u.set_password(password)
    db.session.add(u)
    db.session.commit()
    flash(f"사용자 '{display_name}'이 추가되었습니다.", "success")
    return redirect(url_for("admin_users"))


@app.route("/admin/users/<int:user_id>/toggle", methods=["POST"])
@login_required
@admin_required
def admin_user_toggle(user_id):
    user = User.query.get_or_404(user_id)
    if user.id == current_user.id:
        flash("자신의 계정은 비활성화할 수 없습니다.", "warning")
        return redirect(url_for("admin_users"))
    user.is_active = not user.is_active
    db.session.commit()
    state = "활성화" if user.is_active else "비활성화"
    flash(f"'{user.display_name}' 계정이 {state}되었습니다.", "success")
    return redirect(url_for("admin_users"))


@app.route("/admin/users/<int:user_id>/reset_pw", methods=["POST"])
@login_required
@admin_required
def admin_reset_pw(user_id):
    user = User.query.get_or_404(user_id)
    new_pw = request.form.get("new_password", "")
    if len(new_pw) < 4:
        flash("비밀번호는 4자 이상이어야 합니다.", "warning")
        return redirect(url_for("admin_users"))
    user.set_password(new_pw)
    db.session.commit()
    flash(f"'{user.display_name}' 비밀번호가 초기화되었습니다.", "success")
    return redirect(url_for("admin_users"))


# ─────────────────────────────────────────────
# 내 프로필 / 비밀번호 변경
# ─────────────────────────────────────────────
@app.route("/profile", methods=["GET", "POST"])
@login_required
def profile():
    if request.method == "POST":
        current_pw = request.form.get("current_password", "")
        new_pw = request.form.get("new_password", "")
        if not current_user.check_password(current_pw):
            flash("현재 비밀번호가 틀렸습니다.", "danger")
        elif len(new_pw) < 4:
            flash("새 비밀번호는 4자 이상이어야 합니다.", "warning")
        else:
            current_user.set_password(new_pw)
            db.session.commit()
            flash("비밀번호가 변경되었습니다.", "success")
    return render_template("profile.html")


# ─────────────────────────────────────────────
# 초기 데이터 생성
# ─────────────────────────────────────────────
def init_db():
    with app.app_context():
        db.create_all()
        if not User.query.filter_by(username="admin").first():
            admin = User(username="admin", display_name="관리자", role="admin")
            admin.set_password("admin1234")
            db.session.add(admin)
            db.session.add(Category(name="공지사항", description="전사 공지"))
            db.session.add(Category(name="개발", description="개발 문서"))
            db.session.add(Category(name="HR", description="인사 규정"))
            db.session.commit()
            print("초기 관리자 계정 생성: admin / admin1234")


if __name__ == "__main__":
    os.makedirs(Config.UPLOAD_FOLDER, exist_ok=True)
    init_db()
    app.run(host="0.0.0.0", port=5000, debug=False)
