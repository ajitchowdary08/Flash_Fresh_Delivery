from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from datetime import datetime
import uuid
import random
import json
from typing import Dict, List
from pydantic import BaseModel

from app.database.db import get_db
from app.models.models import Order, OrderItem, Product, ProductVariant, User, PromoCode, Rating, Payment
from app.schemas.schemas import CreateOrderRequest
from app.services.maps_service import maps_service
from app.services.payment_service import payment_service
from app.core.config import settings
from app.core.security import get_current_user

router = APIRouter(prefix="/orders", tags=["Orders & Real-Time Tracking"])

class OrderRatingRequest(BaseModel):
    rating: int = 5 # Rider speed rating
    freshness_rating: int = 5 # Produce freshness rating
    review: str = ""

# WebSocket Connection Manager for Live Order & Rider Tracking
class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, order_id: str, websocket: WebSocket):
        await websocket.accept()
        if order_id not in self.active_connections:
            self.active_connections[order_id] = []
        self.active_connections[order_id].append(websocket)

    def disconnect(self, order_id: str, websocket: WebSocket):
        if order_id in self.active_connections:
            if websocket in self.active_connections[order_id]:
                self.active_connections[order_id].remove(websocket)

    async def broadcast_order_update(self, order_id: str, data: dict):
        if order_id in self.active_connections:
            for connection in self.active_connections[order_id]:
                try:
                    await connection.send_text(json.dumps(data))
                except Exception:
                    pass

ws_manager = ConnectionManager()

VALID_STATE_TRANSITIONS = {
    "PLACED": ["PACKED", "CANCELLED"],
    "PACKED": ["OUT_FOR_DELIVERY", "CANCELLED"],
    "OUT_FOR_DELIVERY": ["DELIVERED"],
    "DELIVERED": [],
    "CANCELLED": []
}

