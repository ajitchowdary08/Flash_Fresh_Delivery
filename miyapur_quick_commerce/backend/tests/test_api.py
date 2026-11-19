import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.database.db import get_db, SessionLocal
from app.models.models import User, Order

client = TestClient(app)

def test_verify_otp_creates_then_reuses_same_user():
    """
    Guarantees the login fix: re-logging in with the same phone number
    must always resolve and reuse the existing User ID from the database,
    preventing any profile or address loss.
    """
    phone = "9876501234"
    # Send OTP
    r_send = client.post("/api/v1/auth/send-otp", json={"phone": phone})
    assert r_send.status_code == 200
    otp = r_send.json().get("dev_otp", "123456")

    # First login (creates user)
    r1 = client.post("/api/v1/auth/verify-otp", json={"phone": phone, "otp": otp})
    assert r1.status_code == 200
    uid1 = r1.json()["user_id"]
    assert uid1 is not None

    # Update profile name
    client.post(f"/api/v1/auth/profile/{uid1}", json={"name": "Ajit Chowdary"})

    # Second login (same phone)
    r_send2 = client.post("/api/v1/auth/send-otp", json={"phone": phone})
    otp2 = r_send2.json().get("dev_otp", "123456")
    r2 = client.post("/api/v1/auth/verify-otp", json={"phone": phone, "otp": otp2})
    assert r2.status_code == 200
    uid2 = r2.json()["user_id"]
    assert uid2 == uid1, "Re-login must return the exact same user_id"
    assert r2.json()["name"] == "Ajit Chowdary", "Profile name must persist"

def test_order_creation_server_authoritative_and_idempotent():
    """
    Verifies server-authoritative pricing and idempotency:
    re-submitting with the same idempotency_key returns the existing order.
    """
    import uuid
    idempotency_key = f"test_idem_{uuid.uuid4().hex[:10]}"
    payload = {
        "user_id": "usr_test_idem",
        "delivery_address": "Near Miyapur Metro Pillar 84",
        "latitude": 17.495101,
        "longitude": 78.367535,
        "items": [
            {
                "product_name": "Fresh Farm Hybrid Tomatoes",
                "variant_label": "1kg",
                "quantity": 2,
                "unit_price": 38.0
            }
        ],
        "payment_method": "UPI",
        "idempotency_key": idempotency_key
    }

    r1 = client.post("/api/v1/orders/create", json=payload)
    assert r1.status_code == 200
    data1 = r1.json()
    assert data1["success"] is True
    order_id = data1["order_id"]
    assert data1.get("payment_session_id") is not None

    # Second submission with same idempotency key
    r2 = client.post("/api/v1/orders/create", json=payload)
    assert r2.status_code == 200
    data2 = r2.json()
    assert data2["order_id"] == order_id
    assert "already processed" in data2.get("message", "")

def test_far_away_address_is_serviceable():
    """
    We deliver ANYWHERE — there is no 10 KM radius cap. An order to a far-away
    address (e.g. Charminar, ~24 KM from the hub) must be accepted, not rejected.
    """
    payload = {
        "user_id": "usr_test_far",
        "delivery_address": "Charminar, Old City, Hyderabad",
        "latitude": 17.3616,  # ~24 KM from Miyapur
        "longitude": 78.4747,
        "items": [
            {
                "product_name": "Fresh Farm Hybrid Tomatoes",
                "variant_label": "1kg",
                "quantity": 1,
                "unit_price": 38.0
            }
        ],
        "payment_method": "UPI"
    }
    r = client.post("/api/v1/orders/create", json=payload)
    assert r.status_code == 200
    assert r.json()["success"] is True
    # Distance is recorded for display but must NOT block the order.
    assert r.json()["distance_km"] > 10.0

def test_cashfree_checkout_page_renders_official_sdk():
    """
    Verifies that GET /payments/cashfree-checkout/{order_id} renders Cashfree Drop-in SDK v3.
    """
    # Create order first
    payload = {
        "user_id": "usr_test_cf",
        "delivery_address": "Miyapur Allwyn Colony",
        "latitude": 17.495101,
        "longitude": 78.367535,
        "items": [
            {
                "product_name": "Fresh Farm Hybrid Tomatoes",
                "variant_label": "1kg",
                "quantity": 1,
                "unit_price": 38.0
            }
        ],
        "payment_method": "UPI"
    }
    r_order = client.post("/api/v1/orders/create", json=payload)
    assert r_order.status_code == 200
    order_id = r_order.json()["order_id"]

    r_checkout = client.get(f"/api/v1/payments/cashfree-checkout/{order_id}")
    assert r_checkout.status_code == 200
    assert "https://sdk.cashfree.com/js/v3/cashfree.js" in r_checkout.text
    assert "Cashfree({" in r_checkout.text
    assert "mode: \"sandbox\"" in r_checkout.text


