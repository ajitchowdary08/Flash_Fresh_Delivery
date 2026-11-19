from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from datetime import datetime
from app.database.db import get_db
from app.models.models import Category, Product, PromoCode
from app.schemas.schemas import PromoCodeValidateRequest

router = APIRouter(prefix="/catalog", tags=["Catalog & Sunday Meat Engine"])

@router.get("/categories")
def get_categories(db: Session = Depends(get_db)):
    """
    Returns all product categories.
    """
    return db.query(Category).order_by(Category.display_order).all()

@router.get("/products")
def get_products(
    category_id: str = None,
    day_override: str = Query(None, description="Test override: 'sunday' or 'weekday'"),
    db: Session = Depends(get_db)
):
    """
    Returns products list.
    If day is Sunday (or day_override='sunday'), Sunday Fresh Chicken & Fish are available for live 10-15 min quick delivery.
    Otherwise, vegetables are available for instant delivery, and meat is available for Sunday pre-order.
    """
    now = datetime.now()
    is_sunday = (now.weekday() == 6) or (day_override and day_override.lower() == "sunday")

    query = db.query(Product).filter(Product.is_active == True)
    if category_id:
        query = query.filter(Product.category_id == category_id)

    products = query.all()
    
    result = []
    for p in products:
        variants = [
            {
                "id": v.id,
                "weight_label": v.weight_label,
                "mrp": v.mrp,
                "price": v.price,
                "stock_qty": v.stock_qty
            }
            for v in p.variants
        ]

        if p.is_sunday_only:
            delivery_mode = "LIVE_DELIVERY" if is_sunday else "PREORDER_FOR_SUNDAY"
            delivery_label = "10 Mins Delivery Today!" if is_sunday else "Available for Sunday Delivery (Pre-order)"
        else:
            delivery_mode = "LIVE_DELIVERY"
            delivery_label = "10-15 Mins Quick Delivery"

        result.append({
            "id": p.id,
            "category_id": p.category_id,
            "name": p.name,
            "description": p.description,
            "image_url": p.image_url,
            "is_sunday_only": p.is_sunday_only,
            "delivery_mode": delivery_mode,
            "delivery_label": delivery_label,
            "variants": variants
        })

    return {
        "is_sunday": is_sunday,
        "current_day_name": "Sunday" if is_sunday else "Weekday",
        "total_products": len(result),
        "products": result
    }

@router.get("/search")
def search_products(query: str = "", db: Session = Depends(get_db)):
    """
    Searches product catalog by name or description.
    """
    if not query:
        return []

    search_term = f"%{query.strip()}%"
    products = db.query(Product).filter(
        Product.is_active == True,
        (Product.name.ilike(search_term)) | (Product.description.ilike(search_term))
    ).all()

    result = []
    for p in products:
        variants = [
            {
                "id": v.id,
                "weight_label": v.weight_label,
                "mrp": v.mrp,
                "price": v.price,
                "stock_qty": v.stock_qty
            }
            for v in p.variants
        ]

        result.append({
            "id": p.id,
            "category_id": p.category_id,
            "name": p.name,
            "description": p.description,
            "image_url": p.image_url,
            "is_sunday_only": p.is_sunday_only,
            "delivery_mode": "LIVE_DELIVERY",
            "delivery_label": "10-15 Mins Quick Delivery",
            "variants": variants
        })
    return result

@router.post("/promos/validate")
def validate_promo_code(req: PromoCodeValidateRequest, db: Session = Depends(get_db)):
    """
    Promo codes have been retired. This endpoint is kept for backward
    compatibility with older app builds that still POST to it, but it always
    returns 'invalid' so the checkout no longer applies any discount.
    """
    raise HTTPException(
        status_code=400,
        detail="Promo codes are no longer available. Proceed to pay the listed price."
    )

@router.get("/promos/active")
def get_active_promos(db: Session = Depends(get_db)):
    """
    Promo codes have been retired. Returns an empty list so the checkout banner
    renders nothing. Kept for backward compatibility with older app builds.
    """
    return []
