import math
import requests
from typing import List, Dict, Any, Optional
from sqlalchemy import text
from app.core.config import settings


class MapsService:
    """
    100% Dynamic Geocoding & Places Autocomplete Engine.
    Uses Google Maps Platform API when GOOGLE_MAPS_API_KEY is configured,
    and falls back to live OpenStreetMap Nominatim API for zero-config dynamic geocoding.
    """

    @classmethod
    def get_nearby_locations(cls, user_lat: Optional[float] = None, user_lng: Optional[float] = None) -> List[Dict[str, Any]]:
        """
        Dynamically fetches nearby places using live Geocoding / Reverse-Geocoding.
        """
        ref_lat = user_lat if user_lat is not None else settings.STORE_LATITUDE
        ref_lng = user_lng if user_lng is not None else settings.STORE_LONGITUDE

        # Perform live reverse geocode for current position
        top_place = cls.reverse_geocode(ref_lat, ref_lng)
        return [
            {
                "id": top_place["id"],
                "name": top_place["name"],
                "address": top_place["address"],
                "landmark": top_place["landmark"],
                "latitude": ref_lat,
                "longitude": ref_lng,
                "distance_km": top_place["distance_km"],
                "is_serviceable": True,
                "eta_minutes": top_place["eta_minutes"],
            }
        ]

    @staticmethod
    def calculate_haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """
        Calculates Great-Circle distance in kilometers between two points on Earth.
        """
        R = 6371.0
        dLat = math.radians(lat2 - lat1)
        dLon = math.radians(lon2 - lon1)
        a = (math.sin(dLat / 2) * math.sin(dLat / 2) +
             math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
             math.sin(dLon / 2) * math.sin(dLon / 2))
        c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
        return round(R * c, 2)

    @classmethod
    def check_serviceability(cls, latitude: float, longitude: float, db=None) -> Dict[str, Any]:
        """
        Validates delivery serviceability dynamically across the city.
        """
        distance = cls.calculate_haversine_distance(settings.STORE_LATITUDE, settings.STORE_LONGITUDE, latitude, longitude)
        is_serviceable = distance <= settings.MAX_DELIVERY_RADIUS_KM
        eta_minutes = max(8, int(8 + (distance * 1.5)))
        if eta_minutes > 35:
            eta_minutes = 35

        return {
            "is_serviceable": is_serviceable,
            "distance_km": distance,
            "max_allowed_radius_km": settings.MAX_DELIVERY_RADIUS_KM,
            "estimated_delivery_minutes": eta_minutes,
            "store_name": settings.STORE_NAME,
            "store_address": settings.STORE_ADDRESS,
            "store_latitude": settings.STORE_LATITUDE,
            "store_longitude": settings.STORE_LONGITUDE,
            "message": f"Delivery available in ~{eta_minutes} mins!" if is_serviceable else f"Delivery not available. Location is {distance:.1f} km away (max {settings.MAX_DELIVERY_RADIUS_KM:.0f} km)."
        }

    @classmethod
    def reverse_geocode(cls, latitude: float, longitude: float) -> Dict[str, Any]:
        """
        Dynamically reverse-geocodes GPS coordinates into a human-readable street address.
        1. Google Maps Geocoding API if GOOGLE_MAPS_API_KEY is available.
        2. Live OpenStreetMap Nominatim Reverse API for dynamic zero-config lookup.
        """
        service_info = cls.check_serviceability(latitude, longitude)
        address_str = ""
        name = ""
        landmark = ""

        # 1. Try Google Maps API if configured
        if settings.GOOGLE_MAPS_API_KEY:
            try:
                url = "https://maps.googleapis.com/maps/api/geocode/json"
                params = {
                    "latlng": f"{latitude},{longitude}",
                    "key": settings.GOOGLE_MAPS_API_KEY,
                    "language": "en"
                }
                res = requests.get(url, params=params, timeout=5)
                if res.status_code == 200:
                    data = res.json()
                    results = data.get("results", [])
                    if results:
                        address_str = results[0].get("formatted_address", "")
                        comps = results[0].get("address_components", [])
                        for c in comps:
                            types = c.get("types", [])
                            if "sublocality_level_1" in types or "sublocality" in types:
                                name = c.get("long_name", "")
                                break
                            if "locality" in types and not name:
                                name = c.get("long_name", "")
                        for c in comps:
                            if "landmark" in c.get("types", []) or "sublocality_level_2" in c.get("types", []):
                                landmark = c.get("long_name", "")
                                break
            except Exception as e:
                print(f"[Google Maps Reverse Geocode Error]: {e}")

        # 2. Live OpenStreetMap Nominatim Dynamic Reverse Geocoding
        if not address_str or not name:
            try:
                url = "https://nominatim.openstreetmap.org/reverse"
                params = {
                    "format": "json",
                    "lat": latitude,
                    "lon": longitude,
                    "zoom": 18,
                    "addressdetails": 1
                }
                headers = {"User-Agent": "FlashFreshQuickCommerce/1.0"}
                res = requests.get(url, params=params, headers=headers, timeout=5)
                if res.status_code == 200:
                    data = res.json()
                    address_str = data.get("display_name", "")
                    addr_details = data.get("address", {})
                    name = (
                        addr_details.get("building") or
                        addr_details.get("amenity") or
                        addr_details.get("shop") or
                        addr_details.get("road") or
                        addr_details.get("suburb") or
                        addr_details.get("neighbourhood") or
                        addr_details.get("residential") or
                        addr_details.get("city_district") or
                        "Selected Location"
                    )
                    landmark = addr_details.get("suburb") or addr_details.get("city") or ""
            except Exception as e:
                print(f"[Nominatim Reverse Geocode Error]: {e}")

        if not address_str:
            name = "Selected Delivery Point"
            address_str = f"Location at {latitude:.5f}, {longitude:.5f}, Telangana, India"

        return {
            "id": f"gps_{int(latitude * 1e5)}_{int(longitude * 1e5)}",
            "name": name,
            "address": address_str,
            "landmark": landmark,
            "latitude": latitude,
            "longitude": longitude,
            "distance_km": service_info["distance_km"],
            "is_serviceable": service_info["is_serviceable"],
            "eta_minutes": service_info["estimated_delivery_minutes"],
            "message": service_info["message"],
            "store_latitude": service_info["store_latitude"],
            "store_longitude": service_info["store_longitude"],
            "max_allowed_radius_km": service_info["max_allowed_radius_km"],
        }

    @classmethod
    def geocode_place(cls, place_id: str) -> Optional[Dict[str, Any]]:
        """
        Resolves a Place ID dynamically to coordinates.
        """
        if not settings.GOOGLE_MAPS_API_KEY or not place_id:
            return None
        try:
            url = "https://maps.googleapis.com/maps/api/place/details/json"
            params = {
                "place_id": place_id,
                "key": settings.GOOGLE_MAPS_API_KEY,
                "fields": "name,formatted_address,geometry"
            }
            res = requests.get(url, params=params, timeout=5)
            if res.status_code == 200:
                data = res.json().get("result", {})
                loc = data.get("geometry", {}).get("location", {})
                lat = loc.get("lat")
                lng = loc.get("lng")
                if lat is None or lng is None:
                    return None
                service_info = cls.check_serviceability(lat, lng)
                return {
                    "id": place_id,
                    "name": data.get("name", "Selected Location"),
                    "address": data.get("formatted_address", f"GPS ({lat}, {lng})"),
                    "landmark": "",
                    "latitude": lat,
                    "longitude": lng,
                    "distance_km": service_info["distance_km"],
                    "is_serviceable": True,
                    "eta_minutes": service_info["estimated_delivery_minutes"],
                    "message": service_info["message"],
                }
        except Exception as e:
            print(f"[Google Maps Place Details Error]: {e}")
        return None

    @classmethod
    def autocomplete_places(cls, query: str) -> List[Dict[str, Any]]:
        """
        100% Dynamic Places Autocomplete API.
        1. Google Places Autocomplete API if GOOGLE_MAPS_API_KEY is available.
        2. Live OpenStreetMap Nominatim Dynamic Search API for zero-config live searching.
        """
        query_str = query.strip()
        if not query_str:
            return []

        # 1. Google Places Autocomplete
        if settings.GOOGLE_MAPS_API_KEY:
            try:
                url = "https://maps.googleapis.com/maps/api/place/autocomplete/json"
                params = {
                    "input": query_str,
                    "key": settings.GOOGLE_MAPS_API_KEY,
                    "location": f"{settings.STORE_LATITUDE},{settings.STORE_LONGITUDE}",
                    "radius": 50000,
                    "components": "country:in"
                }
                res = requests.get(url, params=params, timeout=5)
                if res.status_code == 200:
                    data = res.json()
                    results = []
                    for p in data.get("predictions", []):
                        results.append({
                            "id": p.get("place_id"),
                            "name": p.get("structured_formatting", {}).get("main_text", p.get("description")),
                            "address": p.get("description"),
                            "landmark": p.get("structured_formatting", {}).get("secondary_text", ""),
                            "latitude": None,
                            "longitude": None,
                            "distance_km": None,
                            "is_serviceable": True,
                            "eta_minutes": 15
                        })
                    if results:
                        return results
            except Exception as e:
                print(f"[Google Maps Autocomplete Error]: {e}")

        # 2. Live OpenStreetMap Nominatim Dynamic Search API
        try:
            url = "https://nominatim.openstreetmap.org/search"
            params = {
                "q": f"{query_str}, India",
                "format": "json",
                "addressdetails": 1,
                "limit": 10
            }
            headers = {"User-Agent": "FlashFreshQuickCommerce/1.0"}
            res = requests.get(url, params=params, headers=headers, timeout=5)
            if res.status_code == 200:
                data = res.json()
                results = []
                for idx, item in enumerate(data):
                    lat = float(item.get("lat", 0.0))
                    lng = float(item.get("lon", 0.0))
                    dist = cls.calculate_haversine_distance(settings.STORE_LATITUDE, settings.STORE_LONGITUDE, lat, lng)
                    eta = max(8, int(8 + (dist * 1.5)))
                    results.append({
                        "id": f"nom_{idx}_{lat}_{lng}",
                        "name": item.get("name") or item.get("display_name", "").split(",")[0],
                        "address": item.get("display_name", ""),
                        "landmark": (item.get("address", {})).get("suburb", ""),
                        "latitude": lat,
                        "longitude": lng,
                        "distance_km": dist,
                        "is_serviceable": True,
                        "eta_minutes": eta
                    })
                return results
        except Exception as e:
            print(f"[Nominatim Dynamic Search Error]: {e}")

        return []


maps_service = MapsService()
