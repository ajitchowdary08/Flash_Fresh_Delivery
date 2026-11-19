import uuid
from datetime import datetime
from sqlalchemy import Column, String, Integer, Float, Boolean, DateTime, ForeignKey, Text
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()

def generate_uuid():
    return str(uuid.uuid4())

class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=generate_uuid)
    phone = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, default="Valued Customer")
    email = Column(String, default="")
    # Authorization role: CUSTOMER | RIDER | MANAGER | ADMIN. Persisted so it can be
    # checked server-side (the JWT also carries it, but the DB is authoritative).
    role = Column(String, default="CUSTOMER", index=True)
    is_active = Column(Boolean, default=True)
    monthly_credit_limit = Column(Float, default=5000.0) # Monthly Postpaid Credit Line
    current_monthly_dues = Column(Float, default=0.0)   # Active Monthly Tab / Dues
    is_pay_later_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    orders = relationship("Order", back_populates="user")
    addresses = relationship("Address", back_populates="user", cascade="all, delete-orphan")

class Address(Base):
    __tablename__ = "addresses"

    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, ForeignKey("users.id"))
    label = Column(String, default="Home") # Home, Work, Other
    house_number = Column(String, default="") # Flat / House No / Floor
    street_address = Column(String, nullable=False)
    landmark = Column(String, default="")
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    distance_km = Column(Float, default=0.0)
    is_serviceable = Column(Boolean, default=True)
    is_default = Column(Boolean, default=False)

    user = relationship("User", back_populates="addresses")

class Category(Base):
    __tablename__ = "categories"

    id = Column(String, primary_key=True, default=generate_uuid)
    name = Column(String, nullable=False)
    slug = Column(String, unique=True, index=True)
    icon = Column(String, default="leaf")
    display_order = Column(Integer, default=0)

    products = relationship("Product", back_populates="category")

class Product(Base):
    __tablename__ = "products"

    id = Column(String, primary_key=True, default=generate_uuid)
    category_id = Column(String, ForeignKey("categories.id"))
    name = Column(String, nullable=False)
    description = Column(Text, default="")
    image_url = Column(String, default="")
    is_sunday_only = Column(Boolean, default=False)
    is_active = Column(Boolean, default=True)

    category = relationship("Category", back_populates="products")
    variants = relationship("ProductVariant", back_populates="product", cascade="all, delete-orphan")

class ProductVariant(Base):
    __tablename__ = "product_variants"

    id = Column(String, primary_key=True, default=generate_uuid)
    product_id = Column(String, ForeignKey("products.id"))
    weight_label = Column(String, nullable=False) # e.g. "500g", "1kg"
    mrp = Column(Float, nullable=False)
    price = Column(Float, nullable=False)
    stock_qty = Column(Integer, default=100)

    product = relationship("Product", back_populates="variants")