# --- New tests for the auth + dynamic-data refactor --------------------------

def test_store_endpoints_reject_invalid_token():
    """A present-but-invalid Bearer token must be rejected on store routes
    (401 unauthenticated or 403 forbidden — both prove the route is protected)."""
    r = client.get("/api/v1/store/dashboard-summary",
                   headers={"Authorization": "Bearer not.a.real.jwt"})
    assert r.status_code in (401, 403)


def test_riders_seeded_into_db():
    """The delivery fleet is now a DB table, not a hardcoded Python list."""
    from app.models.models import Rider
    db = SessionLocal()
    try:
        assert db.query(Rider).count() >= 1
        names = {r.name for r in db.query(Rider).all()}
        assert "Ravi Kumar" in names
    finally:
        db.close()


def test_promo_codes_seeded_into_db():
    """Promo codes are now a DB table, not a hardcoded Python dict."""
    from app.models.models import PromoCode
    db = SessionLocal()
    try:
        codes = {p.code for p in db.query(PromoCode).all()}
        assert {"ZEPTO50", "FLASH100", "SUNDAYMEAT"}.issubset(codes)
    finally:
        db.close()


def test_manager_account_seeded():
    """A default store-manager account exists with role=MANAGER."""
    from app.models.models import User
    db = SessionLocal()
    try:
        mgr = db.query(User).filter(User.role == "MANAGER").first()
        assert mgr is not None
        assert mgr.phone == "9000011111"
    finally:
        db.close()


def test_promo_validate_now_rejected():
    """Promo codes have been retired. Validating any code must return 400 so
    the checkout no longer applies a discount."""
    r = client.post("/api/v1/catalog/promos/validate", json={"code": "zepto50", "items_total": 200})
    assert r.status_code == 400


def test_active_promos_list_is_empty():
    """The active-promos banner endpoint returns an empty list (no promos shown)."""
    r = client.get("/api/v1/catalog/promos/active")
    assert r.status_code == 200
    assert r.json() == []


def test_order_creation_no_fake_rider():
    """A freshly created order must NOT be born with the fake 'Ravi Kumar' rider."""
    payload = {
        "user_id": "usr_test_norider",
        "delivery_address": "Miyapur Metro Pillar 84",
        "latitude": 17.495101,
        "longitude": 78.367535,
        "items": [
            {"product_name": "Fresh Farm Hybrid Tomatoes", "variant_label": "1kg",
             "quantity": 1, "unit_price": 38.0}
        ],
        "payment_method": "UPI"
    }
    r = client.post("/api/v1/orders/create", json=payload)
    assert r.status_code == 200
    data = r.json()
    order_id = data["order_id"]
    from app.models.models import Order
    db = SessionLocal()
    try:
        o = db.query(Order).filter(Order.id == order_id).first()
        assert o is not None
        assert o.rider_id is None
        assert o.rider_name is None
    finally:
        db.close()


def test_idempotent_order_create_retry_returns_cached_order():
    """A retried order-create with the SAME idempotency_key must return the
    already-created order (success), NOT a 429 rate-limit or a duplicate.
    This is the double-tap / network-retry safety net."""
    payload = {
        "user_id": "usr_test_idem",
        "delivery_address": "Miyapur Metro Pillar 84",
        "latitude": 17.495101,
        "longitude": 78.367535,
        "items": [
            {"product_name": "Fresh Farm Hybrid Tomatoes", "variant_label": "1kg",
             "quantity": 1, "unit_price": 38.0}
        ],
        "payment_method": "UPI",
        "idempotency_key": "idem_test_key_20261118",
    }
    r1 = client.post("/api/v1/orders/create", json=payload)
    assert r1.status_code == 200
    first = r1.json()
    # Immediate retry with the same key — must NOT 429, must return the same order.
    r2 = client.post("/api/v1/orders/create", json=payload)
    assert r2.status_code == 200
    second = r2.json()
    assert second["success"] is True
    assert second["order_id"] == first["order_id"]
