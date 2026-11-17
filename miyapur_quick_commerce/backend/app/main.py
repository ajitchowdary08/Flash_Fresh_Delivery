from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from app.core.config import settings
from app.database.db import init_db
from app.api.v1.auth import router as auth_router
from app.api.v1.maps import router as maps_router
from app.api.v1.catalog import router as catalog_router
from app.api.v1.orders import router as orders_router
from app.api.v1.payments import router as payments_router
from app.api.v1.rider import router as rider_router
from app.api.v1.store import router as store_router

# Initialize database schema and seeds
init_db()

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Hyperlocal Quick-Commerce API (10KM Miyapur Radius) with Mock OTP, Mock Razorpay & Mock Google Maps",
    version="1.0.0"
)

# Enable CORS for Flutter Web, Android Emulator, and iOS/Desktop
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount API Routers
app.include_router(auth_router, prefix=settings.API_V1_STR)
app.include_router(maps_router, prefix=settings.API_V1_STR)
app.include_router(catalog_router, prefix=settings.API_V1_STR)
app.include_router(orders_router, prefix=settings.API_V1_STR)
app.include_router(payments_router, prefix=settings.API_V1_STR)
app.include_router(rider_router, prefix=settings.API_V1_STR)
app.include_router(store_router, prefix=settings.API_V1_STR)

import os

# Serve Dark Store Dashboard HTML
@app.get("/store", response_class=HTMLResponse)
def get_store_dashboard():
    template_path = os.path.join(os.path.dirname(__file__), "templates", "store_dashboard.html")
    with open(template_path, "r", encoding="utf-8") as f:
        return f.read()

@app.get("/")
def root():
    return {
        "status": "online",
        "service": settings.PROJECT_NAME,
        "store": settings.STORE_NAME,
        "store_coordinates": {
            "lat": settings.STORE_LATITUDE,
            "lng": settings.STORE_LONGITUDE
        },
        "delivery_radius": f"{settings.MAX_DELIVERY_RADIUS_KM} KM",
        "store_manager_dashboard": "http://127.0.0.1:8000/store",
        "interactive_api_docs": "http://127.0.0.1:8000/docs"
    }
