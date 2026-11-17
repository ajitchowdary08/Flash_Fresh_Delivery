from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.schemas.schemas import GeofenceCheckRequest
from app.services.maps_service import maps_service
from app.core.config import settings

router = APIRouter(prefix="/maps", tags=["Google Maps & 10KM Geofence"])


class ReverseGeocodeRequest(BaseModel):
    latitude: float
    longitude: float


class GeocodePlaceRequest(BaseModel):
    place_id: str


@router.get("/locations")
def autocomplete_locations(query: str = ""):
    """
    Calls Google Places Autocomplete API or returns verified Miyapur delivery landmarks.
    Each prediction carries its place_id; resolve it through /maps/geocode before
    accepting the address, so the 10 KM geofence is enforced on the resolved coordinates.
    """
    return maps_service.autocomplete_places(query)


@router.get("/nearby")
def get_nearby_locations(lat: Optional[float] = None, lng: Optional[float] = None):
    """
    Returns verified delivery locations within the 10 KM radius of the Miyapur Central Hub.
    If lat and lng are provided, distances are computed from the user's current coordinates
    and sorted closest to the user first.
    """
    return maps_service.get_nearby_locations(user_lat=lat, user_lng=lng)


@router.post("/check-serviceability")
def check_serviceability(req: GeofenceCheckRequest):
    """
    Verifies if coordinates fall strictly within the 10.0 KM delivery radius of the
    Miyapur Central Dark Store Hub. This is the authoritative geofence check used by
    every order, every saved address, and every GPS-detected location.
    """
    return maps_service.check_serviceability(req.latitude, req.longitude)


@router.post("/reverse-geocode")
def reverse_geocode(req: ReverseGeocodeRequest):
    """
    Reverse-geocodes GPS coordinates to a human-readable address AND runs the 10 KM
    geofence check. The client calls this after detecting the user's current location
    via the device GPS — if `is_serviceable` is False, the UI must show
    'Delivery Not Available' and block checkout.
    """
    return maps_service.reverse_geocode(req.latitude, req.longitude)


@router.post("/geocode")
def geocode_place(req: GeocodePlaceRequest):
    """
    Resolves a Google Place ID (returned by /maps/locations) into coordinates and
    runs the 10 KM geofence check. Used after a Places Autocomplete selection so the
    chosen location is validated against the delivery radius before it is accepted.
    """
    result = maps_service.geocode_place(req.place_id)
    if result is None:
        raise HTTPException(status_code=400, detail="Unable to resolve this place. Please pick another location.")
    return result


@router.get("/hub")
def get_hub_info():
    """
    Returns the central Dark Store hub coordinates and delivery radius so the client
    can render the geofence circle on the GoogleMap widget.
    """
    return {
        "store_name": settings.STORE_NAME,
        "store_latitude": settings.STORE_LATITUDE,
        "store_longitude": settings.STORE_LONGITUDE,
        "max_allowed_radius_km": settings.MAX_DELIVERY_RADIUS_KM,
        "store_address": settings.STORE_ADDRESS,
    }


@router.get("/route")
def get_directions_route(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
):
    """
    Returns real street route coordinates snapped to the road network between
    the Miyapur Central Hub and the customer delivery destination.
    Uses Google Directions API if configured or the Miyapur arterial street network.
    """
    return maps_service.get_directions_route(
        origin_lat=origin_lat,
        origin_lng=origin_lng,
        dest_lat=dest_lat,
        dest_lng=dest_lng,
    )
