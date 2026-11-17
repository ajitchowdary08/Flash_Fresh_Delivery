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
                "product_name": "Farm Fresh Tomatoes",
                "variant_label": "1 kg",
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

def test_geofence_out_of_bounds_rejection():
    """
    Orders beyond the 10 KM delivery radius from Miyapur Central Hub must fail closed (400 Bad Request).
    """
    payload = {
        "user_id": "usr_test_geofence",
        "delivery_address": "Charminar, Old City, Hyderabad",
        "latitude": 17.3616,  # ~24 KM from Miyapur
        "longitude": 78.4747,
        "items": [
            {
                "product_name": "Farm Fresh Tomatoes",
                "variant_label": "1 kg",
                "quantity": 1,
                "unit_price": 38.0
            }
        ],
        "payment_method": "UPI"
    }
    r = client.post("/api/v1/orders/create", json=payload)
    assert r.status_code == 400
    assert "exceeds our 10.0 KM service boundary" in r.json()["detail"]

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
                "product_name": "Farm Fresh Tomatoes",
                "variant_label": "1 kg",
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
