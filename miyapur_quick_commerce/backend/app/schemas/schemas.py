from pydantic import BaseModel, Field
from typing import List, Optional

# Auth Schemas
class SendOTPRequest(BaseModel):
    phone: str = Field(..., example="9876543210")

class VerifyOTPRequest(BaseModel):
    phone: str = Field(..., example="9876543210")
    otp: str = Field(..., example="123456")
    name: Optional[str] = "Customer"

class AuthResponse(BaseModel):
    success: bool
    token: Optional[str] = None
    user_id: Optional[str] = None
    phone: Optional[str] = None
    name: Optional[str] = None
    message: str

# Map & Geofence Schemas
class GeofenceCheckRequest(BaseModel):
    latitude: float
    longitude: float

class LocationItem(BaseModel):
    id: str
    name: str
    address: str
    latitude: float
    longitude: float
    landmark: str
    distance_km: float
    is_serviceable: bool
    eta_minutes: Optional[int]

# Catalog Schemas
class VariantSchema(BaseModel):
    id: str
    weight_label: str
    mrp: float
    price: float
    stock_qty: int

class ProductSchema(BaseModel):
    id: str
    name: str
    description: str
    image_url: str
    is_sunday_only: bool
    category_id: str
    variants: List[VariantSchema]

class CategorySchema(BaseModel):
    id: str
    name: str
    slug: str
    icon: str
    display_order: int

# Order & Payment Schemas
class OrderItemCreate(BaseModel):
    product_name: str
    variant_label: str
    quantity: int
    unit_price: float
    # Optional but recommended: the exact product/variant UUIDs from the catalog.
    # When supplied, the backend looks up the variant by id (not by weight_label)
    # and IGNORES client-supplied unit_price entirely — the DB price is authoritative.
    product_id: Optional[str] = None
    variant_id: Optional[str] = None

class CreateOrderRequest(BaseModel):
    user_id: str
    delivery_address: str
    latitude: float
    longitude: float
    items: List[OrderItemCreate]
    payment_method: str = "UPI"
    is_sunday_meat_order: bool = False
    scheduled_slot: Optional[str] = "10-15 Mins Quick Delivery"
    promo_code: Optional[str] = ""
    delivery_instructions: Optional[str] = ""
    idempotency_key: Optional[str] = None

class VerifyPaymentRequest(BaseModel):
    order_id: str
    gateway_order_id: str
    payment_method: str = "UPI"
    should_succeed: bool = True

class PromoCodeValidateRequest(BaseModel):
    code: str
    items_total: float

class RiderLocationUpdate(BaseModel):
    order_id: str
    latitude: float
    longitude: float

class VerifyDeliveryOTPRequest(BaseModel):
    order_id: str
    otp: str
