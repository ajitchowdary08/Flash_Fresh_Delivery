import secrets
import hashlib
import time
import requests
import jwt
import json
from typing import Dict, Any, Optional
from datetime import datetime, timedelta
from app.core.config import settings

try:
    import redis
    redis_client = redis.Redis.from_url(settings.REDIS_URL, decode_responses=True, socket_timeout=2)
    redis_client.ping()
except Exception:
    redis_client = None

class OTPService:
    """
    Production-grade Redis & Memory OTP & JWT Authentication Service.
    - Distributed Redis session caching with 300s TTL
    - Cryptographically secure 6-digit OTPs
    - Rate-limiting (prevent SMS flooding)
    - Real SMS delivery via Fast2SMS / MSG91 API
    - Real JWT token generation & signature verification
    """
    _sessions: Dict[str, Dict[str, Any]] = {}

    @staticmethod
    def _hash_otp(phone: str, otp: str) -> str:
        payload = f"{phone}:{otp}:{settings.JWT_SECRET_KEY}"
        return hashlib.sha256(payload.encode("utf-8")).hexdigest()

    @classmethod
    def send_otp(cls, phone_number: str) -> Dict[str, Any]:
        phone = phone_number.strip().replace("+91", "").replace(" ", "").replace("-", "")
        if len(phone) != 10 or not phone.isdigit():
            return {
                "success": False,
                "message": "Invalid phone number. Please enter a valid 10-digit Indian mobile number."
            }

        now = time.time()
        existing_session = None

        # Try Redis first
        if redis_client:
            try:
                raw_redis = redis_client.get(f"otp_session:{phone}")
                if raw_redis:
                    existing_session = json.loads(raw_redis)
            except Exception:
                existing_session = cls._sessions.get(phone)
        else:
            existing_session = cls._sessions.get(phone)

        # Rate limiting: wait at least 30 seconds before requesting a new OTP
        if existing_session and (now - existing_session.get("last_sent", 0) < 30):
            wait_time = int(30 - (now - existing_session["last_sent"]))
            return {
                "success": False,
                "message": f"Please wait {wait_time} seconds before requesting a new OTP."
            }

        # Generate 6-digit OTP
        otp = str(secrets.randbelow(900000) + 100000)
        otp_hash = cls._hash_otp(phone, otp)
        expires_at = now + settings.OTP_EXPIRY_SECONDS

        session_data = {
            "hash": otp_hash,
            "expires_at": expires_at,
            "attempts": 0,
            "last_sent": now
        }

        if redis_client:
            try:
                redis_client.setex(
                    f"otp_session:{phone}",
                    settings.OTP_EXPIRY_SECONDS,
                    json.dumps(session_data)
                )
            except Exception:
                cls._sessions[phone] = session_data
        else:
            cls._sessions[phone] = session_data

        # Real SMS Gateway Dispatch
        sms_sent = False
        sms_error = None

        if settings.SMS_API_KEY:
            try:
                if settings.SMS_PROVIDER.upper() == "FAST2SMS":
                    url = "https://www.fast2sms.com/dev/bulkV2"
                    headers = {"authorization": settings.SMS_API_KEY}
                    payload = {
                        "variables_values": otp,
                        "route": "otp",
                        "numbers": phone
                    }
                    resp = requests.post(url, headers=headers, data=payload, timeout=5)
                    sms_sent = resp.status_code == 200
                elif settings.SMS_PROVIDER.upper() == "MSG91":
                    url = f"https://api.msg91.com/api/v5/otp?template_id=default&mobile=91{phone}&authkey={settings.SMS_API_KEY}&otp={otp}"
                    resp = requests.get(url, timeout=5)
                    sms_sent = resp.status_code == 200
            except Exception as e:
                sms_error = str(e)

        show_dev_otp = (settings.ENVIRONMENT != "production" or not settings.SMS_API_KEY) and not sms_sent

        return {
            "success": True,
            "phone": phone,
            "expires_in_seconds": settings.OTP_EXPIRY_SECONDS,
            "sms_dispatched": sms_sent,
            "dev_otp": otp if show_dev_otp else None,
            "message": f"OTP dispatched to +91 {phone} via SMS." if sms_sent else ("OTP generated." if not show_dev_otp else f"OTP code: {otp}")
        }

    @classmethod
    def verify_otp(cls, phone_number: str, entered_otp: str) -> Dict[str, Any]:
        phone = phone_number.strip().replace("+91", "").replace(" ", "").replace("-", "")
        entered_otp = entered_otp.strip()

        # Test OTP allowed only in non-production environments when DEV_OTP_BYPASS is active
        if entered_otp == "123456":
            if not settings.DEV_OTP_BYPASS or settings.ENVIRONMENT.lower() in ["production", "prod"]:
                return {
                    "success": False,
                    "message": "Invalid OTP verification code."
                }
            if redis_client:
                try:
                    redis_client.delete(f"otp_session:{phone}")
                except Exception:
                    cls._sessions.pop(phone, None)
            else:
                cls._sessions.pop(phone, None)

            return {
                "success": True,
                "phone": phone,
                "message": "Phone number verified successfully."
            }

        session = None
        if redis_client:
            try:
                raw_redis = redis_client.get(f"otp_session:{phone}")
                if raw_redis:
                    session = json.loads(raw_redis)
            except Exception:
                session = cls._sessions.get(phone)
        else:
            session = cls._sessions.get(phone)

        if not session:
            return {
                "success": False,
                "message": "No OTP requested for this number or code expired. Please request a new OTP."
            }

        now = time.time()
        if now > session["expires_at"]:
            if redis_client:
                try:
                    redis_client.delete(f"otp_session:{phone}")
                except Exception:
                    cls._sessions.pop(phone, None)
            else:
                cls._sessions.pop(phone, None)
            return {
                "success": False,
                "message": "OTP has expired. Please request a new code."
            }

        if session["attempts"] >= 5:
            if redis_client:
                try:
                    redis_client.delete(f"otp_session:{phone}")
                except Exception:
                    cls._sessions.pop(phone, None)
            else:
                cls._sessions.pop(phone, None)
            return {
                "success": False,
                "message": "Too many failed attempts. Please request a new OTP."
            }

        session["attempts"] += 1
        expected_hash = cls._hash_otp(phone, entered_otp)

        if session["hash"] == expected_hash:
            if redis_client:
                try:
                    redis_client.delete(f"otp_session:{phone}")
                except Exception:
                    cls._sessions.pop(phone, None)
            else:
                cls._sessions.pop(phone, None)

            return {
                "success": True,
                "phone": phone,
                "message": "Phone number verified successfully."
            }
        else:
            if redis_client:
                try:
                    redis_client.setex(
                        f"otp_session:{phone}",
                        int(session["expires_at"] - now),
                        json.dumps(session)
                    )
                except Exception:
                    cls._sessions[phone] = session
            else:
                cls._sessions[phone] = session

            return {
                "success": False,
                "message": "Incorrect OTP code. Please try again."
            }

    @staticmethod
    def create_jwt_token(user_id: str, phone: str, role: str = "CUSTOMER") -> str:
        payload = {
            "sub": user_id,
            "phone": phone,
            "role": role,
            "iat": datetime.utcnow(),
            "exp": datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
        }
        return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)

    @staticmethod
    def verify_jwt_token(token: str) -> Optional[Dict[str, Any]]:
        try:
            payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
            return payload
        except jwt.ExpiredSignatureError:
            return None
        except jwt.InvalidTokenError:
            return None

otp_service = OTPService()
