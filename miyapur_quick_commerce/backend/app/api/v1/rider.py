from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import Optional, Dict, Any
from pydantic import BaseModel

from app.database.db import get_db
from app.models.models import Order, Rider, RiderLocation
from app.schemas.schemas import RiderLocationUpdate, VerifyDeliveryOTPRequest
from app.api.v1.orders import ws_manager
from app.core.security import get_current_rider
from app.core.config import settings
from datetime import datetime

router = APIRouter(prefix="/rider", tags=["Delivery Partner (Rider) Operations"])

class RiderDutyUpdate(BaseModel):
    is_online: bool
    current_lat: Optional[float] = None
    current_lng: Optional[float] = None


def _resolve_rider(auth: dict, db: Session) -> Rider:
    """Resolves the Rider row from the auth payload. Falls back to the first
    active rider in dev (no token)."""
    r = auth.get("rider")
    if r is not None:
        return r
    # Dev fallback when no token was supplied.
    r = db.query(Rider).filter(Rider.is_active == True).first()
    if not r:
        raise HTTPException(status_code=404, detail="No active riders configured.")
    return r


@router.get("/profile")
def get_rider_profile(auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Returns current rider profile, live DB rating stats, completed trips, and online status.
    """
    r = _resolve_rider(auth, db)
    delivered_orders = db.query(Order).filter(
        Order.rider_id == r.id, Order.status == "DELIVERED"
    ).all()

    completed_trips = len(delivered_orders)
    today_earnings = sum(35.0 + (10.0 if o.distance_km > 3.0 else 0.0) for o in delivered_orders)
    cod_collected = sum(o.grand_total for o in delivered_orders if (o.payment_method or "").upper() == "COD")

    rated_orders = db.query(Order).filter(Order.rider_rating.isnot(None)).all()
    avg_rating = round(sum(o.rider_rating for o in rated_orders) / len(rated_orders), 1) if rated_orders else 5.0

    return {
        "rider_id": r.id,
        "name": r.name,
        "phone": r.phone,
        "vehicle": r.vehicle or "—",
        "rating": avg_rating,
        "is_online": r.is_online,
        "today_earnings": today_earnings,
        "completed_trips_today": completed_trips,
        "cod_cash_in_hand": cod_collected,
        "current_lat": r.current_lat,
        "current_lng": r.current_lng,
    }

@router.get("/earnings")
def get_rider_earnings(auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Returns 100% dynamic earnings, trip breakdowns, incentives, and COD floating cash from DB.
    """
    r = _resolve_rider(auth, db)
    delivered_orders = db.query(Order).filter(
        Order.rider_id == r.id,
        Order.status == "DELIVERED"
    ).order_by(Order.created_at.desc()).all()

    completed_trips = len(delivered_orders)
    base_pay = completed_trips * 35.0
    distance_bonus = sum(10.0 for o in delivered_orders if o.distance_km > 3.0)
    meat_incentive = sum(15.0 for o in delivered_orders if o.is_sunday_meat_order)
    today_earnings = base_pay + distance_bonus + meat_incentive
    cod_cash_in_hand = sum(o.grand_total for o in delivered_orders if (o.payment_method or "").upper() == "COD")

    # Dynamic Daily Incentive Milestones
    m1_achieved = completed_trips >= 5
    m2_achieved = completed_trips >= 10
    m3_achieved = completed_trips >= 15
    incentive_bonus = (50.0 if m1_achieved else 0.0) + (70.0 if m2_achieved else 0.0) + (80.0 if m3_achieved else 0.0)

    trips_history = []
    for o in delivered_orders[:20]:
        payout = 35.0 + (10.0 if o.distance_km > 3.0 else 0.0) + (15.0 if o.is_sunday_meat_order else 0.0)
        trips_history.append({
            "order_id": o.id,
            "order_number": o.order_number,
            "delivery_address": o.delivery_address,
            "distance_km": o.distance_km,
            "payout": payout,
            "payment_method": o.payment_method or "ONLINE",
            "grand_total": o.grand_total,
            "delivered_at": o.created_at.strftime("%I:%M %p")
        })

    return {
        "success": True,
        "today_earnings": today_earnings + incentive_bonus,
        "completed_trips": completed_trips,
        "base_pay": base_pay,
        "distance_bonus": distance_bonus,
        "meat_incentive": meat_incentive,
        "incentive_bonus": incentive_bonus,
        "cod_cash_in_hand": cod_cash_in_hand,
        "hub_deposit_limit": 1500.0,
        "milestones": [
            {"tier": "Tier 1: 5 Deliveries", "reward": "+₹50 Bonus", "target": 5, "achieved": m1_achieved},
            {"tier": "Tier 2: 10 Deliveries", "reward": "+₹120 Bonus", "target": 10, "achieved": m2_achieved},
            {"tier": "Tier 3: 15 Deliveries", "reward": "+₹200 Bonus", "target": 15, "achieved": m3_achieved},
        ],
        "trips_history": trips_history,
        "settlement_info": "Every Tuesday directly to Bank A/c"
    }

@router.get("/reviews")
def get_rider_reviews(auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Returns live customer rating average, total rating count, and recent reviews from database.
    """
    r = _resolve_rider(auth, db)
    rated_orders = db.query(Order).filter(
        Order.rider_id == r.id, Order.rider_rating.isnot(None)
    ).order_by(Order.created_at.desc()).all()

    total_ratings = len(rated_orders)
    if total_ratings > 0:
        avg_rating = round(sum(o.rider_rating for o in rated_orders) / total_ratings, 1)
    else:
        avg_rating = 5.0

    recent_reviews = []
    for o in rated_orders[:15]:
        recent_reviews.append({
            "order_number": o.order_number or f"#MYP-{o.id[:8]}",
            "rider_rating": o.rider_rating,
            "freshness_rating": o.freshness_rating or 5,
            "review": o.review_notes or "Fast 10-minute delivery!",
            "date": o.created_at.strftime("%d %b, %I:%M %p")
        })

    return {
        "success": True,
        "avg_rating": avg_rating,
        "total_ratings": total_ratings,
        "recent_reviews": recent_reviews
    }

@router.post("/duty")
def toggle_duty(update: RiderDutyUpdate, auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Toggle rider online/offline duty. Persists to the riders table (was in-memory).
    """
    r = _resolve_rider(auth, db)
    r.is_online = update.is_online
    if update.current_lat is not None:
        r.current_lat = update.current_lat
    if update.current_lng is not None:
        r.current_lng = update.current_lng
    db.commit()
    db.refresh(r)
    return {
        "success": True,
        "is_online": r.is_online,
        "message": "You are now ONLINE and will receive delivery orders!" if update.is_online else "You are now OFFLINE."
    }

def _serialize_order_for_rider(o: Order) -> dict:
    payout = 35.0 + (10.0 if o.distance_km > 3.0 else 0.0)
    return {
        "order_id": o.id,
        "order_number": o.order_number,
        "status": o.status,
        "items_count": len(o.items),
        "distance_km": o.distance_km,
        "delivery_address": o.delivery_address,
        "delivery_otp": o.delivery_otp,
        "grand_total": o.grand_total,
        "payment_method": o.payment_method or "ONLINE",
        "payment_status": o.payment_status or "PAID",
        "payout_amount": payout,
        "scheduled_slot": o.scheduled_slot,
        "pickup_hub": settings.STORE_NAME,
        "customer_phone": o.user.phone if (o.user and o.user.phone) else "—",
        "latitude": o.latitude,
        "longitude": o.longitude,
        "rider_lat": o.rider_lat,
        "rider_lng": o.rider_lng,
        "items": [
            {
                "name": itm.product_name,
                "variant": itm.variant_label,
                "quantity": itm.quantity
            }
            for itm in o.items
        ]
    }

@router.get("/orders/available")
def get_available_orders(auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Fetches orders that are PACKED by dark store and ready for delivery partner pickup.
    Only orders that are packed (or assigned to this rider) are eligible for pickup.
    """
    r = _resolve_rider(auth, db)  # ensures caller is a valid rider
    orders = db.query(Order).filter(
        (
            (Order.status == "PACKED") & (
                Order.rider_id.is_(None) |
                (Order.rider_id == r.id) |
                (Order.rider_phone == r.phone)
            )
        ) | (
            (Order.status == "OUT_FOR_DELIVERY") & (
                (Order.rider_id == r.id) |
                (Order.rider_phone == r.phone)
            )
        )
    ).order_by(Order.created_at.desc()).all()

    return [_serialize_order_for_rider(o) for o in orders]

@router.get("/orders/assigned")
def get_assigned_orders(auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Returns orders explicitly assigned to this delivery partner that are not yet delivered.
    """
    r = _resolve_rider(auth, db)
    orders = db.query(Order).filter(
        (Order.rider_id == r.id) | (Order.rider_phone == r.phone),
        Order.status.in_(["PACKED", "OUT_FOR_DELIVERY"])
    ).order_by(Order.created_at.desc()).all()

    return [_serialize_order_for_rider(o) for o in orders]

@router.post("/orders/{order_id}/accept")
async def accept_order(order_id: str, auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Rider accepts order atomically to prevent double claiming.
    Requires order to have been packed by dark store.
    """
    r = _resolve_rider(auth, db)
    order = db.query(Order).filter(Order.id == order_id).with_for_update().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.status == "PLACED":
        raise HTTPException(status_code=400, detail="Order is still being prepared & packed by dark store. Please wait until packed.")

    if order.status == "DELIVERED":
        raise HTTPException(status_code=400, detail="Order has already been delivered.")

    if order.status == "OUT_FOR_DELIVERY":
        if order.rider_id == r.id or order.rider_phone == r.phone:
            return {
                "success": True,
                "order_id": order.id,
                "order_number": order.order_number,
                "status": order.status,
                "message": f"Order {order.order_number} is out for delivery. Resuming navigation."
            }
        raise HTTPException(status_code=400, detail="Order has already been picked up by another rider.")

    if order.rider_id and order.rider_id != r.id and order.rider_phone != r.phone:
        raise HTTPException(status_code=400, detail="Order has already been accepted by another fleet partner.")

    order.rider_id = r.id
    order.rider_name = r.name
    order.rider_phone = r.phone
    order.rider_vehicle = r.vehicle

    db.commit()
    db.refresh(order)

    # Broadcast update to connected customers
    await ws_manager.broadcast_order_update(order.id, {
        "event": "STATUS_UPDATE",
        "status": order.status,
        "rider_id": order.rider_id,
        "rider_name": order.rider_name,
        "message": f"Delivery partner {order.rider_name} assigned and heading to dark store."
    })

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "status": order.status,
        "message": f"Order {order.order_number} accepted! Proceed to Central Dark Store Hub for pickup."
    }

@router.post("/orders/{order_id}/reject")
async def reject_order(order_id: str, req: dict, auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """Rider declines an order with a reason, so it can be re-dispatched."""
    _resolve_rider(auth, db)
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    reason = (req.get("reason") or "Rider declined").strip()
    # If this rider had been auto-assigned, clear the assignment so the store can re-assign.
    if order.rider_id == auth.get("rider_id") or order.rider_id == auth.get("sub"):
        order.rider_id = None
        order.rider_name = None
        order.rider_phone = None
        order.rider_vehicle = None
        db.commit()

        await ws_manager.broadcast_order_update(order.id, {
            "event": "RIDER_UNASSIGNED",
            "status": order.status,
            "message": "Delivery partner was unassigned. Searching for nearest available rider..."
        })

    return {"success": True, "order_id": order.id, "reason": reason,
            "message": f"Order {order.order_number} declined. It will be re-offered to other riders."}

@router.post("/orders/{order_id}/pickup")
async def pickup_order(order_id: str, auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Rider collects packed bag from Central Hub and departs.
    """
    r = _resolve_rider(auth, db)
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    if order.rider_id and order.rider_id != r.id:
        raise HTTPException(status_code=403, detail="This order is assigned to another rider.")

    order.status = "OUT_FOR_DELIVERY"
    order.rider_lat = settings.STORE_LATITUDE
    order.rider_lng = settings.STORE_LONGITUDE
    db.commit()
    db.refresh(order)

    await ws_manager.broadcast_order_update(order.id, {
        "event": "STATUS_UPDATE",
        "status": order.status,
        "message": "Rider picked up your order bag and is on the way!"
    })

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "status": order.status,
        "message": f"Order {order.order_number} picked up! Navigate to customer."
    }

@router.post("/location/update")
async def update_rider_location(req: RiderLocationUpdate, auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Updates rider live GPS coordinates, persists a location-history row, and
    broadcasts to the customer's live tracking map.
    """
    r = _resolve_rider(auth, db)
    order = db.query(Order).filter(Order.id == req.order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.rider_lat = req.latitude
    order.rider_lng = req.longitude
    r.current_lat = req.latitude
    r.current_lng = req.longitude

    # Persist location history (powers tracking replay & audit).
    db.add(RiderLocation(
        rider_id=r.id, order_id=order.id,
        latitude=req.latitude, longitude=req.longitude,
    ))
    db.commit()

    # Broadcast new rider coordinates via WebSocket
    await ws_manager.broadcast_order_update(order.id, {
        "event": "LOCATION_UPDATE",
        "status": order.status,
        "rider_lat": req.latitude,
        "rider_lng": req.longitude,
    })

    return {"success": True, "order_id": order.id, "lat": req.latitude, "lng": req.longitude}

@router.post("/orders/verify-delivery")
async def verify_delivery_otp(req: VerifyDeliveryOTPRequest, auth: dict = Depends(get_current_rider), db: Session = Depends(get_db)):
    """
    Rider enters customer's 4-digit Delivery PIN code at doorstep.
    """
    r = _resolve_rider(auth, db)
    order = db.query(Order).filter(Order.id == req.order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.delivery_otp != req.otp.strip():
        raise HTTPException(status_code=400, detail="Invalid Delivery PIN code! Please ask customer for correct 4-digit OTP shown on their screen.")

    order.status = "DELIVERED"
    order.payment_status = "PAID"
    db.commit()
    db.refresh(order)

    payout = 35.0 + (10.0 if order.distance_km > 3.0 else 0.0)
    # Persist earnings to the rider row (was in-memory RIDER_STATE).
    r.today_earnings = (r.today_earnings or 0.0) + payout
    r.completed_trips_today = (r.completed_trips_today or 0) + 1
    if (order.payment_method or "").upper() == "COD":
        r.cod_cash_in_hand = (r.cod_cash_in_hand or 0.0) + order.grand_total
    db.commit()

    await ws_manager.broadcast_order_update(order.id, {
        "event": "STATUS_UPDATE",
        "status": "DELIVERED",
        "message": "Order successfully delivered! Thank you for ordering from Flash Fresh Quick Commerce."
    })

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "status": order.status,
        "earned": payout,
        "total_today_earnings": r.today_earnings,
        "message": f"Order {order.order_number} verified with OTP & delivered! ₹{payout:.0f} credited to wallet."
    }
