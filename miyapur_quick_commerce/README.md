# ⚡ Miyapur 10-Minute Quick-Commerce Ecosystem
### Fresh Vegetables (Daily) & Fresh Meat (Sundays) • 10 KM Miyapur Radius

---

## 🏗️ The 3 Applications

| App | Platform | Description | Launcher Script |
| :--- | :--- | :--- | :--- |
| **1. Backend & Store Hub** | Python / Web | FastAPI backend + Live Store Packing Dashboard & Stock Intake | `start_backend.bat` |
| **2. Customer App** | Flutter (Android/iOS/Web) | Veggies & Sunday meat catalog, geofence check, mock OTP, mock UPI | `start_app.bat` |
| **3. Delivery Partner App** | Flutter (Android/iOS/Web) | Online/Offline duty, order radar, store pickup, customer drop & earnings | `start_rider_app.bat` |
| **4. Live Database Viewer** | Windows Batch / CLI | View registered users, saved addresses, and active orders in real-time | `view_db.bat` |

---

## 🚀 Quick Launch Guide

### Step 1: Start Backend & Dark Store Hub
Run `start_backend.bat` or:
```bash
cd backend
venv\Scripts\python.exe run_backend.py
```
* **API Server:** http://127.0.0.1:8000
* **Store Manager Dashboard:** http://127.0.0.1:8000/store
* **Swagger API Docs:** http://127.0.0.1:8000/docs

---

### Step 2: Start Customer App
Run `start_app.bat` or:
```bash
cd customer_app
flutter run -d chrome
```
*(Or `flutter run -d android` to test on your phone)*

---

### Step 3: Start Delivery Partner (Rider) App
Run `start_rider_app.bat` or:
```bash
cd rider_app
flutter run -d chrome
```

---

## 🔄 End-to-End Test Walkthrough

1. **Place Order (Customer App):**
   * Log in with mobile number and mock OTP `123456`.
   * Pick an address in Miyapur (e.g. Madinaguda GSM Mall - 2.5 km).
   * Add 1kg Tomatoes and 1kg Sunday Chicken to basket.
   * Tap **Proceed to Pay** ➔ Select **Google Pay (Mock UPI)** ➔ Order placed!

2. **Weigh & Pack (Dark Store Dashboard at `http://127.0.0.1:8000/store`):**
   * Watch the order appear live on the screen!
   * Click **Mark Packed & Tag Bag** to simulate digital scale verification and view the ESC/POS thermal bag slip.

3. **Deliver (Delivery Partner App):**
   * Toggle status to **ONLINE**.
   * See the order pop up with **₹45 PAY**.
   * Tap **Accept Delivery Order**.
   * Click **Confirm Bag Picked Up from Hub** ➔ Click **Confirm Order Delivered to Customer**.
   * Payout is credited to rider wallet, and customer tracking updates to **Delivered**!

---

## 🗺️ Map Integration & 10 KM Delivery Geofence

The Miyapur Central Dark Store Hub is the **single delivery origin**. The exact hub
pin is verified from Google Maps: https://maps.app.goo.gl/5fc6a8ZMgjfttUiB9

| Setting | Value |
| :--- | :--- |
| Hub latitude  | `17.495101` |
| Hub longitude | `78.367535` |
| Delivery radius | `10.0 KM` (strict) |

### Where the Google Maps API key is configured

The same `GOOGLE_MAPS_API_KEY` is wired into **three** places — keep them in sync:

1. `backend/.env` → `GOOGLE_MAPS_API_KEY` (used by the backend for Places Autocomplete, Geocoding and Reverse-Geocoding).
2. `customer_app/android/app/src/main/AndroidManifest.xml` → `com.google.android.geo.API_KEY` (used by the Android `GoogleMap` widget).
3. `customer_app/ios/Runner/Info.plist` → `GoogleMapsApiKey` (used by the iOS `GoogleMap` widget).

### How the 10 KM radius is enforced

The geofence is **authoritative on the backend** and is checked at three points:

1. **GPS detection** — `POST /api/v1/maps/reverse-geocode` resolves the device GPS to an address and returns `is_serviceable: false` when the detected location is outside the radius. The customer app shows a red **"Delivery Not Available"** banner and blocks checkout.
2. **Saved address** — `POST /api/v1/auth/addresses/{user_id}` rejects any address outside the radius with HTTP 400.
3. **Order creation** — `POST /api/v1/orders/create` rejects any order whose `latitude/longitude` is outside the radius with HTTP 400, even if a client bug allowed an out-of-zone address through.

