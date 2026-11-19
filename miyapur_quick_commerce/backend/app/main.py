from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from collections import defaultdict, deque
import time
import os
from app.core.config import settings
from app.database.db import init_db
from app.api.v1.auth import router as auth_router
from app.api.v1.maps import router as maps_router
from app.api.v1.catalog import router as catalog_router
from app.api.v1.orders import router as orders_router
from app.api.v1.payments import router as payments_router
from app.api.v1.rider import router as rider_router
from app.api.v1.store import router as store_router
from app.api.v1.support import router as support_router

init_db()

app = FastAPI(
    title=settings.PROJECT_NAME,
    description="Hyperlocal Quick-Commerce API with OTP, Cashfree PG & Google Maps",
    version="1.0.0"
)

# CORS allow-list from env. Never "*" in production. Comma-separated origins.
_origins_raw = os.getenv("CORS_ORIGINS", "*")
_allowed_origins = (
    ["*"] if _origins_raw.strip() == "*" else [o.strip() for o in _origins_raw.split(",") if o.strip()]
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_allowed_origins,
    allow_credentials=_allowed_origins != ["*"],
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
)


# --- Simple in-memory rate limiter (per IP) for sensitive endpoints. -------
# Production should swap this for Redis-backed slowapi, but this stops the most
# common abuse (OTP SMS flooding, order spam) out of the box.
class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, max_requests: int = 60, window_seconds: int = 60):
        super().__init__(app)
        self.max_requests = max_requests
        self.window = window_seconds
        self.hits = defaultdict(deque)
        # Stricter limits for expensive endpoints.
        self.strict_paths = {"/api/v1/auth/send-otp", "/api/v1/orders/create"}
        self.strict_max = 5

    async def dispatch(self, request, call_next):
        path = request.url.path
        if path in self.strict_paths or path.startswith("/api/v1/auth/send-otp"):
            limit = self.strict_max
        else:
            limit = self.max_requests
        client = request.client.host if request.client else "unknown"
        if client == "testclient" and settings.ENVIRONMENT != "production":
            return await call_next(request)
        key = f"{client}:{path}"
        now = time.time()
        q = self.hits[key]
        while q and now - q[0] > self.window:
            q.popleft()
        if len(q) >= limit:
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests. Please slow down and retry shortly."},
            )
        q.append(now)
        return await call_next(request)


app.add_middleware(RateLimitMiddleware, max_requests=60, window_seconds=60)

app.include_router(auth_router, prefix=settings.API_V1_STR)
app.include_router(maps_router, prefix=settings.API_V1_STR)
app.include_router(catalog_router, prefix=settings.API_V1_STR)
app.include_router(orders_router, prefix=settings.API_V1_STR)
app.include_router(payments_router, prefix=settings.API_V1_STR)
app.include_router(rider_router, prefix=settings.API_V1_STR)
app.include_router(store_router, prefix=settings.API_V1_STR)
app.include_router(support_router, prefix=settings.API_V1_STR)

import os

@app.get("/store", response_class=HTMLResponse)
@app.get("/store/dashboard", response_class=HTMLResponse)
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
        "store_manager_dashboard": "https://flash-fresh.onrender.com/store",
        "interactive_api_docs": "https://flash-fresh.onrender.com/docs"
    }
