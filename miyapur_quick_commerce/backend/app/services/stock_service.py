from sqlalchemy.orm import Session
from app.models.models import ProductVariant
from typing import List, Dict

class StockService:
    @staticmethod
    def reserve_and_deduct_stock(db: Session, items: List[Dict]) -> bool:
        """
        Atomically checks and deducts variant stock for order items.
        Returns True if all items were successfully reserved, False if insufficient stock.
        """
        # 1. Verify availability for all items
        for itm in items:
            variant_label = itm.get("variant_label")
            requested_qty = itm.get("quantity", 1)

            variant = db.query(ProductVariant).filter(
                ProductVariant.weight_label == variant_label
            ).with_for_update().first()

            if variant and variant.stock_qty < requested_qty:
                return False

        # 2. Deduct stock for all items
        for itm in items:
            variant_label = itm.get("variant_label")
            requested_qty = itm.get("quantity", 1)

            variant = db.query(ProductVariant).filter(
                ProductVariant.weight_label == variant_label
            ).first()

            if variant:
                variant.stock_qty = max(0, variant.stock_qty - requested_qty)

        db.commit()
        return True

    @staticmethod
    def restore_stock(db: Session, items: List[Dict]):
        """
        Restores variant stock if order is cancelled or payment rejected.
        """
        for itm in items:
            variant_label = itm.get("variant_label")
            qty = itm.get("quantity", 1)

            variant = db.query(ProductVariant).filter(
                ProductVariant.weight_label == variant_label
            ).first()

            if variant:
                variant.stock_qty += qty

        db.commit()

stock_service = StockService()
