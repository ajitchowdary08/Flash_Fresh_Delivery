import pytest
from app.services.maps_service import maps_service
from app.core.config import settings

def test_hub_location_serviceability():
    # Exact Miyapur Central Dark Store Hub pin.
    res = maps_service.check_serviceability(settings.STORE_LATITUDE, settings.STORE_LONGITUDE)
    assert res["is_serviceable"] is True
    assert res["distance_km"] == 0.0

def test_nearby_allwyn_colony_serviceability():
    # Allwyn Colony (~1.2 KM from hub)
    res = maps_service.check_serviceability(17.4985, 78.3720)
    assert res["is_serviceable"] is True
    assert res["distance_km"] < 10.0

def test_far_away_location_is_still_serviceable():
    # We deliver ANYWHERE — there is no radius cap. A location ~115 KM away
    # must still be serviceable (only the distance/ETA differ).
    res = maps_service.check_serviceability(16.4200, 78.3400)
    assert res["is_serviceable"] is True
    assert res["distance_km"] > 10.0
    assert res["estimated_delivery_minutes"] > 0

def test_reverse_geocode_allows_any_checkout():
    # Shamshabad airport ~29 KM away — still serviceable (we deliver anywhere).
    res = maps_service.reverse_geocode(17.2401, 78.4295)
    assert res["is_serviceable"] is True
    assert res["distance_km"] > 10.0

def test_reverse_geocode_nearby_checkout():
    # Kukatpally ~2.5 KM from hub — serviceable.
    res = maps_service.reverse_geocode(17.4980, 78.3910)
    assert res["is_serviceable"] is True
    assert res["distance_km"] <= 10.0
    assert res["eta_minutes"] is not None
