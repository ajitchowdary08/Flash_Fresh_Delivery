@echo off
echo ========================================================
echo       MIYAPUR QUICK COMMERCE - LIVE DATABASE VIEWER
echo ========================================================
echo.
cd /d "%~dp0backend"
.\venv\Scripts\python.exe -c "from app.database.db import SessionLocal; from app.models.models import User, Address, Order; db = SessionLocal(); users = db.query(User).all(); print(f'--- REGISTERED USERS ({len(users)}) ---'); [print(f'Phone: +91 {u.phone} | Name: {u.name} | User ID: {u.id} | Joined: {u.created_at}') for u in users]; addrs = db.query(Address).all(); print(f'\n--- SAVED DELIVERY ADDRESSES ({len(addrs)}) ---'); [print(f'User ID: {a.user_id} | Type: {a.label} | Flat: {a.house_number} | Street: {a.street_address} | Distance: {a.distance_km} KM') for a in addrs]; orders = db.query(Order).all(); print(f'\n--- ORDERS ({len(orders)}) ---'); [print(f'Order ID: {o.id} | User: {o.user_id} | Total: Rs.{o.grand_total} | Status: {o.status}') for o in orders]; db.close()"
echo.
echo ========================================================
pause
