import os
import sys
from dotenv import load_dotenv

# Load .env file if present
load_dotenv()

# Master OTP bypass — only honored in non-production AND when explicitly enabled.
# In production this is ALWAYS False regardless of the env value, so the 123456
# backdoor cannot be used against real customers.
DEV_OTP_BYPASS: bool = (
    os.getenv("ENVIRONMENT", "development") != "production"
    and os.getenv("DEV_OTP_BYPASS", "true").lower() == "true"
)


class Settings:
    PROJECT_NAME: str = os.getenv("PROJECT_NAME", "Flash Fresh Vegetables & Sunday Meat Quick Commerce")
    API_V1_STR: str = "/api/v1"
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")  # production / development

    # Security & JWT Auth
    JWT_SECRET_KEY: str = os.getenv("JWT_SECRET_KEY", "dev_insecure_jwt_secret_change_me_in_production_min_32_chars_long")
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 30  # 30 Days

    # SMS Gateway (Fast2SMS / MSG91)
    SMS_PROVIDER: str = os.getenv("SMS_PROVIDER", "FAST2SMS")
    SMS_API_KEY: str = os.getenv("SMS_API_KEY", "")
    OTP_EXPIRY_SECONDS: int = 300  # 5 Minutes
    DEV_OTP_BYPASS: bool = DEV_OTP_BYPASS

    # CORS allow-list (comma-separated origins). Never "*" in production.
    CORS_ORIGINS: str = os.getenv("CORS_ORIGINS", "*")

    # Razorpay Payment Gateway (Production / Live Test)
    RAZORPAY_KEY_ID: str = os.getenv("RAZORPAY_KEY_ID", "")
    RAZORPAY_KEY_SECRET: str = os.getenv("RAZORPAY_KEY_SECRET", "")
    RAZORPAY_WEBHOOK_SECRET: str = os.getenv("RAZORPAY_WEBHOOK_SECRET", "")

    # Cashfree Payment Gateway (Sandbox / Live)
    CASHFREE_APP_ID: str = os.getenv("CASHFREE_APP_ID", "TEST11361500854188d61c28cdc37e6d00516311")
    CASHFREE_SECRET_KEY: str = os.getenv("CASHFREE_SECRET_KEY", "cfsk_ma_test_80e826f86581fa4e7d6ea9af24c4da2a_ba79c20a")
    CASHFREE_WEBHOOK_SECRET: str = os.getenv("CASHFREE_WEBHOOK_SECRET", "")
    CASHFREE_ENV: str = os.getenv("CASHFREE_ENV", "sandbox")  # sandbox | production

    # Google Maps Platform (Places Autocomplete, Geocoding, Distance Matrix)
    GOOGLE_MAPS_API_KEY: str = os.getenv("GOOGLE_MAPS_API_KEY", "")

    # Central Dark Store Hub — Miyapur (exact Google Maps pin, 10 KM Radius).
    # Verified from https://maps.app.goo.gl/5fc6a8ZMgjfttUiB9
    STORE_LATITUDE: float = float(os.getenv("STORE_LATITUDE", "17.495101"))
    STORE_LONGITUDE: float = float(os.getenv("STORE_LONGITUDE", "78.367535"))
    MAX_DELIVERY_RADIUS_KM: float = float(os.getenv("MAX_DELIVERY_RADIUS_KM", "10.0"))
    STORE_NAME: str = os.getenv("STORE_NAME", "Central Dark Store Hub")
    STORE_ADDRESS: str = os.getenv("STORE_ADDRESS", "Beside Metro Pillar 84, Miyapur, Hyderabad, Telangana 500049")

    # Database & Redis Infrastructure
    _raw_db_url: str = os.getenv("DATABASE_URL", "sqlite:///./quick_commerce.db")
    if _raw_db_url.startswith("postgres://"):
        _raw_db_url = _raw_db_url.replace("postgres://", "postgresql://", 1)
    DATABASE_URL: str = _raw_db_url
    REDIS_URL: str = os.getenv("REDIS_URL", "redis://localhost:6379/0")

    @property
    def cashfree_base_url(self) -> str:
        return "https://sandbox.cashfree.com/pg/orders" if self.CASHFREE_ENV == "sandbox" else "https://api.cashfree.com/pg/orders"

    @property
    def cashfree_is_sandbox(self) -> bool:
        return self.CASHFREE_ENV == "sandbox" or self.CASHFREE_APP_ID.startswith("TEST")

    def validate_production_secrets(self):
        """
        Fail-closed security check for production deployment.
        Refuses to boot when critical secrets are missing or weak.
        """
        if self.ENVIRONMENT != "production":
            return

        errors = []

        # JWT secret must be set and strong (>= 32 chars, not a known placeholder)
        if not self.JWT_SECRET_KEY or self.JWT_SECRET_KEY.startswith("dev_insecure") or "super_secret" in self.JWT_SECRET_KEY or len(self.JWT_SECRET_KEY) < 32:
            errors.append("JWT_SECRET_KEY must be set to a unique, >=32-char value in production.")

        # Cashfree credentials must be live (not the sandbox test defaults)
        if self.CASHFREE_APP_ID.startswith("TEST") or "cfsk_ma_test_" in self.CASHFREE_SECRET_KEY:
            errors.append("Cashfree test credentials cannot be used in production. Set live CASHFREE_APP_ID / CASHFREE_SECRET_KEY.")

        # Webhook signature verification secret must be configured
        if not self.CASHFREE_WEBHOOK_SECRET and not self.RAZORPAY_WEBHOOK_SECRET:
            errors.append("At least one webhook secret (CASHFREE_WEBHOOK_SECRET or RAZORPAY_WEBHOOK_SECRET) must be set in production.")

        # Google Maps API key must be set (geofence + places autocomplete rely on it)
        if not self.GOOGLE_MAPS_API_KEY:
            errors.append("GOOGLE_MAPS_API_KEY must be set in production.")

        # OTP backdoor must be disabled
        if self.DEV_OTP_BYPASS:
            errors.append("DEV_OTP_BYPASS must be disabled (false) in production.")

        if errors:
            print("❌ [FATAL] Production secret validation failed:")
            for e in errors:
                print(f"   - {e}")
            sys.exit(1)


settings = Settings()
settings.validate_production_secrets()