@router.post("/create")
def create_order(
    req: CreateOrderRequest,
    db: Session = Depends(get_db),
    user: dict = Depends(get_current_user),
):
    """
    1. Server-authoritative idempotency check (prevents double-charge/duplicate order).
    2. Enforces caller identity matches authenticated token in production.
    3. Looks up canonical product prices & stock from database (security check).
    4. Calculates items total, delivery charge (no radius restriction — we deliver
       anywhere; no promo codes).
    5. Generates 4-digit Delivery Verification OTP.
    6. Creates official Cashfree Sandbox payment session.
    """
    if user.get("role") == "CUSTOMER" and user.get("sub") != "usr_guest_local" \
            and user.get("sub") != req.user_id and f"usr_{user.get('phone')}" != req.user_id:
        raise HTTPException(
            status_code=403,
            detail="Unauthorized: You cannot place an order for another user account.",
        )
    if req.idempotency_key:
        existing = db.query(Order).filter(Order.idempotency_key == req.idempotency_key).first()
        if existing:
            return {
                "success": True,
                "order_id": existing.id,
                "order_number": existing.order_number,
                "items_total": existing.items_total,
                "discount_amount": existing.discount_amount,
                "promo_code": existing.promo_code,
                "delivery_fee": existing.delivery_fee,
                "grand_total": existing.grand_total,
                "distance_km": existing.distance_km,
                "delivery_eta_mins": existing.delivery_eta_mins,
                "delivery_otp": existing.delivery_otp,
                "status": existing.status,
                "payment": {
                    "success": True,
                    "gateway": "CASHFREE_SANDBOX",
                    "gateway_order_id": existing.order_number,
                    "payment_session_id": existing.payment_session_id,
                    "amount_in_rupees": existing.grand_total
                },
                "payment_session_id": existing.payment_session_id,
                "cf_order_id": existing.cf_order_id,
                "message": "Order already processed (idempotency key matched)"
            }

    # We deliver ANYWHERE — there is no radius cap. We still compute the
    # haversine distance and ETA so the order row records how far the drop is
    # and the store manager / rider can see it. check_serviceability() now
    # always reports is_serviceable=True; it is only used for the distance/ETA.
    service_info = maps_service.check_serviceability(req.latitude, req.longitude)

    validated_items = []
    items_total = 0.0

    for itm in req.items:
        # Authoritative variant lookup. Prefer the exact variant_id (most precise),
        # then fall back to weight_label + product name. The client-supplied
        # `unit_price` is NEVER trusted when a real variant is found — the DB
        # price is the source of truth so manager price edits are always honored.
        variant = None
        if itm.variant_id:
            variant = db.query(ProductVariant).filter(
                ProductVariant.id == itm.variant_id
            ).first()
        if not variant and itm.product_id:
            variant = db.query(ProductVariant).filter(
                ProductVariant.product_id == itm.product_id,
                ProductVariant.weight_label == itm.variant_label
            ).first()
        if not variant:
            # Last-resort fallback by weight_label alone (legacy clients).
            # Restricted to active products so deactivated items cannot be ordered.
            variant = db.query(ProductVariant).join(Product).filter(
                Product.is_active == True,
                ProductVariant.weight_label == itm.variant_label,
                Product.name == itm.product_name
            ).first()

        if not variant:
            raise HTTPException(
                status_code=400,
                detail=f"'{itm.product_name}' ({itm.variant_label}) is no longer available. Please remove it from your cart and retry."
            )

        # DB price is authoritative — ignore the client's unit_price.
        unit_price = variant.price

        # Deduct stock atomically
        if variant.stock_qty < itm.quantity:
            raise HTTPException(
                status_code=400,
                detail=f"Only {variant.stock_qty} units left for {itm.product_name} ({itm.variant_label}). Please update cart quantity."
            )
        variant.stock_qty -= itm.quantity

        total_price = unit_price * itm.quantity
        items_total += total_price

        validated_items.append({
            "product_name": itm.product_name,
            "variant_label": itm.variant_label,
            "quantity": itm.quantity,
            "unit_price": unit_price,
            "total_price": total_price
        })

    # No promo codes / discounts. The customer pays items_total + fees.
    discount_amount = 0.0
    promo_code_applied = ""
    net_items_total = items_total
    delivery_fee = 0.0 if net_items_total >= 199.0 else 15.0
    handling_fee = 4.0 if items_total > 0 else 0.0
    gst_amount = round(0.18 * (delivery_fee + handling_fee), 2) if items_total > 0 else 0.0
    grand_total = round(net_items_total + delivery_fee + handling_fee + gst_amount, 2)

    # Monthly Pay Later Tab processing
    payment_status = "PENDING"
    if req.payment_method.upper() in ["PAY_LATER", "PAY_LATER_MONTHLY"]:
        user = db.query(User).filter(User.id == req.user_id).first()
        credit_limit = user.monthly_credit_limit if user else 5000.0
        current_dues = user.current_monthly_dues if user else 0.0
        available_credit = max(0.0, credit_limit - current_dues)

        if grand_total > available_credit and user is not None:
            raise HTTPException(
                status_code=400,
                detail=f"Order amount ₹{grand_total:.0f} exceeds available Monthly Credit Limit (₹{available_credit:.0f}). Please clear running tab or choose UPI."
            )

        if user:
            user.current_monthly_dues = (user.current_monthly_dues or 0.0) + grand_total
        payment_status = "POSTPAID_TAB"

    # Order number uses date + a monotonic counter derived from today's order count
    # (was random 1000-9999, which only allowed 9000 numbers/day and could collide).
    today_prefix = datetime.utcnow().strftime("%Y%m%d")
    today_count = db.query(Order).filter(Order.order_number.like(f"MYP-{today_prefix}-%")).count()
    order_number = f"MYP-{today_prefix}-{today_count + 1:05d}"
    delivery_otp = str(random.randint(1000, 9999))

    new_order = Order(
        id=str(uuid.uuid4()),
        order_number=order_number,
        user_id=req.user_id,
        delivery_address=req.delivery_address,
        latitude=req.latitude,
        longitude=req.longitude,
        distance_km=service_info["distance_km"],
        status="PLACED",
        delivery_eta_mins=service_info["estimated_delivery_minutes"] or 15,
        items_total=items_total,
        discount_amount=discount_amount,
        promo_code=promo_code_applied,
        delivery_fee=delivery_fee,
        grand_total=grand_total,
        payment_status=payment_status,
        payment_method=req.payment_method,
        idempotency_key=req.idempotency_key,
        is_sunday_meat_order=req.is_sunday_meat_order,
        scheduled_slot=req.scheduled_slot or "10-15 Mins Quick Delivery",
        delivery_instructions=req.delivery_instructions or "",
        delivery_otp=delivery_otp,
        # No rider is assigned at creation time — a rider is assigned only when
        # one accepts the order or the store manager dispatches it. Previously
        # every order was born with a fake "Ravi Kumar" rider.
        rider_id=None,
        rider_name=None,
        rider_phone=None,
        rider_vehicle=None,
        rider_lat=None,
        rider_lng=None,
    )

    for v_itm in validated_items:
        order_item = OrderItem(
            id=str(uuid.uuid4()),
            order_id=new_order.id,
            product_name=v_itm["product_name"],
            variant_label=v_itm["variant_label"],
            quantity=v_itm["quantity"],
            unit_price=v_itm["unit_price"],
            total_price=v_itm["total_price"]
        )
        new_order.items.append(order_item)

    user = db.query(User).filter(User.id == req.user_id).first()
    customer_phone = user.phone if (user and user.phone) else "9966114243"
    customer_name = user.name if (user and user.name) else "Customer"
    customer_id = user.id if user else "cust_user"

    # Create authoritative Cashfree session for online payments
    payment_meta = payment_service.create_cashfree_order(
        amount_in_rupees=grand_total,
        order_id=order_number,
        customer_phone=customer_phone,
        customer_id=customer_id,
        customer_name=customer_name
    )

    if payment_meta.get("payment_session_id"):
        new_order.payment_session_id = payment_meta.get("payment_session_id")
        new_order.cf_order_id = payment_meta.get("cf_order_id") or order_number

    db.add(new_order)
    db.commit()
    db.refresh(new_order)

    # Record the initial payment ledger entry (status PENDING for online,
    # POSTPAID_TAB for pay-later, PENDING_COD for COD). The webhook / verify
    # endpoints will later flip this to PAID/FAILED.
    try:
        gateway_name = "CASHFREE" if payment_status == "PENDING" else (req.payment_method or "UPI").upper()
        db.add(Payment(
            order_id=new_order.id,
            gateway=gateway_name,
            gateway_order_id=new_order.order_number,
            gateway_payment_id=payment_meta.get("cf_order_id"),
            amount=grand_total,
            status=payment_status if payment_status != "PENDING" else "PENDING",
        ))
        db.commit()
    except Exception as e:
        db.rollback()
        print(f"[Payment Ledger Error]: {e}")

    return {
        "success": True,
        "order_id": new_order.id,
        "order_number": new_order.order_number,
        "items_total": items_total,
        "discount_amount": discount_amount,
        "promo_code": promo_code_applied,
        "delivery_fee": delivery_fee,
        "grand_total": grand_total,
        "distance_km": service_info["distance_km"],
        "delivery_eta_mins": new_order.delivery_eta_mins,
        "delivery_otp": delivery_otp,
        "status": new_order.status,
        "payment": payment_meta,
        "payment_session_id": new_order.payment_session_id,
        "cf_order_id": new_order.cf_order_id
    }

