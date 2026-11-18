import random
import time
from typing import Optional, List
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.core.config import settings

router = APIRouter(prefix="/support", tags=["Help & Support"])

class SupportTicketCreate(BaseModel):
    user_id: str
    phone: str
    order_id: Optional[str] = None
    issue_category: str
    description: str

@router.get("/faqs")
def get_dynamic_faqs():
    return {
        "success": True,
        "support_contact": {
            "phone": "+91 90000 11111",
            "whatsapp": "919000011111",
            "email": "support@flashfresh.com",
            "operating_hours": "24x7 Express Support",
            "dark_store_address": settings.STORE_ADDRESS
        },
        "faq_categories": [
            {
                "id": "delivery",
                "title": "Order & Delivery",
                "icon": "local_shipping",
                "faqs": [
                    {
                        "question": "How fast will my order arrive?",
                        "answer": "Orders are packed at Central Dark Store within 3 minutes and delivered to your doorstep within 10-15 minutes by our dedicated rider fleet."
                    },
                    {
                        "question": "How do I give the delivery PIN to the rider?",
                        "answer": "When your rider arrives, share the 4-digit PIN displayed on your live order tracking screen to complete the handover securely."
                    },
                    {
                        "question": "What if my delivery is delayed?",
                        "answer": "You can track your rider live on the map. If delayed due to heavy rain or traffic, click 'Call Rider' or 'Call Store' directly from the tracking screen."
                    }
                ]
            },
            {
                "id": "payments",
                "title": "Payments & Refunds",
                "icon": "account_balance_wallet",
                "faqs": [
                    {
                        "question": "How do refunds work for cancelled orders?",
                        "answer": "Instant refunds for UPI, Cards, NetBanking, or Wallet payments are credited back to your payment source within 2-4 hours."
                    },
                    {
                        "question": "Which payment methods are supported?",
                        "answer": "We accept UPI (GPay, PhonePe, Paytm), Credit/Debit Cards, Cashfree Drop-in Checkout, NetBanking, and Cash on Delivery."
                    }
                ]
            },
            {
                "id": "quality",
                "title": "Product Quality & Items",
                "icon": "verified",
                "faqs": [
                    {
                        "question": "What if an item is damaged or spoiled?",
                        "answer": "We inspect all produce at 5 AM. If you receive a damaged item, click 'Report Quality Issue' on your order summary for an instant replacement or refund."
                    },
                    {
                        "question": "How does Sunday Fresh Meat delivery work?",
                        "answer": "Sunday Fresh Meat & Rohu Fish are 100% antibiotic-free, slaughtered & cut fresh on Sunday morning. Pre-order on Saturday for guaranteed priority delivery."
                    }
                ]
            }
        ]
    }

@router.post("/ticket")
def create_support_ticket(payload: SupportTicketCreate):
    ticket_num = f"TKT-{random.randint(10000, 99999)}"
    return {
        "success": True,
        "ticket_id": ticket_num,
        "message": f"Support ticket #{ticket_num} registered! Our Support Executive will call you back within 5 minutes.",
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S")
    }
