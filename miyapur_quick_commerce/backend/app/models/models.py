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
    monthly_credit_limit = Column(Float, default=5000.0) # Monthly Postpaid Credit Line
    current_monthly_dues = Column(Float, default=0.0)   # Active Monthly Tab / Dues
    is_pay_later_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

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
    user_id = Column(String, ForeignKey("users.id"))
    delivery_address = Column(String, nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    distance_km = Column(Float, default=0.0)
    
    # Status: PLACED, PACKED, OUT_FOR_DELIVERY, DELIVERED
    status = Column(String, default="PLACED")
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

    # Assigned Rider Info & Live Coordinates
    rider_id = Column(String, nullable=True, default="rdr_ravi_01")
    rider_name = Column(String, default="Ravi Kumar")
    rider_phone = Column(String, default="+91 98480 12345")
    rider_vehicle = Column(String, default="Hero Electric (TS 07 EK 4921)")
    rider_lat = Column(Float, default=17.495101)
    rider_lng = Column(Float, default=78.367535)

    # Rating & Review Feedback
    freshness_rating = Column(Integer, nullable=True) # 1 to 5 Stars
    rider_rating = Column(Integer, nullable=True)     # 1 to 5 Stars
    review_notes = Column(Text, nullable=True, default="")

    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="orders")
    items = relationship("OrderItem", back_populates="order", cascade="all, delete-orphan")

class OrderItem(Base):
    __tablename__ = "order_items"

    id = Column(String, primary_key=True, default=generate_uuid)
    order_id = Column(String, ForeignKey("orders.id"))
    product_name = Column(String, nullable=False)
    variant_label = Column(String, nullable=False)
    quantity = Column(Integer, default=1)
    unit_price = Column(Float, nullable=False)
    total_price = Column(Float, nullable=False)

    order = relationship("Order", back_populates="items")

class Rider(Base):
    __tablename__ = "riders"

    id = Column(String, primary_key=True, default=generate_uuid)
    phone = Column(String, unique=True, index=True, nullable=False)
    name = Column(String, nullable=False)
    vehicle = Column(String, default="Hero Electric (TS 07 EK 4921)")
    rating = Column(Float, default=4.9)
    is_online = Column(Boolean, default=True)
    today_earnings = Column(Float, default=0.0)
    completed_trips_today = Column(Integer, default=0)
    current_lat = Column(Float, default=17.495101)
    current_lng = Column(Float, default=78.367535)
    created_at = Column(DateTime, default=datetime.utcnow)

class PromoCode(Base):
    __tablename__ = "promo_codes"

    id = Column(String, primary_key=True, default=generate_uuid)
    code = Column(String, unique=True, index=True, nullable=False)
    discount_percent = Column(Float, default=20.0)
    max_discount = Column(Float, default=50.0)
    min_order = Column(Float, default=149.0)
    description = Column(String, default="")
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime, default=datetime.utcnow)

class SupportTicket(Base):
    __tablename__ = "support_tickets"

    id = Column(String, primary_key=True, default=generate_uuid)
    ticket_number = Column(String, unique=True, index=True)
    user_id = Column(String, ForeignKey("users.id"))
    order_id = Column(String, nullable=True)
    category = Column(String, default="General Inquiry")
    subject = Column(String, nullable=False)
    message = Column(Text, nullable=False)
    status = Column(String, default="OPEN") # OPEN, IN_PROGRESS, RESOLVED
    created_at = Column(DateTime, default=datetime.utcnow)