### Customer-app GPS detection ("Detect Current Location")

The location picker sheet now includes a **"📍 Detect Current Location (GPS)"** button
that:

1. Requests location permission (`geolocator`).
2. Reads a high-accuracy GPS fix.
3. Calls the backend `reverse-geocode` endpoint to get a human-readable address and the authoritative 10 KM verdict.
4. Drops a marker on the embedded `GoogleMap` widget (green = in zone, red = out of zone) and draws the **10 KM delivery-radius circle** around the hub.
5. If the detected location is outside the radius, shows a red **"Delivery Not Available"** banner and blocks checkout.

### New / changed backend endpoints

| Method | Path | Purpose |
| :--- | :--- | :--- |
| GET  | `/api/v1/maps/hub` | Returns hub coordinates + radius (for the map widget). |
| POST | `/api/v1/maps/check-serviceability` | Authoritative 10 KM geofence check for a coordinate. |
| POST | `/api/v1/maps/reverse-geocode` | GPS → address + geofence verdict (used by the GPS button). |
| POST | `/api/v1/maps/geocode` | Google Place ID → coordinates + geofence verdict. |
| GET  | `/api/v1/maps/locations` | Google Places Autocomplete (or preset Hyderabad landmarks). |
| POST | `/api/v1/payments/cashfree/verify` | Server-authoritative Cashfree payment verification (re-fetches order status from Cashfree; the client never decides success). |
| POST | `/api/v1/payments/cashfree/webhook` | Signed, idempotent Cashfree webhook (HMAC-SHA256, fail-closed, replay-protected). |

---

## 🔐 Security & Reliability Fixes Applied

This update closes the P0 / P1 gaps identified in the production-readiness review:

- **Auth fail-closed in production.** `backend/app/core/security.py` now resolves the real `User` row from the DB for every protected endpoint and rejects invalid/expired JWTs in all environments. A missing token is allowed only in `development`; `production` returns 401.
- **Fail-closed config.** `backend/app/core/config.py` refuses to boot in `production` when `JWT_SECRET_KEY` is missing/weak, when Cashfree test credentials are still in use, when no webhook secret is configured, when `GOOGLE_MAPS_API_KEY` is missing, or when `DEV_OTP_BYPASS` is left on. The app exits with a clear error list instead of starting insecure.
- **OTP backdoor gated.** The `123456` test OTP is accepted only in `development` and only when `DEV_OTP_BYPASS=true`; it is always rejected in production.
- **Login data-loss bug fixed.** `customer_app/lib/services/api_service.dart` `verifyOtp` no longer fabricates a `jwt_prod_token_signed` token + canonical user id when the backend is unreachable. It now returns an explicit failure so the UI shows "cannot connect" instead of creating a divergent local user that loses order history on re-login. A typed `ApiException` was added for genuine failures.
- **Cashfree webhook is signed + idempotent.** `verify_cashfree_webhook_signature` implements the official `Base64(HMAC-SHA256(timestamp + raw_body, secret))` with a constant-time compare, rejects stale timestamps (replay protection), re-fetches the authoritative order status from Cashfree before flipping to `PAID`, and is a no-op for an already-PAID order.
- **Razorpay webhook fails closed.** `verify_webhook_signature` previously returned `True` when no secret was configured; it now returns `False` so a forged webhook can never mark an order paid.
- **Server-authoritative pricing & idempotency.** Order creation already re-prices every item from the DB and rejects duplicate `idempotency_key` submissions.

---

## 🧪 Verifying the geofence end-to-end

With the backend running (`http://127.0.0.1:8000`):

```bash
# In zone (Kukatpally ~2.5 km from hub) -> is_serviceable: true
curl -X POST http://127.0.0.1:8000/api/v1/maps/check-serviceability \
  -H "Content-Type: application/json" \
  -d '{"latitude": 17.4980, "longitude": 78.3910}'

# Out of zone (Shamshabad ~29 km from hub) -> is_serviceable: false
curl -X POST http://127.0.0.1:8000/api/v1/maps/check-serviceability \
  -H "Content-Type: application/json" \
  -d '{"latitude": 17.2401, "longitude": 78.4295}'
```

In the customer app, open the location picker, tap **"📍 Detect Current Location (GPS)"**,
and the map will drop a marker plus the 10 KM circle. If you are more than 10 KM from
the Miyapur hub, the banner turns red and reads **"Delivery Not Available"**.

