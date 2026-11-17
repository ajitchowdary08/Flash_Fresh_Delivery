# Changelog — Miyapur Quick Commerce Update (2026-11-16)

## 🎯 Core Requirement Delivered: 10 KM Delivery Geofence from Miyapur Hub

The hub is the exact Google Maps pin you shared:
https://maps.app.goo.gl/5fc6a8ZMgjfttUiB9 → `17.495101, 78.367535`

When a customer's detected location is **more than 10 KM** from the hub, the app
shows **"Delivery Not Available"** and blocks checkout. This is enforced at
three layers (GPS detection, saved address, order creation) so it cannot be
bypassed by a client bug.

---

## ✅ What was checked and verified

### Map integration (already present, now verified)
- Google Maps API key `AIzaSyBNnGocMHDAzc9cV61uTeHFpbKiogeIWas` is correctly set in:
  - `backend/.env` → `GOOGLE_MAPS_API_KEY`
  - `customer_app/android/app/src/main/AndroidManifest.xml` → `com.google.android.geo.API_KEY`
  - `customer_app/ios/Runner/Info.plist` → `GoogleMapsApiKey` (newly added)
- The backend geofence service (`/maps/check-serviceability`) was already implemented
  and uses PostGIS `ST_Distance` with a Haversine fallback.

### Hub coordinates (corrected)
- The config used `17.4968, 78.3614` — close, but not the exact Google Maps pin.
- Resolved the short URL `https://maps.app.goo.gl/5fc6a8ZMgjfttUiB9` → it redirects to
  `17.495101, 78.367535`. Updated **every** occurrence across backend and Flutter.

---

## 🛠️ Bugs fixed and features implemented

### 1. GPS "Detect Current Location" with geofence verdict (NEW — the core ask)
- New `location_picker_sheet.dart` with a **"📍 Detect Current Location (GPS)"** button.
- Uses `geolocator` to read a high-accuracy GPS fix.
- Calls the new backend `POST /maps/reverse-geocode` endpoint.
- If `is_serviceable == false`, shows a red **"Delivery Not Available"** banner and a
  bottom block notice, and the address cannot be used for checkout.

### 2. Visual GoogleMap widget with 10 KM radius circle (NEW)
- The location picker now embeds a `GoogleMap` widget showing:
  - A green marker at the Miyapur Central Dark Store Hub.
  - A translucent green circle of 10 KM radius around the hub.
  - A second marker at the detected GPS location (green if in-zone, red if out-of-zone).

### 3. Hub coordinates corrected to the exact Google Maps pin
- `backend/.env`, `backend/app/core/config.py`, `backend/app/services/maps_service.py`
- `customer_app/lib/services/api_service.dart`, `main_shell.dart`, `order_tracking_screen.dart`,
  `cart_screen.dart`, `models.dart`, `profile_screen.dart`
- `backend/app/api/v1/orders.py`, `auth.py`, `backend/app/models/models.py`

### 4. New backend map endpoints
- `GET  /api/v1/maps/hub` — returns hub coordinates + radius for the map widget.
- `POST /api/v1/maps/reverse-geocode` — GPS → address + authoritative geofence verdict.
- `POST /api/v1/maps/geocode` — Google Place ID → coordinates + geofence verdict.
- `GET  /api/v1/maps/locations` — Google Places Autocomplete (now returns place_id for
  client-side resolution + geofence re-check).

### 5. Login data-loss bug fixed (P0 from the improvement plan)
- `api_service.dart` `verifyOtp` previously fabricated a `jwt_prod_token_signed` token
  and a canonical `user_id` when the backend was unreachable. This created a divergent
  local user that lost all order history on re-login.
- Now returns an explicit failure ("Cannot connect to server...") so the UI shows the
  real error instead of faking success.
- Added a typed `ApiException` class for genuine failures.

### 6. Cashfree webhook — signed, idempotent, fail-closed (NEW)
- New `POST /api/v1/payments/cashfree/webhook` endpoint.
- Verifies `Base64(HMAC-SHA256(timestamp + raw_body, secret))` with a constant-time compare.
- Rejects stale timestamps (5-minute skew window) — replay protection.
- Re-fetches the authoritative order status from Cashfree before flipping to `PAID`.
- Idempotent: a second webhook for an already-PAID order is a no-op.
- **Fails closed**: returns HTTP 503 when `CASHFREE_WEBHOOK_SECRET` is not configured.

### 7. Cashfree server-authoritative verify endpoint (NEW)
- New `POST /api/v1/payments/cashfree/verify` — the client calls this after the
  drop-in closes; the backend re-fetches the order status from Cashfree and only
  then marks the order PAID. The client never decides success.

### 8. Cashfree payment gateway integration (FIX)
- `verify_webhook_signature` previously returned `True` when no secret was configured
  (a forged webhook could mark an order paid). Now returns `False`.

