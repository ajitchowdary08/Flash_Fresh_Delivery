from fastapi import APIRouter, Depends, HTTPException, Request, Header
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional

from app.database.db import get_db
from app.models.models import Order, ProductVariant, Payment
from app.services.payment_service import payment_service
from app.core.config import settings
from app.core.security import get_current_user

router = APIRouter(prefix="/payments", tags=["Cashfree PG & UPI Payments"])

class VerifyPaymentPayload(BaseModel):
    order_id: str
    payment_method: str = "COD"
    transaction_id: Optional[str] = None

class CashfreeVerifyPayload(BaseModel):
    order_id: str

@router.post("/verify")
def verify_payment(req: VerifyPaymentPayload, db: Session = Depends(get_db), user: dict = Depends(get_current_user)):
    """
    Confirms offline / postpaid payment methods (COD, Pay Later) and advances order to PACKING.
    Online gateway payments (Cards, UPI, NetBanking) MUST be verified server-side via /payments/cashfree/verify.
    """
    method = (req.payment_method or "COD").upper()
    if method not in ["COD", "CASH_ON_DELIVERY", "PAY_LATER", "PAY_LATER_MONTHLY"]:
        raise HTTPException(
            status_code=400,
            detail="Online payments must be verified via official gateway verification (/payments/cashfree/verify)."
        )

    order = db.query(Order).filter(Order.id == req.order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    # Only the order owner (or a guest in dev) may verify their own payment.
    if user.get("role") == "CUSTOMER" and order.user_id and user.get("sub") != "usr_guest_local" \
            and order.user_id != user.get("sub"):
        raise HTTPException(status_code=403, detail="You can only verify payments for your own orders.")

    order.payment_status = "PENDING_COD" if method in ["COD", "CASH_ON_DELIVERY"] else "PAID"
    order.payment_method = req.payment_method
    order.status = "PACKED"
    db.commit()
    db.refresh(order)

    # Record the payment ledger entry.
    try:
        db.add(Payment(
            order_id=order.id, gateway=req.payment_method.upper(),
            gateway_order_id=order.order_number, amount=order.grand_total,
            status=order.payment_status,
        ))
        db.commit()
    except Exception:
        db.rollback()

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "payment_status": order.payment_status,
        "order_status": order.status,
        "message": "Payment verified successfully. Order sent to Dark Store packing station."
    }