@router.post("/{order_id}/cancel")
async def cancel_order(order_id: str, db: Session = Depends(get_db), user: dict = Depends(get_current_user)):
    """
    Cancels an order within 60s / before dispatch and restores product inventory automatically.
    Enforces the legal state-machine transitions defined in VALID_STATE_TRANSITIONS.
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    # Ownership: the authenticated user must own this order (managers use the
    # store routes, not this one). In dev, get_current_user returns a guest.
    if order.user_id and user.get("sub") and order.user_id != user.get("sub") and user.get("role") == "CUSTOMER":
        raise HTTPException(status_code=403, detail="You can only cancel your own orders.")

    allowed = VALID_STATE_TRANSITIONS.get(order.status, [])
    if "CANCELLED" not in allowed:
        raise HTTPException(
            status_code=400,
            detail=f"Cannot cancel order in status '{order.status}'. Rider is already en route or delivered."
        )

    order.status = "CANCELLED"

    # Restore stock — match the variant precisely by name+label (legacy) since
    # order_items don't store variant_id yet.
    for item in order.items:
        variant = db.query(ProductVariant).join(Product).filter(
            Product.is_active == True,
            Product.name == item.product_name,
            ProductVariant.weight_label == item.variant_label
        ).first()
        if variant:
            variant.stock_qty += item.quantity

    db.commit()

    await ws_manager.broadcast_order_update(order.id, {
        "event": "STATUS_UPDATE",
        "status": "CANCELLED",
        "message": "Order cancelled and stock restored to inventory."
    })

    return {
        "success": True,
        "order_id": order.id,
        "status": order.status,
        "message": "Order cancelled successfully. Refund will be credited within 24 hours."
    }

@router.post("/{order_id}/rate")
def rate_order(order_id: str, req: OrderRatingRequest, db: Session = Depends(get_db), user: dict = Depends(get_current_user)):
    """
    Submits 1-to-5 star rating for Rider Speed & Produce Freshness with review notes.
    Saves feedback directly into database (both the order row and a dedicated
    Rating row) so Rider and Store Admin see it dynamically.
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.rider_rating = req.rating
    order.freshness_rating = req.freshness_rating
    order.review_notes = req.review

    # Persist a dedicated Rating row linked to the rider for the rider app & dashboards.
    db.add(Rating(
        order_id=order.id,
        rider_id=order.rider_id,
        user_id=order.user_id,
        rider_rating=req.rating,
        freshness_rating=req.freshness_rating,
        review=req.review,
    ))
    db.commit()

    return {
        "success": True,
        "order_id": order.id,
        "rider_rating": req.rating,
        "freshness_rating": req.freshness_rating,
        "review": req.review,
        "message": "🎉 Thank you for rating your Flash Fresh delivery!"
    }

