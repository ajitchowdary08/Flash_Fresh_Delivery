import pytest
from app.services.otp_service import otp_service

def test_otp_generation():
    res = otp_service.send_otp("9876543210")
    assert res["success"] is True
    assert res["phone"] == "9876543210"
    assert res["expires_in_seconds"] == 300

def test_invalid_phone_number():
    res = otp_service.send_otp("123")
    assert res["success"] is False
    assert "Invalid phone number" in res["message"]

def test_jwt_token_creation_and_verification():
    token = otp_service.create_jwt_token(user_id="usr_test_123", phone="9876543210", role="CUSTOMER")
    assert isinstance(token, str)

    payload = otp_service.verify_jwt_token(token)
    assert payload is not None
    assert payload["sub"] == "usr_test_123"
    assert payload["phone"] == "9876543210"
    assert payload["role"] == "CUSTOMER"
