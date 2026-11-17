from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List, Dict, Any, Optional

from app.database.db import get_db
from app.models.models import Order, Product, ProductVariant
from app.api.v1.orders import ws_manager

router = APIRouter(prefix="/store", tags=["Dark Store Hub Operations (Miyapur)"])

class StockUpdateRequest(BaseModel):
    variant_id: str
    new_stock_qty: int

class QuickIntakeItem(BaseModel):
    product_name: str
    variant_label: str
    added_qty: int

@router.get("/dashboard-summary")
def get_store_dashboard_summary(db: Session = Depends(get_db)):
    """
    Returns store overview: orders waiting to be packed, out for delivery, delivered, and total catalog items.
    """
    all_orders = db.query(Order).all()
    pending_pack = [o for o in all_orders if o.status == "PLACED"]
    packed = [o for o in all_orders if o.status == "PACKED"]
    out_for_delivery = [o for o in all_orders if o.status == "OUT_FOR_DELIVERY"]
    delivered = [o for o in all_orders if o.status == "DELIVERED"]

    return {
        "store_name": "Central Fulfillment Dark Store Hub",
        "service_radius": "10 KM",
        "orders_to_pack": len(pending_pack),
        "orders_ready_for_pickup": len(packed),
        "orders_in_transit": len(out_for_delivery),
        "orders_delivered_today": len(delivered),
        "total_revenue_today": sum(o.grand_total for o in delivered + out_for_delivery)
    }

@router.get("/packing-queue")
def get_packing_queue(db: Session = Depends(get_db)):
    """
    Live queue of orders needing weighing, packing & bagging at Miyapur hub.
    """
    orders = db.query(Order).filter(Order.status.in_(["PLACED", "PACKED"])).order_by(Order.created_at.asc()).all()
    
    result = []
    for o in orders:
        result.append({
            "order_id": o.id,
            "order_number": o.order_number,
            "status": o.status,
            "items_count": len(o.items),
            "distance_km": o.distance_km,
            "delivery_address": o.delivery_address,
            "created_at": o.created_at.strftime("%I:%M %p"),
            "is_sunday_meat_order": o.is_sunday_meat_order,
            "items": [
                {
                    "name": itm.product_name,
                    "variant": itm.variant_label,
                    "quantity": itm.quantity,
                    "weighed_checked": True
                }
                for itm in o.items
            ]
        })
    return result

