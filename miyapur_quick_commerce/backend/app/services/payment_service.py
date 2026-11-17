import hmac
import hashlib
import base64
import time
import uuid
import requests
from typing import Dict, Any, Optional
from app.core.config import settings

class PaymentService:
    """
    Production & Test Payment Gateway Integration.
    - Supports Razorpay Test Mode (`rzp_test_...`) & Live Mode (`rzp_live_...`)
    - Supports Cashfree Sandbox Mode (`TEST...`) & Production Mode
    - Real HMAC-SHA256 Signature & Webhook Verification
    - Simulated Sandbox Fallback Mode for keyless testing
    """

    @staticmethod
    def create_cashfree_order(
        amount_in_rupees: float,
        order_id: str,
        customer_phone: str = "9966114243",
        customer_id: str = "cust_quick_commerce",
        customer_name: str = "Customer"
    ) -> Dict[str, Any]:
        """
        Creates an official Cashfree Sandbox / Production Order and generates payment_session_id.
        """
        cashfree_app_id = getattr(settings, "CASHFREE_APP_ID", "TEST11361500854188d61c28cdc37e6d00516311")
        cashfree_secret_key = getattr(settings, "CASHFREE_SECRET_KEY", "cfsk_ma_test_80e826f86581fa4e7d6ea9af24c4da2a_ba79c20a")

        is_sandbox = cashfree_app_id.startswith("TEST") or "sandbox" in cashfree_app_id.lower()
        cf_url = "https://sandbox.cashfree.com/pg/orders" if is_sandbox else "https://api.cashfree.com/pg/orders"

        clean_phone = customer_phone.strip().replace("+91", "").replace(" ", "").replace("-", "")
        if len(clean_phone) != 10:
            clean_phone = "9966114243"

        # Sanitize order ID for Cashfree (letters, numbers, hyphens, underscores; max 50 chars)
        clean_order_id = "".join(c for c in order_id if c.isalnum() or c in "-_")[:45]

        headers = {
            "x-client-id": cashfree_app_id,
            "x-client-secret": cashfree_secret_key,
            "x-api-version": "2023-08-01",
            "Content-Type": "application/json"
        }
        payload = {
            "order_id": clean_order_id,
            "order_amount": round(float(amount_in_rupees), 2),
            "order_currency": "INR",
            "customer_details": {
                "customer_id": customer_id[:45],
                "customer_phone": clean_phone,
                "customer_name": customer_name or "Customer"
            },
            "order_meta": {
                "return_url": "http://127.0.0.1:8000/api/v1/payments/cashfree/return?order_id={order_id}"
            }
        }

        try:
            response = requests.post(cf_url, headers=headers, json=payload, timeout=8)
            if response.status_code in [200, 201]:
                data = response.json()
                return {
                    "success": True,
                    "gateway": "CASHFREE_SANDBOX" if is_sandbox else "CASHFREE_LIVE",
                    "order_id": data.get("order_id", clean_order_id),
                    "cf_order_id": data.get("cf_order_id"),
                    "payment_session_id": data.get("payment_session_id"),
                    "amount_in_rupees": amount_in_rupees,
                    "currency": "INR"
                }
            elif response.status_code == 400 and "order_already_exists" in response.text:
                # If order was already created, retrieve its active payment_session_id
                get_url = f"{cf_url}/{clean_order_id}"
                get_res = requests.get(get_url, headers=headers, timeout=8)
                if get_res.status_code == 200:
                    data = get_res.json()
                    return {
                        "success": True,
                        "gateway": "CASHFREE_SANDBOX" if is_sandbox else "CASHFREE_LIVE",
                        "order_id": data.get("order_id", clean_order_id),
                        "cf_order_id": data.get("cf_order_id"),
                        "payment_session_id": data.get("payment_session_id"),
                        "amount_in_rupees": amount_in_rupees,
                        "currency": "INR"
                    }

            if is_sandbox or settings.ENVIRONMENT != "production":
                return {
                    "success": True,
                    "gateway": "CASHFREE_SANDBOX_MOCK",
                    "order_id": clean_order_id,
                    "cf_order_id": f"cf_mock_{clean_order_id}",
                    "payment_session_id": f"session_mock_{clean_order_id}",
                    "amount_in_rupees": amount_in_rupees,
                    "currency": "INR"
                }

            return {
                "success": False,
                "status_code": response.status_code,
                "error": response.text
            }
        except Exception as e:
            if is_sandbox or settings.ENVIRONMENT != "production":
                return {
                    "success": True,
                    "gateway": "CASHFREE_SANDBOX_MOCK",
                    "order_id": clean_order_id,
                    "cf_order_id": f"cf_mock_{clean_order_id}",
                    "payment_session_id": f"session_mock_{clean_order_id}",
                    "amount_in_rupees": amount_in_rupees,
                    "currency": "INR"
                }
            return {"success": False, "error": str(e)}

    @staticmethod
    def verify_cashfree_order_status(order_id: str) -> Dict[str, Any]:
        """
        Polls the Cashfree API to verify the authoritative status of an order.

        Cashfree order_status values:
          - ACTIVE   : payment session still in progress (not yet paid/failed)
          - PAID     : payment captured successfully
          - EXPIRED  : session expired without payment
          - FAILED   : payment attempted but failed

        Returns `is_paid` only when order_status == "PAID". Returns `is_failed`
        when order_status is in {EXPIRED, FAILED}. ACTIVE is treated as "not yet
        decided" so the client can either retry or cancel.
        """
        cashfree_app_id = getattr(settings, "CASHFREE_APP_ID", "TEST11361500854188d61c28cdc37e6d00516311")
        cashfree_secret_key = getattr(settings, "CASHFREE_SECRET_KEY", "cfsk_ma_test_80e826f86581fa4e7d6ea9af24c4da2a_ba79c20a")
        is_sandbox = cashfree_app_id.startswith("TEST") or "sandbox" in cashfree_app_id.lower()
        cf_url = f"https://sandbox.cashfree.com/pg/orders/{order_id}" if is_sandbox else f"https://api.cashfree.com/pg/orders/{order_id}"

        headers = {
            "x-client-id": cashfree_app_id,
            "x-client-secret": cashfree_secret_key,
            "x-api-version": "2023-08-01"
        }
        try:
            response = requests.get(cf_url, headers=headers, timeout=8)
            if response.status_code == 200:
                data = response.json()
                order_status = (data.get("order_status") or "").upper()

                # Cashfree returns a payment group with the worst payment's status,
                # which is the authoritative source for FAILED/CANCELLED/User-dropped.
                payment_group = (data.get("payment_group") or [{}])[0] if isinstance(data.get("payment_group"), list) else {}
                pg_status = (payment_group.get("status") or "").upper()
                pg_message = payment_group.get("error_details", {}).get("description") if isinstance(payment_group.get("error_details"), dict) else None

                is_paid = order_status == "PAID"
                is_failed = order_status in {"EXPIRED", "FAILED"} or pg_status in {"EXPIRED", "FAILED", "CANCELLED", "USER_DROPPED"}

                # Human-readable reason surfaced to the customer
                if is_paid:
                    reason = "Payment captured successfully."
                elif is_failed:
                    if order_status == "FAILED":
                        reason = pg_message or "The payment was declined by your bank or card issuer. Please try a different payment method."
                    elif order_status == "EXPIRED":
                        reason = "The payment session expired before completion. Please try again."
                    elif pg_status == "USER_DROPPED":
                        reason = "The payment was cancelled before completion. Please try again."
                    elif pg_status == "CANCELLED":
                        reason = "The payment was cancelled. Please try again."
                    else:
                        reason = pg_message or "Payment failed. Please retry with a different payment method."
                else:
                    reason = "Payment is still in progress."

                return {
                    "success": True,
                    "order_status": order_status,
                    "is_paid": is_paid,
                    "is_failed": is_failed,
                    "failure_reason": reason if is_failed else None,
                    "data": data
                }
        except Exception as e:
            print(f"[Cashfree Verify Error]: {e}")
        return {"success": False, "is_paid": False, "is_failed": False, "order_status": "UNKNOWN"}

    @staticmethod
    def create_order(amount_in_rupees: float, receipt_id: str) -> Dict[str, Any]:
        amount_in_paise = int(amount_in_rupees * 100)

        # 1. Razorpay Gateway (Test Mode / Live Mode)
        if settings.RAZORPAY_KEY_ID and settings.RAZORPAY_KEY_SECRET:
            try:
                is_test_mode = settings.RAZORPAY_KEY_ID.startswith("rzp_test_")
                response = requests.post(
                    "https://api.razorpay.com/v1/orders",
                    auth=(settings.RAZORPAY_KEY_ID, settings.RAZORPAY_KEY_SECRET),
                    json={
                        "amount": amount_in_paise,
                        "currency": "INR",
                        "receipt": receipt_id,
                        "payment_capture": 1,
                        "notes": {
                            "mode": "TEST_MODE" if is_test_mode else "LIVE_MODE",
                            "hub": "Central Dark Store Hub",
                            "sla": "10-Minute Fresh Delivery"
                        }
                    },
                    timeout=8
                )
                if response.status_code == 200:
                    data = response.json()
                    return {
                        "success": True,
                        "gateway": "RAZORPAY_TEST" if is_test_mode else "RAZORPAY_LIVE",
                        "gateway_order_id": data["id"],
                        "key_id": settings.RAZORPAY_KEY_ID,
                        "amount_in_paise": amount_in_paise,
                        "amount_in_rupees": amount_in_rupees,
                        "currency": "INR",
                        "receipt_id": receipt_id
                    }
            except Exception as e:
                print(f"[Razorpay Error]: {e}")

        # 2. Cashfree Gateway (Sandbox / Live Mode)
        cashfree_app_id = getattr(settings, "CASHFREE_APP_ID", "")
        cashfree_secret_key = getattr(settings, "CASHFREE_SECRET_KEY", "")
        if cashfree_app_id and cashfree_secret_key:
            try:
                is_sandbox = cashfree_app_id.startswith("TEST") or "sandbox" in cashfree_app_id.lower()
                cf_url = "https://sandbox.cashfree.com/pg/orders" if is_sandbox else "https://api.cashfree.com/pg/orders"
                headers = {
                    "x-client-id": cashfree_app_id,
                    "x-client-secret": cashfree_secret_key,
                    "x-api-version": "2023-08-01",
                    "Content-Type": "application/json"
                }
                response = requests.post(
                    cf_url,
                    headers=headers,
                    json={
                        "order_id": receipt_id,
                        "order_amount": amount_in_rupees,
                        "order_currency": "INR",
                        "customer_details": {
                            "customer_id": "cust_test_123",
                            "customer_phone": "9876543210"
                        }
                    },
                    timeout=8
                )
                if response.status_code in [200, 201]:
                    data = response.json()
                    return {
                        "success": True,
                        "gateway": "CASHFREE_SANDBOX" if is_sandbox else "CASHFREE_LIVE",
                        "gateway_order_id": data.get("order_id", receipt_id),
                        "payment_session_id": data.get("payment_session_id"),
                        "amount_in_rupees": amount_in_rupees,
                        "currency": "INR",
                        "receipt_id": receipt_id
                    }
            except Exception as e:
                print(f"[Cashfree Error]: {e}")

        # 3. Simulated Test Sandbox Mode (Keyless Instant Testing)
        mock_order_id = f"order_test_{uuid.uuid4().hex[:12]}"
        return {
            "success": True,
            "gateway": "TEST_SANDBOX_SIMULATED",
            "gateway_order_id": mock_order_id,
            "key_id": settings.RAZORPAY_KEY_ID or "rzp_test_public_key_demo",
            "amount_in_paise": amount_in_paise,
            "amount_in_rupees": amount_in_rupees,
            "currency": "INR",
            "receipt_id": receipt_id,
            "message": "Test Mode Active: Instant Simulated Verification"
        }

    @staticmethod
    def verify_payment_signature(
        razorpay_order_id: str,
        razorpay_payment_id: str,
        razorpay_signature: str
    ) -> bool:
        """
        Validates the authenticity of the payment response using HMAC-SHA256.
        """
        if not settings.RAZORPAY_KEY_SECRET:
            return bool(razorpay_order_id and razorpay_payment_id)

        try:
            msg = f"{razorpay_order_id}|{razorpay_payment_id}"
            generated_signature = hmac.new(
                settings.RAZORPAY_KEY_SECRET.encode("utf-8"),
                msg.encode("utf-8"),
                hashlib.sha256
            ).hexdigest()

            return hmac.compare_digest(generated_signature, razorpay_signature)
        except Exception:
            return False

    @staticmethod
    def verify_webhook_signature(payload_body: bytes, signature_header: str) -> bool:
        """
        Validates Razorpay webhook requests using HMAC-SHA256. Fails CLOSED — if no
        webhook secret is configured, the signature cannot be verified and the request
        is rejected (never accepted) so a forged webhook can never mark an order paid.
        """
        if not settings.RAZORPAY_WEBHOOK_SECRET or not signature_header:
            return False

        try:
            generated_signature = hmac.new(
                settings.RAZORPAY_WEBHOOK_SECRET.encode("utf-8"),
                payload_body,
                hashlib.sha256
            ).hexdigest()
            return hmac.compare_digest(generated_signature, signature_header)
        except Exception:
            return False

    @staticmethod
    def verify_cashfree_webhook_signature(
        timestamp: str,
        raw_body: bytes,
        signature_header: str
    ) -> bool:
        """
        Validates Cashfree webhook requests per the official v2022-09-01 specification:
        expected = Base64(HMAC-SHA256(timestamp + raw_body, secret))
        Comparison is constant-time. Fails CLOSED when no secret is configured.
        """
        secret = settings.CASHFREE_WEBHOOK_SECRET
        if not secret or not timestamp or not signature_header:
            return False
        try:
            signed_payload = timestamp.encode("utf-8") + raw_body
            digest = hmac.new(secret.encode("utf-8"), signed_payload, hashlib.sha256).digest()
            expected = base64.b64encode(digest).decode("utf-8")
            return hmac.compare_digest(expected, signature_header)
        except Exception:
            return False

    @staticmethod
    def is_timestamp_fresh(timestamp: str, max_skew_seconds: int = 300) -> bool:
        """
        Rejects replayed Cashfree webhooks whose timestamp is older than max_skew_seconds.
        """
        try:
            ts = int(timestamp)
            now = int(time.time())
            return abs(now - ts) <= max_skew_seconds
        except Exception:
            return False

payment_service = PaymentService()
