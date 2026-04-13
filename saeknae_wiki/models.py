from datetime import datetime
from flask_sqlalchemy import SQLAlchemy
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash

db = SQLAlchemy()


class User(UserMixin, db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False)
    display_name = db.Column(db.String(64), nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    role = db.Column(db.String(16), default="member")  # "admin" | "member"
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    is_active = db.Column(db.Boolean, default=True)

    documents = db.relationship("Document", backref="author", lazy=True, foreign_keys="Document.author_id")

    def set_password(self, pw):
        self.password_hash = generate_password_hash(pw)

    def check_password(self, pw):
        return check_password_hash(self.password_hash, pw)

    @property
    def is_admin(self):
        return self.role == "admin"


class Category(db.Model):
    __tablename__ = "categories"

    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(64), unique=True, nullable=False)
    description = db.Column(db.String(256))
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    documents = db.relationship("Document", backref="category", lazy=True)


class Document(db.Model):
    __tablename__ = "documents"

    id = db.Column(db.Integer, primary_key=True)
    title = db.Column(db.String(256), nullable=False)
    content = db.Column(db.Text, nullable=False, default="")
    category_id = db.Column(db.Integer, db.ForeignKey("categories.id"), nullable=True)
    author_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=False)
    updated_by_id = db.Column(db.Integer, db.ForeignKey("users.id"), nullable=True)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    is_public = db.Column(db.Boolean, default=True)  # False = 관리자만

    updated_by = db.relationship("User", foreign_keys=[updated_by_id])
    attachments = db.relationship("Attachment", backref="document", lazy=True, cascade="all, delete-orphan")
    revisions = db.relationship("Revision", backref="document", lazy=True, cascade="all, delete-orphan")


class Attachment(db.Model):
    __tablename__ = "attachments"

    id = db.Column(db.Integer, primary_key=True)
    document_id = db.Column(db.Integer, db.ForeignKey("documents.id"), nullable=False)
    filename = db.Column(db.String(256), nullable=False)   # 저장된 실제 파일명
    original_name = db.Column(db.String(256), nullable=False)  # 업로드한 원본명
    file_size = db.Column(db.Integer)
    mime_type = db.Column(db.String(64))
    uploaded_by_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    uploaded_at = db.Column(db.DateTime, default=datetime.utcnow)

    uploaded_by = db.relationship("User", foreign_keys=[uploaded_by_id])


class Revision(db.Model):
    """문서 수정 이력"""
    __tablename__ = "revisions"

    id = db.Column(db.Integer, primary_key=True)
    document_id = db.Column(db.Integer, db.ForeignKey("documents.id"), nullable=False)
    content = db.Column(db.Text, nullable=False)
    edited_by_id = db.Column(db.Integer, db.ForeignKey("users.id"))
    edited_at = db.Column(db.DateTime, default=datetime.utcnow)
    summary = db.Column(db.String(256))

    edited_by = db.relationship("User", foreign_keys=[edited_by_id])