@router.get("/cashfree-checkout/{order_id}", response_class=HTMLResponse)
def get_cashfree_checkout_page(
    order_id: str,
    session_id: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """
    Renders the 100% OFFICIAL Cashfree Web Checkout (Drop-in SDK) page.
    Directly connects to sandbox.cashfree.com to display:
    - Official purple 'Secured by Cashfree' header
    - Test Cards (Visa, RuPay, MasterCard) with 1-click 'Use'
    - Net Banking (ICICI, HDFC, SBI)
    - Cashfree Simulator screen with OTP 111000
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        order = db.query(Order).filter(Order.order_number == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    user_phone = order.user.phone if (order.user and order.user.phone) else "9999999999"
    user_name = order.user.name if (order.user and order.user.name) else "Customer"

    payment_session_id = session_id or order.payment_session_id
    if not payment_session_id:
        # Create real Cashfree Sandbox order session
        cf_res = payment_service.create_cashfree_order(
            amount_in_rupees=order.grand_total,
            order_id=order.order_number,
            customer_phone=user_phone,
            customer_id=order.user_id or "cust_test_123",
            customer_name=user_name
        )

        if not cf_res.get("success") or not cf_res.get("payment_session_id"):
            return HTMLResponse(content=f"""
            <html>
            <body style="font-family: sans-serif; padding: 24px; text-align: center;">
                <h3 style="color: red;">Cashfree Order Initialization Failed</h3>
                <p>{cf_res.get('error', 'Unable to create Cashfree session.')}</p>
            </body>
            </html>
            """, status_code=500)

        payment_session_id = cf_res["payment_session_id"]

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>Secured by Cashfree</title>
    <!-- Official Cashfree JS SDK v3 -->
    <script src="https://sdk.cashfree.com/js/v3/cashfree.js"></script>
    <style>
        * {{ box-sizing: border-box; }}
        body, html {{
            margin: 0;
            padding: 0;
            width: 100%;
            height: 100%;
            background-color: #f8fafc;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            overflow: hidden;
        }}
        #loader-container {{
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            height: 100vh;
            color: #1e293b;
            text-align: center;
            padding: 20px;
        }}
        .cf-logo {{
            font-size: 28px;
            font-weight: 900;
            color: #0f172a;
            letter-spacing: -0.5px;
            margin-bottom: 24px;
        }}
        .spinner {{
            width: 44px;
            height: 44px;
            border: 4px solid #e2e8f0;
            border-top: 4px solid #6366f1;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
            margin-bottom: 16px;
        }}
        @keyframes spin {{
            0% {{ transform: rotate(0deg); }}
            100% {{ transform: rotate(360deg); }}
        }}
    </style>
</head>
<body>
    <div id="loader-container">
        <div class="cf-logo">Cashfree</div>
        <div class="spinner"></div>
        <div style="font-size: 14px; font-weight: 600; color: #64748b;">
            Opening Official Cashfree Payment Gateway...
        </div>
        <div style="font-size: 12px; color: #94a3b8; margin-top: 6px;">
            Order Amount: &#8377;{order.grand_total:.2f}
        </div>
    </div>

    <script>
        document.addEventListener("DOMContentLoaded", function() {{
            try {{
                const cashfree = Cashfree({{
                    mode: "sandbox"
                }});

                cashfree.checkout({{
                    paymentSessionId: "{payment_session_id}",
                    redirectTarget: "_self"
                }}).then(function(result) {{
                    if (result && result.error) {{
                        console.error("Cashfree Checkout Error:", result.error);
                        document.getElementById("loader-container").innerHTML = 
                            "<h3 style='color:red;'>Cashfree Error</h3><p>" + result.error.message + "</p>";
                    }}
                }});
            }} catch(e) {{
                console.error("Cashfree Init Exception:", e);
                document.getElementById("loader-container").innerHTML = 
                    "<h3 style='color:red;'>Cashfree Exception</h3><p>" + e.message + "</p>";
            }}
        }});
    </script>
</body>
</html>"""
    return HTMLResponse(content=html_content)

@router.get("/cashfree/return", response_class=HTMLResponse)
def cashfree_payment_return(order_id: str, db: Session = Depends(get_db)):
    """
    Cashfree returns here after user completes payment or simulator OTP.
    Marks the order as PAID and returns a success redirect page.
    """
    order = db.query(Order).filter(Order.order_number == order_id).first()
    if not order:
        order = db.query(Order).filter(Order.id == order_id).first()

    if order:
        order.payment_status = "PAID"
        order.payment_method = "CASHFREE_SANDBOX"
        order.status = "PACKED"
        db.commit()
        db.refresh(order)

    return HTMLResponse(content=f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Payment Successful</title>
        <style>
            body {{ font-family: sans-serif; text-align: center; padding: 40px 20px; background: #f0fdf4; color: #166534; }}
            .card {{ background: white; border-radius: 16px; padding: 32px 20px; box-shadow: 0 4px 12px rgba(0,0,0,0.06); max-width: 360px; margin: 0 auto; }}
            .btn {{ display: inline-block; margin-top: 24px; padding: 12px 28px; background: #16a34a; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; font-size: 14px; }}
        </style>
    </head>
    <body>
        <div class="card">
            <div style="font-size: 48px; margin-bottom: 12px;">&#9989;</div>
            <h2 style="margin: 0 0 8px 0; color: #15803d;">Payment Successful!</h2>
            <p style="color: #4b5563; font-size: 14px; margin: 0 0 16px 0;">Order #{order_id} is confirmed and sent to Dark Store for packing.</p>
            <div style="font-size: 12px; color: #6b7280;">Auto-redirecting back to app...</div>
            <a href="myapp://payment-complete?order_id={order_id}&status=SUCCESS" class="btn">Return to App</a>
        </div>
        <script>
            setTimeout(function() {{
                window.location.href = "myapp://payment-complete?order_id={order_id}&status=SUCCESS";
            }}, 1200);
        </script>
    </body>
    </html>
    """)

@router.post("/cashfree/verify")
def verify_cashfree_payment(
    req: CashfreeVerifyPayload,
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    """
    Server-authoritative Cashfree payment verification. The client NEVER decides success:
    after the Cashfree drop-in closes, the client calls this endpoint with the order_id,
    and the backend re-fetches the order status directly from Cashfree.

    Outcomes:
      - PAID    -> order marked PAID + PACKED, dispatched to the Dark Store.
      - FAILED  / EXPIRED / USER_DROPPED / CANCELLED -> order marked FAILED + CANCELLED,
        inventory restocked, and the failure reason is returned so the client can show
        a clear "Payment Failed" message and keep the cart so the user can retry.
      - ACTIVE / UNKNOWN -> payment still in progress or unverifiable; order left as-is
        so the user can retry without losing the cart.
    """
    order = db.query(Order).filter(Order.id == req.order_id).first()
    if not order:
        order = db.query(Order).filter(Order.order_number == req.order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    result = payment_service.verify_cashfree_order_status(order.order_number)
    if not result.get("success"):
        raise HTTPException(status_code=502, detail="Unable to reach Cashfree to verify payment. Please check your connection and try again.")

    is_paid = result.get("is_paid", False)
    is_failed = result.get("is_failed", False)
    status = result.get("order_status", "UNKNOWN")
    failure_reason = result.get("failure_reason")

    if is_paid and order.payment_status != "PAID":
        order.payment_status = "PAID"
        order.payment_method = "CASHFREE"
        order.status = "PACKED"
        db.commit()
        db.refresh(order)
        # Record a PAID payment ledger row.
        try:
            db.add(Payment(
                order_id=order.id, gateway="CASHFREE",
                gateway_order_id=order.order_number,
                gateway_payment_id=result.get("cf_payment_id"),
                amount=order.grand_total, status="PAID",
                raw_response=str(result),
            ))
            db.commit()
        except Exception:
            db.rollback()
        return {
            "success": True,
            "is_paid": True,
            "is_failed": False,
            "order_id": order.id,
            "order_number": order.order_number,
            "payment_status": order.payment_status,
            "order_status": order.status,
            "gateway_status": status,
            "message": "Payment verified successfully. Order sent to Dark Store packing station.",
        }

    if is_failed and order.status not in ("CANCELLED", "DELIVERED"):
        # Mark the order FAILED + CANCELLED and restock inventory so the products
        # are immediately available for other customers to order.
        order.payment_status = "FAILED"
        order.status = "CANCELLED"
        try:
            for item in order.items:
                variant = db.query(ProductVariant).filter(
                    ProductVariant.weight_label == item.variant_label
                ).first()
                if variant:
                    variant.stock_qty += item.quantity
        except Exception:
            pass
        db.commit()
        db.refresh(order)
        return {
            "success": False,
            "is_paid": False,
            "is_failed": True,
            "order_id": order.id,
            "order_number": order.order_number,
            "payment_status": order.payment_status,
            "order_status": order.status,
            "gateway_status": status,
            "failure_reason": failure_reason or "Payment failed. Please retry with a different payment method.",
            "message": failure_reason or "Payment failed. The order has been cancelled and your cart is restored so you can retry.",
        }

    # ACTIVE or UNKNOWN — payment not yet decided. Do NOT cancel; let the user retry.
    return {
        "success": False,
        "is_paid": False,
        "is_failed": False,
        "order_id": order.id,
        "order_number": order.order_number,
        "payment_status": order.payment_status,
        "order_status": order.status,
        "gateway_status": status,
        "message": f"Cashfree reports order status as {status}. Payment not yet confirmed — please retry.",
    }


@router.post("/cashfree/webhook")
async def cashfree_webhook(
    request: Request,
    x_webhook_signature: Optional[str] = Header(None),
    x_webhook_timestamp: Optional[str] = Header(None),
    db: Session = Depends(get_db),
):
    """
    Signed, idempotent Cashfree webhook listener (v2022-09-01 spec).
    1. Verifies Base64(HMAC-SHA256(timestamp + raw_body, secret)) with a constant-time compare.
    2. Rejects stale timestamps (replay protection, 5 min skew).
    3. Re-fetches the authoritative order status from Cashfree before flipping to PAID —
       so even a signed payload cannot mark an order paid on its own.
    4. Idempotent: a second webhook for the same order is a no-op.
    Fails CLOSED when CASHFREE_WEBHOOK_SECRET is not configured.
    """
    if not settings.CASHFREE_WEBHOOK_SECRET:
        raise HTTPException(status_code=503, detail="Cashfree webhook secret not configured.")

    body = await request.body()
    if not x_webhook_signature or not x_webhook_timestamp:
        raise HTTPException(status_code=400, detail="Missing Cashfree webhook signature headers.")

    if not payment_service.is_timestamp_fresh(x_webhook_timestamp):
        raise HTTPException(status_code=401, detail="Stale webhook timestamp (possible replay).")

    if not payment_service.verify_cashfree_webhook_signature(x_webhook_timestamp, body, x_webhook_signature):
        raise HTTPException(status_code=401, detail="Invalid Cashfree webhook signature.")

    try:
        data = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="Malformed webhook body.")

    # Cashfree webhook payload -> data.order.order_id is our internal order_number
    order_info = (data.get("data") or {}).get("order") or {}
    cf_order_id = order_info.get("order_id") or order_info.get("cf_order_id")
    if not cf_order_id:
        raise HTTPException(status_code=400, detail="Webhook payload missing order id.")

    order = db.query(Order).filter(Order.order_number == cf_order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found for webhook payload.")

    # Idempotent: never re-process an already PAID order
    if order.payment_status == "PAID":
        return {"status": "ok", "message": "Order already PAID (idempotent)."}

    # Re-fetch authoritative status from Cashfree before flipping
    result = payment_service.verify_cashfree_order_status(order.order_number)
    if result.get("is_paid"):
        order.payment_status = "PAID"
        order.payment_method = "CASHFREE"
        order.status = "PACKED"
        db.commit()

    return {"status": "ok"}
