from typing import Optional
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from app.schemas.schemas import GeofenceCheckRequest
from app.services.maps_service import maps_service
from app.core.config import settings

router = APIRouter(prefix="/maps", tags=["Google Maps & Geocoding Service"])


class ReverseGeocodeRequest(BaseModel):
    latitude: float
    longitude: float


class GeocodePlaceRequest(BaseModel):
    place_id: str


@router.get("/locations")
def autocomplete_locations(query: str = ""):
    """
    Calls Google Places Autocomplete API or returns verified Miyapur delivery landmarks.
    Each prediction carries its place_id; resolve it through /maps/geocode to get
    the resolved coordinates for the saved address. We deliver ANYWHERE — there is
    no radius cap, so the resolved location is always accepted.
    """
    return maps_service.autocomplete_places(query)


@router.get("/nearby")
def get_nearby_locations(lat: Optional[float] = None, lng: Optional[float] = None):
    """
    Returns nearby delivery locations around the Miyapur Central Hub. If lat and
    lng are provided, distances are computed from the user's current coordinates
    and sorted closest to the user first.
    """
    return maps_service.get_nearby_locations(user_lat=lat, user_lng=lng)


@router.post("/check-serviceability")
def check_serviceability(req: GeofenceCheckRequest):
    """
    Returns the distance and ETA from the Miyapur Central Hub to the given
    coordinates. We deliver ANYWHERE, so is_serviceable is always True — this
    endpoint only provides distance/ETA info for display.
    """
    return maps_service.check_serviceability(req.latitude, req.longitude)


@router.post("/reverse-geocode")
def reverse_geocode(req: ReverseGeocodeRequest):
    """
    Reverse-geocodes GPS coordinates to a human-readable address and computes
    the distance/ETA from the hub. is_serviceable is always True (we deliver
    anywhere); the client uses the address + distance for display.
    """
    return maps_service.reverse_geocode(req.latitude, req.longitude)


@router.post("/geocode")
def geocode_place(req: GeocodePlaceRequest):
    """
    Resolves a Google Place ID (returned by /maps/locations) into coordinates
    and computes the distance/ETA. We deliver anywhere, so the resolved location
    is always accepted.
    """
    result = maps_service.geocode_place(req.place_id)
    if result is None:
        raise HTTPException(status_code=400, detail="Unable to resolve this place. Please pick another location.")
    return result


@router.get("/hub")
def get_hub_info():
    """
    Returns the central Dark Store hub coordinates. Used by the client to center
    the GoogleMap widget on the hub. There is no delivery-radius cap.
    """
    return {
        "store_name": settings.STORE_NAME,
        "store_latitude": settings.STORE_LATITUDE,
        "store_longitude": settings.STORE_LONGITUDE,
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
