from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import Optional, Dict, Any
from pydantic import BaseModel

from app.database.db import get_db
from app.models.models import Order
from app.schemas.schemas import RiderLocationUpdate, VerifyDeliveryOTPRequest
from app.api.v1.orders import ws_manager
from app.core.security import get_current_rider

router = APIRouter(prefix="/rider", tags=["Delivery Partner (Rider) Operations"])

class RiderDutyUpdate(BaseModel):
    rider_id: str
    is_online: bool
    current_lat: Optional[float] = 17.495101
    current_lng: Optional[float] = 78.367535

# In-memory rider state
RIDER_STATE = {
    "rider_id": "rdr_ravi_01",
    "name": "Ravi Kumar",
    "phone": "+91 98480 12345",
    "vehicle": "Hero Electric (TS 07 EK 4921)",
    "rating": 4.9,
    "is_online": True,
    "today_earnings": 385.0,
    "completed_trips_today": 9,
    "current_lat": 17.495101,
    "current_lng": 78.367535,
}

@router.get("/profile")
def get_rider_profile(db: Session = Depends(get_db)):
    """
    Returns current rider profile, live DB rating stats, completed trips, and online status.
    """
    delivered_orders = db.query(Order).filter(
        Order.rider_id == RIDER_STATE["rider_id"],
        Order.status == "DELIVERED"
    ).all()

    completed_trips = len(delivered_orders)
    today_earnings = sum(35.0 + (10.0 if o.distance_km > 3.0 else 0.0) for o in delivered_orders)
    cod_collected = sum(o.grand_total for o in delivered_orders if (o.payment_method or "").upper() == "COD")

    rated_orders = db.query(Order).filter(Order.rider_rating.isnot(None)).all()
    avg_rating = round(sum(o.rider_rating for o in rated_orders) / len(rated_orders), 1) if rated_orders else 5.0

    return {
        "rider_id": RIDER_STATE["rider_id"],
        "name": RIDER_STATE["name"],
        "phone": RIDER_STATE["phone"],
        "vehicle": RIDER_STATE["vehicle"],
        "rating": avg_rating,
        "is_online": RIDER_STATE["is_online"],
        "today_earnings": today_earnings,
        "completed_trips_today": completed_trips,
        "cod_cash_in_hand": cod_collected,
        "current_lat": RIDER_STATE["current_lat"],
        "current_lng": RIDER_STATE["current_lng"],
    }

@router.get("/earnings")
def get_rider_earnings(db: Session = Depends(get_db)):
    """
    Returns 100% dynamic earnings, trip breakdowns, incentives, and COD floating cash from DB.
    """
    delivered_orders = db.query(Order).filter(
        Order.rider_id == RIDER_STATE["rider_id"],
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
def get_rider_reviews(db: Session = Depends(get_db)):
    """
    Returns live customer rating average, total rating count, and recent reviews from database.
    """
    rated_orders = db.query(Order).filter(Order.rider_rating.isnot(None)).order_by(Order.created_at.desc()).all()

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
def toggle_duty(update: RiderDutyUpdate):
    """
    Toggle rider online/offline duty.
    """
    RIDER_STATE["is_online"] = update.is_online
    return {
        "success": True,
        "is_online": RIDER_STATE["is_online"],
        "message": "You are now ONLINE and will receive delivery orders!" if update.is_online else "You are now OFFLINE."
    }

@router.get("/orders/available")
def get_available_orders(db: Session = Depends(get_db)):
    """
    Fetches orders that are PACKED or PLACED and ready for delivery partner pickup.
    """
    orders = db.query(Order).filter(Order.status.in_(["PLACED", "PACKED", "OUT_FOR_DELIVERY"])).order_by(Order.created_at.desc()).all()
    
    res = []
    for o in orders:
        payout = 35.0 + (10.0 if o.distance_km > 3.0 else 0.0)
        res.append({
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
            "pickup_hub": "Flash Fresh Central Dark Store (Metro Pillar 84)",
            "customer_phone": "+91 98765 43210",
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
        })
    return res

@router.post("/orders/{order_id}/accept")
async def accept_order(order_id: str, db: Session = Depends(get_db)):
    """
    Rider accepts order atomically to prevent double claiming.
    """
    order = db.query(Order).filter(Order.id == order_id).with_for_update().first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    if order.status in ["OUT_FOR_DELIVERY", "DELIVERED"]:
        raise HTTPException(status_code=400, detail="Order has already been picked up or delivered by another rider.")

    if order.rider_id and order.rider_id != RIDER_STATE["rider_id"] and order.status == "OUT_FOR_DELIVERY":
        raise HTTPException(status_code=400, detail="Order has already been accepted by another fleet partner.")

    order.status = "PACKED"
    order.rider_id = RIDER_STATE["rider_id"]
    order.rider_name = RIDER_STATE["name"]
    order.rider_phone = RIDER_STATE["phone"]
    order.rider_vehicle = RIDER_STATE["vehicle"]

    db.commit()
    db.refresh(order)

    # Broadcast update to connected customers
    await ws_manager.broadcast_order_update(order.id, {
        "event": "STATUS_UPDATE",
        "status": order.status,
        "message": f"Delivery partner {order.rider_name} assigned and heading to dark store."
    })

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "status": order.status,
        "message": f"Order {order.order_number} accepted! Proceed to Central Dark Store Hub for pickup."
    }

@router.post("/orders/{order_id}/pickup")
async def pickup_order(order_id: str, db: Session = Depends(get_db)):
    """
    Rider collects packed bag from Central Hub and departs.
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.status = "OUT_FOR_DELIVERY"
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
async def update_rider_location(req: RiderLocationUpdate, db: Session = Depends(get_db)):
    """
    Updates rider live GPS coordinates and broadcasts to customer's live tracking map.
    """
    order = db.query(Order).filter(Order.id == req.order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.rider_lat = req.latitude
    order.rider_lng = req.longitude
    RIDER_STATE["current_lat"] = req.latitude
    RIDER_STATE["current_lng"] = req.longitude

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
async def verify_delivery_otp(req: VerifyDeliveryOTPRequest, db: Session = Depends(get_db)):
    """
    Rider enters customer's 4-digit Delivery PIN code at doorstep.
    """
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
    RIDER_STATE["today_earnings"] += payout
    RIDER_STATE["completed_trips_today"] += 1

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
        "total_today_earnings": RIDER_STATE["today_earnings"],
        "message": f"Order {order.order_number} verified with OTP & delivered! ₹{payout:.0f} credited to wallet."
    }
