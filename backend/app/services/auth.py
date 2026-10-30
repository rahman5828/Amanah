from sqlalchemy import select
from sqlalchemy.orm import Session
from app.core.security import hash_password, verify_password, create_access_token

from app.models.user import User
from app.schemas.auth import UserRegister
from app.core.security import hash_password


def get_user_by_email(db: Session, email: str) -> User | None:
    statement = select(User).where(User.email == email.lower())
    return db.scalar(statement)


def register_user(db: Session, user_data: UserRegister) -> User:
    user = User(
        full_name=user_data.full_name.strip(),
        email=str(user_data.email).lower(),
        password_hash=hash_password(user_data.password),
    )

    db.add(user)
    db.commit()
    db.refresh(user)

    return user

def authenticate_user(
    db: Session,
    email: str,
    password: str,
) -> User | None:
    user = get_user_by_email(db, email.lower())

    if user is None:
        return None

    if not verify_password(password, user.password_hash):
        return None

    return user