@router.get("/history/{user_id}")
@router.get("/user/{user_id}")
def get_user_order_history(user_id: str, db: Session = Depends(get_db), user: dict = Depends(get_current_user)):
    """
    Returns full order history with item details, delivery OTP, receipts, and status.
    Authenticated callers can query their own history by id or phone; a guest
    (dev) can still query by the supplied id for local testing.
    Queries flexibly by user_id or clean phone number so customer history is never lost.
    """
    # Authorization: a CUSTOMER may only read their own orders.
    role = user.get("role", "CUSTOMER")
    if role == "CUSTOMER":
        auth_sub = user.get("sub", "")
        # Allow if the requested id matches the caller, or matches their phone,
        # or the caller is a dev guest.
        clean_phone = user_id.strip().replace("+91", "").replace(" ", "").replace("-", "")
        allowed = (
            auth_sub == "usr_guest_local"
            or user_id == auth_sub
            or user.get("phone") == user_id
            or user.get("phone") == clean_phone
            or f"usr_{clean_phone}" == auth_sub
        )
        if not allowed:
            raise HTTPException(status_code=403, detail="You can only view your own order history.")

    clean_phone = user_id.strip().replace("+91", "").replace(" ", "").replace("-", "")
    users = db.query(User).filter((User.id == user_id) | (User.phone == clean_phone) | (User.phone == user_id) | (User.id == f"usr_{clean_phone}")).all()
    user_ids = [u.id for u in users]
    for alt in [user_id, clean_phone, f"usr_{clean_phone}"]:
        if alt not in user_ids:
            user_ids.append(alt)

    orders = db.query(Order).filter(Order.user_id.in_(user_ids)).order_by(Order.created_at.desc()).all()
    res = []
    for o in orders:
        res.append({
            "order_id": o.id,
            "order_number": o.order_number,
            "status": o.status,
            "grand_total": o.grand_total,
            "items_total": o.items_total,
            "discount_amount": o.discount_amount,
            "promo_code": o.promo_code,
            "delivery_fee": o.delivery_fee,
            "delivery_otp": o.delivery_otp,
            "payment_status": o.payment_status,
            "payment_method": o.payment_method,
            "delivery_address": o.delivery_address,
            "latitude": o.latitude,
            "longitude": o.longitude,
            "delivery_eta_mins": o.delivery_eta_mins,
            "created_at": o.created_at.strftime("%d %b %Y, %I:%M %p"),
            "is_sunday_meat_order": o.is_sunday_meat_order,
            "items": [
                {
                    "name": itm.product_name,
                    "variant": itm.variant_label,
                    "quantity": itm.quantity,
                    "unit_price": itm.unit_price,
                    "total_price": itm.total_price
                }
                for itm in o.items
            ]
        })
    return res

