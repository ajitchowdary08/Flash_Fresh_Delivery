from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import jwt
try:
    from jwt.exceptions import PyJWTError as JWTError
except ImportError:
    from jose import JWTError  # type: ignore
from sqlalchemy.orm import Session
from typing import Dict, Any, Optional

from app.database.db import get_db
from app.models.models import User
from app.services.otp_service import otp_service
from app.core.config import settings

security = HTTPBearer(auto_error=False)


def _decode_token(token: str) -> Optional[Dict[str, Any]]:
    """
    Decodes and verifies a JWT. Returns the payload (sub, phone, role) on success,
    None on any failure. Always uses the authoritative JWT_SECRET_KEY from settings.
    """
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY,
            algorithms=[settings.JWT_ALGORITHM],
        )
        if not payload.get("sub"):
            return None
        return payload
    except JWTError:
        return None


def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    """
    Validates the JWT Bearer token for protected customer endpoints.
    - Production: a valid, non-expired Bearer token is MANDATORY.
    - Development: an absent token resolves to a guest user so the app can be tested
      end-to-end without forcing a login, but a PRESENT-but-INVALID token is always rejected.
    Resolves the underlying User row from the DB so the caller has an authoritative identity.
    """
    if not credentials:
        if settings.ENVIRONMENT == "production":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authentication required. Please provide a valid Bearer token.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return {"sub": "usr_guest_local", "phone": "9876543210", "role": "CUSTOMER"}

    payload = _decode_token(credentials.credentials)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired JWT authentication token. Please re-authenticate.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id = payload.get("sub")
    db_user = db.query(User).filter(User.id == user_id).first()
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User record not found in database.",
        )

    return {**payload, "user": db_user}


def get_current_rider(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> Dict[str, Any]:
    """
    Validates the JWT Bearer token for delivery rider endpoints.
    Requires role RIDER or ADMIN; a guest token is rejected in production.
    """
    if not credentials:
        if settings.ENVIRONMENT == "production":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Rider authorization required.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return {"sub": "rdr_ravi_01", "phone": "9848012345", "role": "RIDER"}

    payload = _decode_token(credentials.credentials)
    if not payload or payload.get("role") not in ["RIDER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: Rider authentication required.",
        )
    return payload


def get_current_store_manager(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
) -> Dict[str, Any]:
    """
    Validates the JWT Bearer token for Dark Store Hub Manager & Admin operations.
    Requires role STORE_MANAGER or ADMIN; a guest token is rejected in production.
    """
    if not credentials:
        if settings.ENVIRONMENT == "production":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Dark store manager authorization required.",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return {"sub": "mgr_miyapur_01", "phone": "9000011111", "role": "STORE_MANAGER"}

    payload = _decode_token(credentials.credentials)
    if not payload or payload.get("role") not in ["STORE_MANAGER", "ADMIN"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: Dark Store Hub Manager authority required.",
        )
    return payload


otp_service.verify_jwt_token = _decode_token
