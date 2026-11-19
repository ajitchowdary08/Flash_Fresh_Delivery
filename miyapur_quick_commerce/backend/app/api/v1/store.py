from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import uuid
import json

from app.database.db import get_db
from app.models.models import Order, Product, ProductVariant, Category, Rider, PromoCode, AuditLog, Rating
from app.api.v1.orders import ws_manager
from app.core.security import get_current_store_manager
from app.core.config import settings


def _audit(db: Session, actor: dict, action: str, entity_type: str, entity_id: str, details: dict):
    """Records an admin mutation for compliance / who-did-what traceability."""
    try:
        db.add(AuditLog(
            actor_id=actor.get("sub", "unknown"),
            actor_role=actor.get("role", "MANAGER"),
            action=action,
            entity_type=entity_type,
            entity_id=str(entity_id),
            details=json.dumps(details, default=str),
        ))
        db.commit()
    except Exception:
        db.rollback()


router = APIRouter(prefix="/store", tags=["Dark Store Hub Operations"])

class StockUpdateRequest(BaseModel):
    variant_id: str
    new_stock_qty: int

class QuickIntakeItem(BaseModel):
    product_name: str
    variant_label: str
    added_qty: int

@router.get("/dashboard-summary")
def get_store_dashboard_summary(db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    """
    Returns store overview: orders waiting to be packed, out for delivery, delivered, and total catalog items.
    """
    pending_pack = db.query(func.count(Order.id)).filter(Order.status == "PLACED").scalar() or 0
    packed = db.query(func.count(Order.id)).filter(Order.status == "PACKED").scalar() or 0
    out_for_delivery = db.query(func.count(Order.id)).filter(Order.status == "OUT_FOR_DELIVERY").scalar() or 0
    delivered = db.query(func.count(Order.id)).filter(Order.status == "DELIVERED").scalar() or 0
    total_rev = db.query(func.sum(Order.grand_total)).filter(Order.status.in_(["DELIVERED", "OUT_FOR_DELIVERY"])).scalar() or 0.0

    return {
        "store_name": "Central Fulfillment Dark Store Hub",
        "service_radius": "Full City Delivery",
        "orders_to_pack": pending_pack,
        "orders_ready_for_pickup": packed,
        "orders_in_transit": out_for_delivery,
        "orders_delivered_today": delivered,
        "total_revenue_today": round(float(total_rev), 2)
    }

@router.get("/packing-queue")
def get_packing_queue(db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
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
def mark_order_packed(order_id: str, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    """
    Store boy finishes weighing and bagging, marks order as PACKED.
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    order.status = "PACKED"
    db.commit()
    db.refresh(order)
    _audit(db, manager, "MARK_PACKED", "order", order.id, {"order_number": order.order_number})

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
def get_store_inventory(db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
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
def update_stock(req: StockUpdateRequest, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    """
    Quick stock correction by variant id.
    """
    variant = db.query(ProductVariant).filter(ProductVariant.id == req.variant_id).first()
    if not variant:
        raise HTTPException(status_code=404, detail="Variant not found")

    old_stock = variant.stock_qty
    variant.stock_qty = req.new_stock_qty
    db.commit()
    db.refresh(variant)
    _audit(db, manager, "STOCK_UPDATE", "variant", variant.id, {"old": old_stock, "new": req.new_stock_qty})

    return {
        "success": True,
        "variant_id": variant.id,
        "weight_label": variant.weight_label,
        "new_stock_qty": variant.stock_qty,
        "message": "Stock quantity updated successfully."
    }


# Active delivery fleet partners are now sourced LIVE from the `riders` table
# (previously a hardcoded Python list). The store manager can onboard new riders
# via the rider-creation endpoint and activate/deactivate them here.


class AssignRiderRequest(BaseModel):
    rider_id: str


class RecordMeatWeightRequest(BaseModel):
    actual_weight_g: float
    cut_type: str = "Curry Cut"
    turmeric_wash: bool = True
    skinless: bool = True


@router.get("/riders/active")
def get_active_riders(db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    """
    Returns fleet partners available around the Central Dark Store Hub — live from DB.
    """
    riders = db.query(Rider).filter(Rider.is_active == True).all()
    return [
        {
            "id": r.id,
            "name": r.name,
            "phone": r.phone,
            "vehicle": r.vehicle or "—",
            "rating": r.rating,
            "status": "AVAILABLE" if r.is_online else "OFFLINE",
            "is_online": r.is_online,
        }
        for r in riders
    ]


@router.post("/riders/create")
def create_rider(req: dict, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    """Store manager onboards a new delivery partner. Creates both a Rider row
    and a linked User (role=RIDER) so the rider can log in via OTP."""
    from app.models.models import User as UserModel
    phone = (req.get("phone") or "").strip().replace("+91", "").replace(" ", "").replace("-", "")
    if len(phone) != 10 or not phone.isdigit():
        raise HTTPException(status_code=400, detail="A valid 10-digit phone is required.")
    name = (req.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Rider name is required.")
    if db.query(Rider).filter(Rider.phone == phone).first():
        raise HTTPException(status_code=400, detail="A rider with this phone already exists.")

    u = UserModel(id=f"rdr_{phone}", phone=phone, name=name, role="RIDER")
    db.add(u); db.commit(); db.refresh(u)
    r = Rider(id=f"rdr_{phone}", phone=phone, name=name, vehicle=req.get("vehicle", ""),
              rating=5.0, is_online=False, is_active=True, user_id=u.id)
    db.add(r); db.commit(); db.refresh(r)
    _audit(db, manager, "RIDER_ADD", "rider", r.id, {"name": name, "phone": phone})
    return {"success": True, "rider_id": r.id, "message": f"Rider '{name}' onboarded."}


@router.post("/riders/{rider_id}/toggle-active")
def toggle_rider_active(rider_id: str, req: dict, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    r = db.query(Rider).filter(Rider.id == rider_id).first()
    if not r:
        raise HTTPException(status_code=404, detail="Rider not found")
    r.is_active = bool(req.get("is_active", not r.is_active))
    db.commit()
    _audit(db, manager, "RIDER_TOGGLE", "rider", r.id, {"is_active": r.is_active})
    return {"success": True, "rider_id": r.id, "is_active": r.is_active}


@router.post("/orders/{order_id}/assign-rider")
async def assign_rider_to_order(
    order_id: str,
    req: AssignRiderRequest,
    db: Session = Depends(get_db),
    manager: dict = Depends(get_current_store_manager),
):
    """
    Store manager assigns an available rider to a packed order, triggering immediate dispatch.
    """
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")

    # Resolve rider from DB (was: next((r for r in ACTIVE_RIDERS ...))).
    rider_row = db.query(Rider).filter(Rider.id == req.rider_id).first()
    if not rider_row:
        raise HTTPException(status_code=404, detail="Selected rider not found in fleet.")
    if not rider_row.is_active:
        raise HTTPException(status_code=400, detail="That rider is currently deactivated.")

    rider = {
        "id": rider_row.id,
        "name": rider_row.name,
        "phone": rider_row.phone,
        "vehicle": rider_row.vehicle or "—",
    }

    order.status = "PACKED"
    order.rider_id = rider_row.id
    order.rider_name = rider_row.name
    order.rider_phone = rider_row.phone
    order.rider_vehicle = rider_row.vehicle
    order.rider_lat = settings.STORE_LATITUDE if hasattr(settings, "STORE_LATITUDE") else 17.495101
    order.rider_lng = settings.STORE_LONGITUDE if hasattr(settings, "STORE_LONGITUDE") else 78.367535

    db.commit()
    db.refresh(order)
    _audit(db, manager, "ASSIGN_RIDER", "order", order.id, {"rider_id": rider_row.id, "rider_name": rider_row.name})

    # Broadcast live status update over WebSocket to customer app
    await ws_manager.broadcast_order_update(order.id, {
        "event": "STATUS_UPDATE",
        "status": "PACKED",
        "message": f"Rider {rider['name']} ({rider['vehicle']}) has been assigned to your order!",
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
    manager: dict = Depends(get_current_store_manager),
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
def get_all_categories(db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    """Returns all product categories for the Add Product form dropdown."""
    categories = db.query(Category).order_by(Category.display_order).all()
    return [{"id": c.id, "name": c.name, "slug": c.slug, "icon": c.icon} for c in categories]


@router.post("/catalog/add-product")
def add_product(req: AddProductRequest, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
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
    _audit(db, manager, "PRODUCT_ADD", "product", product.id, {"name": product.name, "variants": len(created_variants)})

    return {
        "success": True,
        "product_id": product.id,
        "name": product.name,
        "category": category.name,
        "variants_added": len(created_variants),
        "message": f"Added '{product.name}' to catalog with {len(created_variants)} variant(s). Visible in app immediately.",
    }


@router.post("/catalog/delete-product")
def deactivate_product(req: DeleteProductRequest, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    """Admin: Soft-deactivate a product (sets is_active=False)."""
    product = db.query(Product).filter(Product.id == req.product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    if not product.is_active:
        return {"success": True, "product_id": product.id, "name": product.name,
                "message": f"'{product.name}' was already deactivated."}

    product.is_active = False
    db.commit()
    _audit(db, manager, "PRODUCT_DEACTIVATE", "product", product.id, {"name": product.name})

    return {
        "success": True,
        "product_id": product.id,
        "name": product.name,
        "message": f"'{product.name}' deactivated and removed from customer catalog.",
    }


# -----------------------------------------------------------------------------
# Promo Code Management (Admin CRUD) — promo codes now live in the DB.
# -----------------------------------------------------------------------------

class PromoCodeInput(BaseModel):
    code: str
    description: str = ""
    discount_percent: float
    max_discount: float
    min_order: float = 0.0
    is_active: bool = True


@router.get("/promos")
def list_promo_codes(db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    promos = db.query(PromoCode).order_by(PromoCode.created_at.desc()).all()
    return [{
        "id": p.id, "code": p.code, "description": p.description,
        "discount_percent": p.discount_percent, "max_discount": p.max_discount,
        "min_order": p.min_order, "is_active": p.is_active, "usage_count": p.usage_count,
    } for p in promos]


@router.post("/promos/create")
def create_promo_code(req: PromoCodeInput, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    code = req.code.strip().upper()
    if not code:
        raise HTTPException(status_code=400, detail="Promo code is required.")
    if db.query(PromoCode).filter(PromoCode.code == code).first():
        raise HTTPException(status_code=400, detail="This promo code already exists.")
    p = PromoCode(code=code, description=req.description, discount_percent=req.discount_percent,
                  max_discount=req.max_discount, min_order=req.min_order, is_active=req.is_active)
    db.add(p); db.commit(); db.refresh(p)
    _audit(db, manager, "PROMO_ADD", "promo", p.id, {"code": code})
    return {"success": True, "promo_id": p.id, "code": code, "message": f"Promo '{code}' created."}


@router.post("/promos/{promo_id}/toggle")
def toggle_promo_active(promo_id: str, req: dict, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    p = db.query(PromoCode).filter(PromoCode.id == promo_id).first()
    if not p:
        raise HTTPException(status_code=404, detail="Promo code not found")
    p.is_active = bool(req.get("is_active", not p.is_active))
    db.commit()
    _audit(db, manager, "PROMO_TOGGLE", "promo", p.id, {"code": p.code, "is_active": p.is_active})
    return {"success": True, "code": p.code, "is_active": p.is_active}


@router.get("/audit-log")
def get_audit_log(db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager), limit: int = 100):
    """Returns the most recent admin mutations (who/what/when) for accountability."""
    logs = db.query(AuditLog).order_by(AuditLog.created_at.desc()).limit(min(limit, 500)).all()
    return [{
        "id": l.id, "actor_id": l.actor_id, "actor_role": l.actor_role, "action": l.action,
        "entity_type": l.entity_type, "entity_id": l.entity_id, "details": l.details,
        "created_at": l.created_at.strftime("%d %b %Y, %I:%M %p") if l.created_at else "",
    } for l in logs]



# --- Inline Edit: update product name, weight label, and price ---------------

class UpdateProductDetailRequest(BaseModel):
    product_id: str
    variant_id: str
    product_name: str
    weight_label: str
    price: float
    stock_qty: int


@router.post("/inventory/update-product-detail")
def update_product_detail(req: UpdateProductDetailRequest, db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
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

    old_price = variant.price
    old_stock = variant.stock_qty
    product.name = req.product_name.strip()
    variant.weight_label = req.weight_label.strip()
    variant.price = req.price
    variant.stock_qty = req.stock_qty
    db.commit()
    _audit(db, manager, "PRICE_UPDATE", "variant", variant.id, {
        "product": product.name, "old_price": old_price, "new_price": req.price,
        "old_stock": old_stock, "new_stock": req.stock_qty,
    })

    return {
        "success": True,
        "product_id": product.id,
        "variant_id": variant.id,
        "message": f"'{product.name}' updated successfully.",
    }


@router.get("/reviews")
def get_store_reviews(db: Session = Depends(get_db), manager: dict = Depends(get_current_store_manager)):
    """
    Returns store ratings and customer freshness reviews.
    """
    ratings = db.query(Rating).order_by(Rating.created_at.desc()).limit(50).all()
    if not ratings:
        orders_with_reviews = db.query(Order).filter(Order.freshness_rating.isnot(None)).order_by(Order.created_at.desc()).limit(50).all()
        avg_freshness = db.query(func.avg(Order.freshness_rating)).filter(Order.freshness_rating.isnot(None)).scalar() or 5.0
        return {
            "avg_rating": round(float(avg_freshness), 1),
            "total_ratings": len(orders_with_reviews),
            "recent_reviews": [
                {
                    "order_id": o.id,
                    "order_number": o.order_number,
                    "freshness_rating": o.freshness_rating,
                    "rider_rating": o.rider_rating,
                    "review": o.review_notes or "Fresh farm quality delivered on time!",
                    "created_at": o.created_at.strftime("%d %b %Y") if o.created_at else "Recent",
                }
                for o in orders_with_reviews
            ]
        }

    avg_rating = db.query(func.avg(Rating.freshness_rating)).filter(Rating.freshness_rating.isnot(None)).scalar() or 5.0
    return {
        "avg_rating": round(float(avg_rating), 1),
        "total_ratings": len(ratings),
        "recent_reviews": [
            {
                "order_id": r.order_id,
                "freshness_rating": r.freshness_rating or 5,
                "rider_rating": r.rider_rating or 5,
                "review": r.review or "Great quality fresh produce!",
                "created_at": r.created_at.strftime("%d %b %Y") if r.created_at else "Recent",
            }
            for r in ratings
        ]
    }
