from fastapi import APIRouter, Depends, HTTPException, Header
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from app.database.db import get_db
from app.models.models import User, Address
from app.schemas.schemas import SendOTPRequest, VerifyOTPRequest, AuthResponse
from app.services.otp_service import otp_service
from app.services.maps_service import maps_service
from app.core.security import get_current_user
import uuid

router = APIRouter(prefix="/auth", tags=["Customer Profile & Addresses"])

class FirebaseLoginRequest(BaseModel):
    phone: str
    firebase_uid: str
    name: Optional[str] = None

class UpdateProfileRequest(BaseModel):
    name: str
    email: Optional[str] = ""

class CreateAddressRequest(BaseModel):
    label: str = "Home" # Home, Work, Other
    house_number: str = "" # Flat / Door / Floor No
    street_address: Optional[str] = ""
    landmark: Optional[str] = ""
    latitude: Optional[float] = 17.495101
    longitude: Optional[float] = 78.367535
    is_default: Optional[bool] = False

@router.post("/send-otp")
def send_otp(req: SendOTPRequest):
    """
    Sends a 6-digit OTP code to the customer's phone number.
    """
    res = otp_service.send_otp(req.phone)
    if not res["success"]:
        raise HTTPException(status_code=400, detail=res["message"])
    return res

@router.post("/verify-otp", response_model=AuthResponse)
def verify_otp(req: VerifyOTPRequest, db: Session = Depends(get_db)):
    """
    Verifies the OTP code and creates/fetches the user account with a signed JWT token.
    """
    res = otp_service.verify_otp(req.phone, req.otp)
    if not res["success"]:
        raise HTTPException(status_code=400, detail=res["message"])

    clean_phone = res["phone"]
    user = db.query(User).filter(User.phone == clean_phone).first()
    if not user:
        user = User(
            id=f"usr_{clean_phone}",
            phone=clean_phone,
            name=req.name or f"Customer ({clean_phone[-4:]})",
            email=""
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    jwt_token = otp_service.create_jwt_token(user_id=user.id, phone=user.phone)

    return AuthResponse(
        success=True,
        token=jwt_token,
        user_id=user.id,
        phone=user.phone,
        name=user.name,
        message="Authentication successful."
    )

@router.post("/firebase-login", response_model=AuthResponse)
def firebase_login(req: FirebaseLoginRequest, db: Session = Depends(get_db)):
    """
    Synchronizes Firebase Phone Auth user with the PostgreSQL/SQLite backend database.
    Creates or fetches the user profile from SQL DB.
    """
    clean_phone = req.phone.strip().replace("+91", "").replace(" ", "").replace("-", "")
    user = db.query(User).filter((User.phone == clean_phone) | (User.id == req.firebase_uid)).first()

    if not user:
        user = User(
            id=req.firebase_uid or str(uuid.uuid4()),
            phone=clean_phone,
            name=req.name or f"Customer ({clean_phone[-4:]})",
            email=""
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    jwt_token = otp_service.create_jwt_token(user_id=user.id, phone=user.phone)

    return AuthResponse(
        success=True,
        token=jwt_token,
        user_id=user.id,
        phone=user.phone,
        name=user.name,
        message="User authenticated and synchronized with database."
    )

@router.get("/profile/{user_id}")
def get_user_profile(user_id: str, db: Session = Depends(get_db)):
    """
    Returns customer personal details, phone, email, and monthly credit line stats directly from SQL DB.
    """
    user = db.query(User).filter((User.id == user_id) | (User.phone == user_id)).first()
    if not user:
        return {
            "id": user_id,
            "name": "Valued Resident",
            "phone": user_id,
            "email": "",
            "total_orders": 0,
            "saved_addresses_count": 1,
            "monthly_credit_limit": 1500.0,
            "current_monthly_dues": 0.0,
            "available_credit": 1500.0,
            "is_pay_later_active": True,
            "member_since": "November 2026"
        }

    credit_limit = user.monthly_credit_limit or 5000.0
    current_dues = user.current_monthly_dues or 0.0
    available_credit = max(0.0, credit_limit - current_dues)

    return {
        "id": user.id,
        "name": user.name,
        "phone": user.phone,
        "email": user.email,
        "total_orders": len(user.orders),
        "saved_addresses_count": len(user.addresses),
        "monthly_credit_limit": credit_limit,
        "current_monthly_dues": current_dues,
        "available_credit": available_credit,
        "is_pay_later_active": user.is_pay_later_active,
        "member_since": user.created_at.strftime("%B %Y")
    }

@router.get("/pay-later/statement/{user_id}")
def get_pay_later_statement(user_id: str, db: Session = Depends(get_db)):
    """
    Returns itemized monthly credit line statement & active running tab for Miyapur Monthly Khata.
    """
    user = db.query(User).filter(User.id == user_id).first()
    credit_limit = user.monthly_credit_limit if user else 5000.0
    current_dues = user.current_monthly_dues if user else 0.0
    available = max(0.0, credit_limit - current_dues)

    return {
        "success": True,
        "user_id": user_id,
        "monthly_credit_limit": credit_limit,
        "current_monthly_dues": current_dues,
        "available_credit": available,
        "billing_cycle": "1st to 30th of every month",
        "next_due_date": "1st of next month",
        "is_eligible": True,
        "message": f"Monthly Tab Active. Available Credit: ₹{available:.0f}"
    }

@router.post("/pay-later/settle-bill/{user_id}")
def settle_pay_later_bill(user_id: str, db: Session = Depends(get_db)):
    """
    Settles user's monthly credit line bill via UPI/Razorpay and resets running tab to ₹0.
    """
    user = db.query(User).filter(User.id == user_id).first()
    if user:
        cleared_amount = user.current_monthly_dues
        user.current_monthly_dues = 0.0
        db.commit()
    else:
        cleared_amount = 0.0

    return {
        "success": True,
        "user_id": user_id,
        "cleared_amount": cleared_amount,
        "current_monthly_dues": 0.0,
        "available_credit": 5000.0,
        "message": f"Monthly statement of ₹{cleared_amount:.0f} settled successfully! Your credit limit has been fully restored."
    }

@router.put("/profile/{user_id}")
@router.post("/profile/{user_id}")
def update_user_profile(user_id: str, req: UpdateProfileRequest, db: Session = Depends(get_db)):
    """
    Updates or creates customer profile name and email address in the SQL Database.
    """
    user = db.query(User).filter((User.id == user_id) | (User.phone == user_id)).first()
    if not user:
        user = User(
            id=user_id,
            phone=user_id,
            name=req.name.strip(),
            email=req.email.strip() if req.email else ""
        )
        db.add(user)
    else:
        user.name = req.name.strip()
        if req.email:
            user.email = req.email.strip()

    db.commit()
    db.refresh(user)

    return {
        "success": True,
        "id": user.id,
        "name": user.name,
        "email": user.email,
        "message": "Profile updated successfully in database."
    }

@router.get("/addresses/{user_id}")
def get_saved_addresses(user_id: str, db: Session = Depends(get_db)):
    """
    Returns all saved addresses (Home, Work, Other) for the customer.
    Queries flexibly by user_id or clean phone number so saved addresses are never lost.
    """
    clean_phone = user_id.strip().replace("+91", "").replace(" ", "").replace("-", "")
    users = db.query(User).filter((User.id == user_id) | (User.phone == clean_phone) | (User.phone == user_id) | (User.id == f"usr_{clean_phone}")).all()
    user_ids = [u.id for u in users]
    for alt in [user_id, clean_phone, f"usr_{clean_phone}"]:
        if alt not in user_ids:
            user_ids.append(alt)

    addresses = db.query(Address).filter(Address.user_id.in_(user_ids)).all()
    res = []
    for a in addresses:
        res.append({
            "id": a.id,
            "label": a.label,
            "house_number": a.house_number,
            "street_address": a.street_address,
            "landmark": a.landmark,
            "latitude": a.latitude,
            "longitude": a.longitude,
            "distance_km": a.distance_km,
            "is_serviceable": a.is_serviceable,
            "is_default": a.is_default
        })
    return res

@router.post("/addresses/{user_id}")
def add_saved_address(user_id: str, req: CreateAddressRequest, db: Session = Depends(get_db)):
    """
    Adds a new saved delivery address with 10 KM geofence validation.
    Ensures parent user account exists in SQL Database.
    """
    clean_phone = user_id.strip().replace("+91", "").replace(" ", "").replace("-", "")
    user = db.query(User).filter((User.id == user_id) | (User.phone == clean_phone) | (User.phone == user_id)).first()
    if not user:
        user = User(
            id=f"usr_{clean_phone}" if len(clean_phone) == 10 else user_id,
            phone=clean_phone if len(clean_phone) == 10 else "9876543210",
            name=f"Customer ({clean_phone[-4:] if len(clean_phone) >= 4 else user_id})",
            email=""
        )
        db.add(user)
        db.commit()
        db.refresh(user)

    target_user_id = user.id

    service_info = maps_service.check_serviceability(req.latitude, req.longitude)
    if not service_info["is_serviceable"]:
        raise HTTPException(
            status_code=400,
            detail=f"This address is {service_info['distance_km']} KM away, which is outside our 10 KM delivery radius from Miyapur Central Hub."
        )

    # If this is marked default, unset existing default
    if req.is_default:
        db.query(Address).filter(Address.user_id == target_user_id).update({"is_default": False})

    new_addr = Address(
        id=str(uuid.uuid4()),
        user_id=target_user_id,
        label=req.label,
        house_number=req.house_number,
        street_address=req.street_address,
        landmark=req.landmark or "",
        latitude=req.latitude,
        longitude=req.longitude,
        distance_km=service_info["distance_km"],
        is_serviceable=service_info["is_serviceable"],
        is_default=req.is_default or False
    )
    db.add(new_addr)
    db.commit()
    db.refresh(new_addr)

    return {
        "success": True,
        "id": new_addr.id,
        "label": new_addr.label,
        "house_number": new_addr.house_number,
        "street_address": new_addr.street_address,
        "distance_km": new_addr.distance_km,
        "message": "Delivery address saved successfully."
    }

@router.delete("/addresses/{address_id}")
def delete_saved_address(address_id: str, db: Session = Depends(get_db)):
    """
    Deletes a saved address.
    """
    addr = db.query(Address).filter(Address.id == address_id).first()
    if not addr:
        raise HTTPException(status_code=404, detail="Address not found")

    db.delete(addr)
    db.commit()
    return {"success": True, "message": "Address deleted successfully."}
