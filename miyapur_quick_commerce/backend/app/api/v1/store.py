from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import uuid

from app.database.db import get_db
from app.models.models import Order, Product, ProductVariant, Category, Rider
from app.api.v1.orders import ws_manager
from app.core.security import get_current_store_manager

router = APIRouter(prefix="/store", tags=["Dark Store Hub Operations"])

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
        "service_radius": "Full City Delivery",
        "orders_to_pack": len(pending_pack),
        "orders_ready_for_pickup": len(packed),
        "orders_in_transit": len(out_for_delivery),
        "orders_delivered_today": len(delivered),
        "total_revenue_today": sum(o.grand_total for o in delivered + out_for_delivery)
    }

@router.get("/packing-queue")
def get_packing_queue(db: Session = Depends(get_db)):
    """
    Live queue of orders needing weighing, packing & bagging at central hub.
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
def get_active_riders(db: Session = Depends(get_db)):
    """
    Returns active fleet partners directly from the SQL database.
    """
    riders = db.query(Rider).filter(Rider.is_online == True).all()
    res = []
    for r in riders:
        res.append({
            "id": r.id,
            "name": r.name,
            "phone": r.phone,
            "vehicle": r.vehicle,
            "rating": r.rating,
            "status": "AVAILABLE",
            "distance": "0.2 km from Hub",
        })
    return res


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

    rider = db.query(Rider).filter(Rider.id == req.rider_id).first()
    if not rider:
        rider = db.query(Rider).first()

    rider_info = {
        "id": rider.id if rider else "rdr_ravi_01",
        "name": rider.name if rider else "Ravi Kumar",
        "phone": rider.phone if rider else "+91 98480 12345",
        "vehicle": rider.vehicle if rider else "Hero Electric (TS 07 EK 4921)",
        "rating": rider.rating if rider else 4.9,
    }

    order.status = "OUT_FOR_DELIVERY"
    order.rider_id = rider_info["id"]
    order.rider_name = rider_info["name"]
    order.rider_phone = rider_info["phone"]
    order.rider_vehicle = rider_info["vehicle"]
    order.rider_lat = rider.current_lat if rider else 17.495101
    order.rider_lng = rider.current_lng if rider else 78.367535

    db.commit()
    db.refresh(order)

    # Broadcast live status update over WebSocket to customer app
    await ws_manager.broadcast_order_update(order.id, {
        "event": "STATUS_UPDATE",
        "status": "OUT_FOR_DELIVERY",
        "message": f"Rider {rider_info['name']} ({rider_info['vehicle']}) has picked up your order!",
        "rider": rider_info,
    })

    return {
        "success": True,
        "order_id": order.id,
        "order_number": order.order_number,
        "status": order.status,
        "rider": rider_info,
        "message": f"Assigned {rider_info['name']}! Order is now Out for Delivery.",
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


# -----------------------------------------------------------------------------
# Catalog Management (Admin: Add / Deactivate products)
# -----------------------------------------------------------------------------

class VariantInput(BaseModel):
    weight_label: str
    mrp: float
    price: float
    stock_qty: int = 0


class AddProductRequest(BaseModel):
    category_id: str
    name: str
    description: str = ""
    image_url: str = ""
    is_sunday_only: bool = False
    variants: List[VariantInput]


class DeleteProductRequest(BaseModel):
    product_id: str


@router.get("/catalog/all-categories")
def get_all_categories(db: Session = Depends(get_db)):
    """Returns all product categories for the Add Product form dropdown."""
    categories = db.query(Category).order_by(Category.display_order).all()
    return [{"id": c.id, "name": c.name, "slug": c.slug, "icon": c.icon} for c in categories]


@router.post("/catalog/add-product")
def add_product(req: AddProductRequest, db: Session = Depends(get_db)):
    """Admin: Add a new product + at least one variant to the catalog."""
    category = db.query(Category).filter(Category.id == req.category_id).first()
    if not category:
        raise HTTPException(status_code=404, detail="Category not found")
    if not req.variants:
        raise HTTPException(status_code=400, detail="At least one variant is required")

    product = Product(
        id=str(uuid.uuid4()),
        category_id=req.category_id,
        name=req.name.strip(),
        description=req.description.strip(),
        image_url=req.image_url.strip() if req.image_url else "",
        is_sunday_only=req.is_sunday_only,
        is_active=True,
    )
    db.add(product)
    db.flush()

    created_variants = []
    for v in req.variants:
        variant = ProductVariant(
            id=str(uuid.uuid4()),
            product_id=product.id,
            weight_label=v.weight_label.strip(),
            mrp=v.mrp,
            price=v.price,
            stock_qty=v.stock_qty,
        )
        db.add(variant)
        created_variants.append(variant)

    db.commit()

    return {
        "success": True,
        "product_id": product.id,
        "name": product.name,
        "category": category.name,
        "variants_added": len(created_variants),
        "message": f"Added '{product.name}' to catalog with {len(created_variants)} variant(s). Visible in app immediately.",
    }


@router.post("/catalog/delete-product")
def deactivate_product(req: DeleteProductRequest, db: Session = Depends(get_db)):
    """Admin: Soft-deactivate a product (sets is_active=False)."""
    product = db.query(Product).filter(Product.id == req.product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    if not product.is_active:
        return {"success": True, "product_id": product.id, "name": product.name,
                "message": f"'{product.name}' was already deactivated."}

    product.is_active = False
    db.commit()

    return {
        "success": True,
        "product_id": product.id,
        "name": product.name,
        "message": f"'{product.name}' deactivated and removed from customer catalog.",
    }


# --- Inline Edit: update product name, weight label, and price ---------------

class UpdateProductDetailRequest(BaseModel):
    product_id: str
    variant_id: str
    product_name: str
    weight_label: str
    price: float
    stock_qty: int


@router.post("/inventory/update-product-detail")
def update_product_detail(req: UpdateProductDetailRequest, db: Session = Depends(get_db)):
    """
    Admin inline edit: update product name, weight label, selling price, and stock qty.
    All four fields are saved in a single call from the inventory table row.
    """
    product = db.query(Product).filter(Product.id == req.product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    variant = db.query(ProductVariant).filter(
        ProductVariant.id == req.variant_id,
        ProductVariant.product_id == req.product_id
    ).first()
    if not variant:
        raise HTTPException(status_code=404, detail="Variant not found")

    product.name = req.product_name.strip()
    variant.weight_label = req.weight_label.strip()
    variant.price = req.price
    variant.stock_qty = req.stock_qty
    db.commit()

    return {
        "success": True,
        "product_id": product.id,
        "variant_id": variant.id,
        "message": f"'{product.name}' updated successfully.",
    }