### 9. Auth fail-closed in production (FIX)
- `backend/app/core/security.py` now resolves the real `User` row from the DB for
  every protected endpoint. A present-but-invalid JWT is always rejected (401).
  A missing token is allowed only in `development`; `production` returns 401.

### 10. Fail-closed config (FIX)
- `backend/app/core/config.py` refuses to boot in `production` when:
  - `JWT_SECRET_KEY` is missing/weak (< 32 chars or a known placeholder).
  - Cashfree test credentials are still in use (`TEST...` / `cfsk_ma_test_...`).
  - No webhook secret is configured.
  - `GOOGLE_MAPS_API_KEY` is missing.
  - `DEV_OTP_BYPASS` is left on.
- The app exits with a clear error list instead of starting insecure.

### 11. OTP backdoor gated (FIX)
- The `123456` test OTP is accepted only in `development` AND when `DEV_OTP_BYPASS=true`.
  Always rejected in `production`.

### 12. iOS permissions (NEW)
- Added `NSLocationWhenInUseUsageDescription` and `NSLocationAlwaysUsageDescription`
  to `ios/Runner/Info.plist` (required by `geolocator`).

### 13. Tests updated and passing
- Updated `tests/test_geofence.py` to the corrected hub coordinates.
- Added `test_reverse_geocode_blocks_out_of_zone_checkout` and
  `test_reverse_geocode_allows_in_zone_checkout`.
- All 13 backend tests pass.

---

## 📦 Files modified

### Backend
- `backend/.env` — corrected hub coordinates.
- `backend/.env.example` — comprehensive env documentation (all new vars).
- `backend/app/core/config.py` — fail-closed production validation, new Cashfree/CORS/OTP vars.
- `backend/app/core/security.py` — DB-backed auth, fail-closed in production.
- `backend/app/services/maps_service.py` — corrected hub, new `reverse_geocode` + `geocode_place`.
- `backend/app/services/payment_service.py` — fail-closed webhooks, new Cashfree HMAC verifier.
- `backend/app/api/v1/maps.py` — new `/reverse-geocode`, `/geocode`, `/hub` endpoints.
- `backend/app/api/v1/payments.py` — new `/cashfree/verify`, `/cashfree/webhook` endpoints.
- `backend/app/api/v1/orders.py`, `auth.py`, `backend/app/models/models.py` — coordinate defaults updated.
- `backend/tests/test_geofence.py` — updated for new coordinates + new reverse-geocode tests.

### Customer app (Flutter)
- `customer_app/pubspec.yaml` — added `geolocator: ^13.0.1`.
- `customer_app/lib/services/api_service.dart` — `ApiException`, fixed `verifyOtp`/`sendOtp`,
  new `reverseGeocode`/`geocodePlace`/`checkServiceability` methods, hub constants.
- `customer_app/lib/screens/location_picker_sheet.dart` — full rewrite with GoogleMap widget,
  GPS detect button, 10 KM radius circle, "Delivery Not Available" banner.
- `customer_app/lib/screens/main_shell.dart` — corrected hub coordinates.
- `customer_app/lib/screens/cart_screen.dart` — corrected hub coordinates.
- `customer_app/lib/screens/order_tracking_screen.dart` — corrected hub coordinates.
- `customer_app/lib/models/models.dart` — corrected hub coordinate fallbacks.
- `customer_app/lib/screens/profile_screen.dart` — corrected hub coordinates.
- `customer_app/ios/Runner/Info.plist` — location permission strings + GoogleMapsApiKey.
- `customer_app/android/app/src/main/AndroidManifest.xml` — already had the API key (verified).

### Docs
- `README.md` — new sections for map integration, geofence, GPS detection, security fixes.
- `CHANGELOG.md` — this file.

---

## 🧪 How to verify

### Backend tests
```bash
cd backend
python -m pytest tests/ -q
# Expected: 13 passed
```

### Geofence via curl (backend running on Render)
```bash
# In zone (hub itself) -> is_serviceable: true, distance 0.0
curl -X POST https://flash-fresh.onrender.com/api/v1/maps/check-serviceability \
  -H "Content-Type: application/json" \
  -d '{"latitude": 17.495101, "longitude": 78.367535}'

# Out of zone (Shamshabad ~29 km) -> is_serviceable: false
curl -X POST https://flash-fresh.onrender.com/api/v1/maps/check-serviceability \
  -H "Content-Type: application/json" \
  -d '{"latitude": 17.2401, "longitude": 78.4295}'
```

### GPS detection in the app
1. Open the customer app.
2. Tap the location bar at the top to open the location picker.
3. Tap **"📍 Detect Current Location (GPS)"**.
4. The map drops a marker at your GPS fix and draws the 10 KM circle around the hub.
5. If you are more than 10 KM from the Miyapur hub, the banner turns red and reads
   **"Delivery Not Available"**, and checkout is blocked.