class Order(Base):
    __tablename__ = "orders"

    id = Column(String, primary_key=True, default=generate_uuid)
    order_number = Column(String, unique=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), index=True)
    delivery_address = Column(String, nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    distance_km = Column(Float, default=0.0)

    # Status: PLACED, PACKED, OUT_FOR_DELIVERY, DELIVERED, CANCELLED
    status = Column(String, default="PLACED", index=True)
    delivery_eta_mins = Column(Integer, default=15)

    items_total = Column(Float, nullable=False)
    delivery_fee = Column(Float, default=15.0)
    discount_amount = Column(Float, default=0.0)
    promo_code = Column(String, default="")
    grand_total = Column(Float, nullable=False)

    payment_status = Column(String, default="PENDING")
    payment_method = Column(String, default="UPI")
    cf_order_id = Column(String, nullable=True, index=True)
    payment_session_id = Column(String, nullable=True)
    idempotency_key = Column(String, unique=True, nullable=True, index=True)
    pg_payment_id = Column(String, nullable=True)
    is_sunday_meat_order = Column(Boolean, default=False)
    scheduled_slot = Column(String, default="10-15 Mins Quick Delivery")
    delivery_instructions = Column(String, default="")
    delivery_otp = Column(String, default="4921")

    # Assigned Rider Info & Live Coordinates. Nullable — no order is born with a
    # fake rider anymore. A rider is assigned only when one accepts/ is assigned.
    rider_id = Column(String, nullable=True, index=True)
    rider_name = Column(String, nullable=True)
    rider_phone = Column(String, nullable=True)
    rider_vehicle = Column(String, nullable=True)
    rider_lat = Column(Float, nullable=True)
    rider_lng = Column(Float, nullable=True)

    # Rating & Review Feedback
    freshness_rating = Column(Integer, nullable=True) # 1 to 5 Stars
    rider_rating = Column(Integer, nullable=True)     # 1 to 5 Stars
    review_notes = Column(Text, nullable=True, default="")

    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    user = relationship("User", back_populates="orders")
    items = relationship("OrderItem", back_populates="order", cascade="all, delete-orphan")
    payments = relationship("Payment", back_populates="order", cascade="all, delete-orphan")
    ratings = relationship("Rating", back_populates="order", cascade="all, delete-orphan")

class OrderItem(Base):
    __tablename__ = "order_items"

    id = Column(String, primary_key=True, default=generate_uuid)
    order_id = Column(String, ForeignKey("orders.id"), index=True)
    product_name = Column(String, nullable=False)
    variant_label = Column(String, nullable=False)
    quantity = Column(Integer, default=1)
    unit_price = Column(Float, nullable=False)
    total_price = Column(Float, nullable=False)

    order = relationship("Order", back_populates="items")


# =============================================================================
# Delivery fleet — previously a hardcoded Python list. Now a real table so the
# store manager can onboard / activate / deactivate riders dynamically.
# =============================================================================
class Rider(Base):
    __tablename__ = "riders"

    id = Column(String, primary_key=True, default=generate_uuid)
    phone = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=False)
    vehicle = Column(String, default="")
    # AUTH: riders log in with phone OTP just like customers; their JWT role=RIDER
    # is linked to this row by phone. `user_id` points at the users row (role=RIDER).
    user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    rating = Column(Float, default=5.0)
    is_online = Column(Boolean, default=False, index=True)
    is_active = Column(Boolean, default=True)  # manager can deactivate a rider
    current_lat = Column(Float, nullable=True)
    current_lng = Column(Float, nullable=True)
    # Fleet operational state
    today_earnings = Column(Float, default=0.0)
    completed_trips_today = Column(Integer, default=0)
    cod_cash_in_hand = Column(Float, default=0.0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    orders = relationship(
        "Order",
        primaryjoin="foreign(Order.rider_id)==Rider.id",
        viewonly=True,
    )
    locations = relationship("RiderLocation", back_populates="rider", cascade="all, delete-orphan")


class RiderLocation(Base):
    """Time-series of rider GPS pings — powers live tracking history & replays."""
    __tablename__ = "rider_locations"

    id = Column(String, primary_key=True, default=generate_uuid)
    rider_id = Column(String, ForeignKey("riders.id"), index=True, nullable=False)
    order_id = Column(String, ForeignKey("orders.id"), nullable=True, index=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, index=True)

    rider = relationship("Rider", back_populates="locations")


# =============================================================================
# Promo codes — previously a hardcoded Python dict. Now a real table so the
# store manager can create / expire coupons dynamically from the dashboard.
# =============================================================================
class PromoCode(Base):
    __tablename__ = "promo_codes"

    id = Column(String, primary_key=True, default=generate_uuid)
    code = Column(String, unique=True, index=True, nullable=False)
    description = Column(String, default="")
    discount_percent = Column(Float, default=0.0)
    max_discount = Column(Float, default=0.0)
    min_order = Column(Float, default=0.0)
    is_active = Column(Boolean, default=True, index=True)
    usage_count = Column(Integer, default=0)
    valid_from = Column(DateTime, default=datetime.utcnow)
    valid_until = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


# =============================================================================
# Payment ledger — previously payment state lived as columns on `orders`. This
# table gives a proper transaction history (attempts, refunds, gateway refs).
# =============================================================================
class Payment(Base):
    __tablename__ = "payments"

    id = Column(String, primary_key=True, default=generate_uuid)
    order_id = Column(String, ForeignKey("orders.id"), index=True, nullable=False)
    gateway = Column(String, default="CASHFREE")  # CASHFREE | UPI | COD | PAY_LATER
    gateway_order_id = Column(String, nullable=True, index=True)
    gateway_payment_id = Column(String, nullable=True, index=True)
    amount = Column(Float, nullable=False)
    status = Column(String, default="PENDING")  # PENDING | PAID | FAILED | REFUNDED
    raw_response = Column(Text, default="")
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    order = relationship("Order", back_populates="payments")


# =============================================================================
# Audit log — every admin mutation (price change, product add/delete, rider
# assign, order status override) is recorded with who/what/when for compliance.
# =============================================================================
class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(String, primary_key=True, default=generate_uuid)
    actor_id = Column(String, index=True)        # manager user_id
    actor_role = Column(String, default="MANAGER")
    action = Column(String, index=True)          # PRICE_UPDATE, PRODUCT_ADD, ...
    entity_type = Column(String, default="")    # product | order | rider
    entity_id = Column(String, default="", index=True)
    details = Column(Text, default="")           # JSON snapshot of the change
    created_at = Column(DateTime, default=datetime.utcnow, index=True)


# =============================================================================
# Ratings — previously ratings were columns on `orders` only (one per order).
# This table allows multi-dimensional, per-delivery reviews that the rider app
# and store dashboard can query independently of the order row.
# =============================================================================
class Rating(Base):
    __tablename__ = "ratings"

    id = Column(String, primary_key=True, default=generate_uuid)
    order_id = Column(String, ForeignKey("orders.id"), index=True, nullable=False)
    rider_id = Column(String, ForeignKey("riders.id"), nullable=True, index=True)
    user_id = Column(String, ForeignKey("users.id"), nullable=True, index=True)
    rider_rating = Column(Integer, nullable=True)
    freshness_rating = Column(Integer, nullable=True)
    review = Column(Text, default="")
    created_at = Column(DateTime, default=datetime.utcnow)

    order = relationship("Order", back_populates="ratings")