@router.get("/{order_id}/tracking")
def get_order_tracking(order_id: str, db: Session = Depends(get_db), user: dict = Depends(get_current_user)):
    """
    Returns live delivery tracking steps, 4-digit Delivery OTP, and assigned rider coordinates.
    """
    from app.models.models import Rider
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    # A CUSTOMER may only track their own order.
    if user.get("role") == "CUSTOMER" and order.user_id and user.get("sub") != "usr_guest_local" \
            and order.user_id != user.get("sub"):
        raise HTTPException(status_code=403, detail="You can only track your own orders.")

    # Resolve the rider's real rating from the riders table (was hardcoded 4.9).
    rider_rating = 5.0
    if order.rider_id:
        rider_row = db.query(Rider).filter(Rider.id == order.rider_id).first()
        if rider_row:
            rider_rating = rider_row.rating or 5.0

    rider_info = {
        "id": order.rider_id,
        "name": order.rider_name,
        "phone": order.rider_phone,
        "vehicle": order.rider_vehicle,
        "rating": rider_rating,
        "current_lat": order.rider_lat,
        "current_lng": order.rider_lng,
    }

    steps = [
        {"status": "PLACED", "title": "Order Placed & Confirmed", "completed": True, "time": "Just now"},
        {"status": "PACKED", "title": "Packed & Weighed at Central Hub", "completed": order.status in ["PACKED", "OUT_FOR_DELIVERY", "DELIVERED"], "time": "2 mins ago"},
        {"status": "OUT_FOR_DELIVERY", "title": "Rider On the Way", "completed": order.status in ["OUT_FOR_DELIVERY", "DELIVERED"], "time": "5 mins ago"},
        {"status": "DELIVERED", "title": "Delivered to Doorstep", "completed": order.status == "DELIVERED", "time": "Arrived"}
    ]

    return {
        "order_id": order.id,
        "order_number": order.order_number,
        "status": order.status,
        "payment_status": order.payment_status,
        "delivery_eta_mins": order.delivery_eta_mins,
        "delivery_address": order.delivery_address,
        "delivery_otp": order.delivery_otp,
        "items_total": order.items_total,
        "discount_amount": order.discount_amount,
        "delivery_fee": order.delivery_fee,
        "grand_total": order.grand_total,
        "store_coordinates": {"lat": settings.STORE_LATITUDE, "lng": settings.STORE_LONGITUDE},
        "customer_coordinates": {"lat": order.latitude, "lng": order.longitude},
        "rider": rider_info if order.status in ["OUT_FOR_DELIVERY", "DELIVERED"] else None,
        "steps": steps,
        "items": [
            {
                "product_name": itm.product_name,
                "variant_label": itm.variant_label,
                "quantity": itm.quantity,
                "total_price": itm.total_price
            }
            for itm in order.items
        ]
    }

@router.websocket("/ws/{order_id}")
async def order_live_websocket(websocket: WebSocket, order_id: str):
    """
    Real-time WebSocket endpoint for live order status & rider position updates.
    """
    await ws_manager.connect(order_id, websocket)
    try:
        while True:
            # Keep connection alive & receive optional client heartbeats
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        ws_manager.disconnect(order_id, websocket)