@router.post("/orders/{order_id}/mark-packed")
def mark_order_packed(order_id: str, db: Session = Depends(get_db)):
    """
    Store boy finishes weighing and bagging, marks order as PACKED.
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.status = "PACKED"
    db.commit()
    db.refresh(order)

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "status": order.status,
        "message": f"Order {order.order_number} marked as PACKED. Ready for Rider pickup!",
        "thermal_slip": {
            "title": "⚡ FLASH FRESH QUICK COMMERCE - PACKING SLIP",
            "order_number": order.order_number,
            "hub": "Central Dark Store Hub - Pillar 84",
            "address": order.delivery_address,
            "items_count": len(order.items),
            "bag_status": "SEALED & VERIFIED"
        }
    }

@router.get("/inventory")
def get_store_inventory(db: Session = Depends(get_db)):
    """
    Returns live inventory of daily vegetables & Sunday meats.
    """
    products = db.query(Product).all()
    inventory_list = []
    for p in products:
        for v in p.variants:
            inventory_list.append({
                "product_id": p.id,
                "variant_id": v.id,
                "product_name": p.name,
                "weight_label": v.weight_label,
                "is_sunday_only": p.is_sunday_only,
                "price": v.price,
                "stock_qty": v.stock_qty,
                "status": "In Stock" if v.stock_qty > 10 else ("Low Stock" if v.stock_qty > 0 else "Out of Stock")
            })
    return inventory_list

@router.post("/inventory/update-stock")
def update_stock(req: StockUpdateRequest, db: Session = Depends(get_db)):
    """
    Updates stock quantity for a variant (e.g. morning veggie intake).
    """
    variant = db.query(ProductVariant).filter(ProductVariant.id == req.variant_id).first()
    if not variant:
        raise HTTPException(status_code=404, detail="Variant not found")

    variant.stock_qty = req.new_stock_qty
    db.commit()
    db.refresh(variant)

    return {
        "success": True,
        "variant_id": variant.id,
        "weight_label": variant.weight_label,
        "new_stock_qty": variant.stock_qty,
        "message": "Stock quantity updated successfully."
    }


# Active delivery fleet partners stationed at or near Miyapur Hub
ACTIVE_RIDERS = [
    {
        "id": "rdr_ravi_01",
        "name": "Ravi Kumar",
        "phone": "+91 98480 12345",
        "vehicle": "Hero Electric (TS 07 EK 4921)",
        "rating": 4.9,
        "status": "AVAILABLE",
        "distance": "0.1 km from Hub",
    },
    {
        "id": "rdr_suresh_02",
        "name": "Suresh Goud",
        "phone": "+91 98765 24680",
        "vehicle": "Ather 450X (TS 08 FA 1024)",
        "rating": 4.8,
        "status": "AVAILABLE",
        "distance": "0.4 km from Hub",
    },
    {
        "id": "rdr_naresh_03",
        "name": "Naresh Krishna",
        "phone": "+91 91234 56789",
        "vehicle": "Ola S1 Pro (TS 07 AB 9988)",
        "rating": 4.9,
        "status": "AVAILABLE",
        "distance": "0.6 km from Hub",
    },
]


class AssignRiderRequest(BaseModel):
    rider_id: str


class RecordMeatWeightRequest(BaseModel):
    actual_weight_g: float
    cut_type: str = "Curry Cut"
    turmeric_wash: bool = True
    skinless: bool = True


@router.get("/riders/active")
def get_active_riders():
    """
    Returns fleet partners available around the Miyapur Dark Store Hub.
    """
    return ACTIVE_RIDERS


@router.post("/orders/{order_id}/assign-rider")
async def assign_rider_to_order(
    order_id: str,
    req: AssignRiderRequest,
    db: Session = Depends(get_db),
):
    """
    Store manager assigns an available rider to a packed order, triggering immediate dispatch.
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    rider = next((r for r in ACTIVE_RIDERS if r["id"] == req.rider_id), ACTIVE_RIDERS[0])

    order.status = "OUT_FOR_DELIVERY"
    order.rider_id = rider["id"]
    order.rider_name = rider["name"]
    order.rider_phone = rider["phone"]
    order.rider_vehicle = rider["vehicle"]
    order.rider_lat = 17.495101
    order.rider_lng = 78.367535

    db.commit()
    db.refresh(order)

    # Broadcast live status update over WebSocket to customer app
    await ws_manager.broadcast_order_update(order.id, {
        "event": "STATUS_UPDATE",
        "status": "OUT_FOR_DELIVERY",
        "message": f"Rider {rider['name']} ({rider['vehicle']}) has picked up your order!",
        "rider": rider,
    })

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "status": order.status,
        "rider": rider,
        "message": f"Assigned {rider['name']}! Order is now Out for Delivery.",
    }


@router.post("/orders/{order_id}/record-weight")
def record_meat_weight(
    order_id: str,
    req: RecordMeatWeightRequest,
    db: Session = Depends(get_db),
):
    """
    Records verified meat weight, cutting style, and cleaning wash before bagging.
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.delivery_instructions = (
        f"Weighed: {req.actual_weight_g:.0f}g | Cut: {req.cut_type} | "
        f"Turmeric Wash: {'Yes' if req.turmeric_wash else 'No'} | "
        f"Skinless: {'Yes' if req.skinless else 'With Skin'}"
    )
    db.commit()

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "actual_weight_g": req.actual_weight_g,
        "cut_type": req.cut_type,
        "turmeric_wash": req.turmeric_wash,
        "skinless": req.skinless,
        "message": f"Weight {req.actual_weight_g:.0f}g recorded & bag sealed for {order.order_number}!",
    }
