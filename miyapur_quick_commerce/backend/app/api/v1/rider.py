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
def get_rider_profile():
    """
    Returns current rider profile and online status.
    """
    return RIDER_STATE

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
            "payout_amount": payout,
            "scheduled_slot": o.scheduled_slot,
            "pickup_hub": "Miyapur Central Dark Store (Metro Pillar 84)",
            "customer_phone": "+91 98765 43210",
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
        "message": f"Order {order.order_number} accepted! Proceed to Miyapur Dark Store Hub for pickup."
    }

@router.post("/orders/{order_id}/pickup")
async def pickup_order(order_id: str, db: Session = Depends(get_db)):
    """
    Rider collects packed bag from Miyapur Hub and departs.
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
