import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/preferences.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';

/// Central Dark Store Hub coordinates (Matches backend configuration)
const double _kHubLatitude = 17.495101;
const double _kHubLongitude = 78.367535;
const double _kMaxDeliveryRadiusKm = 10.0;

class MapPinPickerScreen extends StatefulWidget {
  final double initialLatitude;
  final double initialLongitude;
  final String initialAreaName;
  final Function(LocationModel confirmedLocation) onLocationConfirmed;

  const MapPinPickerScreen({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
    this.initialAreaName = "",
    required this.onLocationConfirmed,
  });

  @override
  State<MapPinPickerScreen> createState() => _MapPinPickerScreenState();
}

class _MapPinPickerScreenState extends State<MapPinPickerScreen> {
  GoogleMapController? _mapController;
  late CameraPosition _cameraPosition;

  final TextEditingController _searchController = TextEditingController();
  List<LocationModel> _searchResults = [];
  bool _isSearching = false;
  bool _isGeocoding = false;
  bool _isLocatingGps = false;

  // Active pin details resolved from current map camera center
  String _areaTitle = "Resolving Address...";
  String _fullAddress = "Fetching details from Google Maps...";
  double _currentLat = 17.495101;
  double _currentLng = 78.367535;
  double _distanceKm = 0.5;
  bool _isServiceable = true;
  int _etaMinutes = 10;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _currentLat = widget.initialLatitude != 0.0 ? widget.initialLatitude : _kHubLatitude;
    _currentLng = widget.initialLongitude != 0.0 ? widget.initialLongitude : _kHubLongitude;
    if (widget.initialAreaName.isNotEmpty) {
      _areaTitle = widget.initialAreaName;
    }

    _cameraPosition = CameraPosition(
      target: LatLng(_currentLat, _currentLng),
      zoom: 16.0,
    );

    // Initial reverse geocode
    _reverseGeocodeCenter(_currentLat, _currentLng);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocodeCenter(double lat, double lng, {String? overrideTitle}) async {
    setState(() {
      _isGeocoding = true;
      _currentLat = lat;
      _currentLng = lng;
    });

    try {
      final res = await ApiService.reverseGeocode(lat, lng);
      if (mounted) {
        String title = overrideTitle ?? (res["name"] ?? "").toString();
        if (title.isEmpty || title == "Detected Location") {
          final addr = (res["address"] ?? "").toString();
          if (addr.isNotEmpty && !addr.startsWith("GPS (") && !addr.startsWith("Detected Location")) {
            title = addr.split(',').first.trim();
          } else {
            title = "Hafeezpet Area";
          }
        }

        String addr = (res["address"] ?? "").toString();
        if (addr.isEmpty || addr.startsWith("GPS (") || addr.startsWith("Detected Location")) {
          addr = "$title, Hafeezpet, Hyderabad, Telangana 500049";
        }

        setState(() {
          _areaTitle = title;
          _fullAddress = addr;
          _distanceKm = (res["distance_km"] ?? 0.0).toDouble();
          _isServiceable = res["is_serviceable"] ?? true;
          _etaMinutes = (res["eta_minutes"] as num?)?.toInt() ??
              (res["estimated_delivery_minutes"] as num?)?.toInt() ??
              10;
          _isGeocoding = false;
        });
      }
    } catch (_) {
      if (mounted) {
        final title = overrideTitle ?? "Hafeezpet Area";
        setState(() {
          _areaTitle = title;
          _fullAddress = "$title, Hafeezpet, Hyderabad, Telangana 500049";
          _isGeocoding = false;
        });
      }
    }
  }

  void _onCameraMove(CameraPosition position) {
    _cameraPosition = position;
  }

  void _onCameraIdle() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _reverseGeocodeCenter(
        _cameraPosition.target.latitude,
        _cameraPosition.target.longitude,
      );
    });
  }

  Future<void> _animateToCurrentGps() async {
    setState(() => _isLocatingGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          LiquidToast.show(
            context,
            message: "Please enable location services on your device.",
            icon: Icons.location_off_rounded,
            accentColor: Colors.orange.shade800,
          );
        }
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final newTarget = LatLng(pos.latitude, pos.longitude);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(newTarget, 16.5));
      _reverseGeocodeCenter(pos.latitude, pos.longitude);
    } catch (e) {
      if (mounted) {
        LiquidToast.show(
          context,
          message: "Unable to detect GPS position.",
          icon: Icons.error_outline_rounded,
          accentColor: Colors.red.shade700,
        );
      }
    } finally {
      if (mounted) setState(() => _isLocatingGps = false);
    }
  }

  void _onSearchQueryChanged(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }
    setState(() => _isSearching = true);
    final results = await ApiService.getLocations(query: q);
    if (mounted) {
      setState(() {
        _searchResults = results;
      });
    }
  }

  void _selectSearchResult(LocationModel loc) async {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchResults = [];
    });

    double targetLat = loc.latitude;
    double targetLng = loc.longitude;

    if (targetLat == 0.0 || targetLng == 0.0) {
      final geo = await ApiService.geocodePlace(loc.id);
      if (geo != null) {
        targetLat = (geo["latitude"] as num).toDouble();
        targetLng = (geo["longitude"] as num).toDouble();
      }
    }

    if (targetLat != 0.0 && targetLng != 0.0) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(targetLat, targetLng), 16.5),
      );
      _reverseGeocodeCenter(targetLat, targetLng);
    }
  }

  void _handleConfirmAndProceed() async {
    final confirmedLoc = LocationModel(
      id: "map_loc_${DateTime.now().millisecondsSinceEpoch}",
      name: _areaTitle.isNotEmpty ? _areaTitle : "Selected Delivery Point",
      address: _fullAddress,
      latitude: _currentLat,
      longitude: _currentLng,
      landmark: "",
      distanceKm: _distanceKm,
      isServiceable: true,
      etaMinutes: _etaMinutes,
    );

    await Preferences.setString(Preferences.keyActiveLocId, confirmedLoc.id);
    await Preferences.setString(Preferences.keyActiveLocName, confirmedLoc.name);
    await Preferences.setString(Preferences.keyActiveLocAddress, confirmedLoc.address);
    await Preferences.setDouble(Preferences.keyActiveLocLat, confirmedLoc.latitude);
    await Preferences.setDouble(Preferences.keyActiveLocLng, confirmedLoc.longitude);
    await Preferences.setDouble(Preferences.keyActiveLocDist, confirmedLoc.distanceKm);
    await Preferences.setBoolean(Preferences.keyActiveLocServiceable, confirmedLoc.isServiceable);
    await Preferences.setInt(Preferences.keyActiveLocEta, confirmedLoc.etaMinutes);

    widget.onLocationConfirmed(confirmedLoc);
  }

  Set<Circle> get _geofenceCircles {
    return {
      Circle(
        circleId: const CircleId("hub_10km_zone"),
        center: const LatLng(_kHubLatitude, _kHubLongitude),
        radius: _kMaxDeliveryRadiusKm * 1000, // 10 KM in meters
        strokeColor: const Color(0xFF2563EB),
        strokeWidth: 2,
        fillColor: const Color(0x152563EB),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Full Screen Interactive Google Map
          GoogleMap(
            initialCameraPosition: _cameraPosition,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            onTap: (LatLng latLng) {
              _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));
              _reverseGeocodeCenter(latLng.latitude, latLng.longitude);
            },
            circles: const {},
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: false,
            mapToolbarEnabled: false,
          ),

          // 2. Stationary Center Marker Pin Overlay (Exact Swiggy style - Image 3)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 36.0), // Align pin tip at screen center
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      "Order delivers here",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 48,
                        color: _isServiceable ? const Color(0xFF2563EB) : Colors.red.shade700,
                      ),
                      const Positioned(
                        top: 10,
                        child: Icon(Icons.circle, size: 14, color: Colors.white),
                      ),
                    ],
                  ),
                  // Pin shadow dot on map
                  Container(
                    width: 10,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: const BorderRadius.all(Radius.elliptical(10, 5)),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Top Floating Header Bar with Back button & Search Box (Image 3)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      // White rounded Back Button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              )
                            ],
                          ),
                          child: const Icon(Icons.arrow_back, color: Color(0xFF111827), size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Search Input Box
                      Expanded(
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              )
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
                                  onChanged: _onSearchQueryChanged,
                                  decoration: const InputDecoration(
                                    hintText: "Search an area or address",
                                    hintStyle: TextStyle(color: Colors.black45, fontSize: 13),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const Icon(Icons.search_rounded, color: Colors.black54, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Live Autocomplete Suggestions Overlay
                  if (_isSearching && _searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, idx) {
                          final loc = _searchResults[idx];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on_outlined, color: Color(0xFF2563EB), size: 18),
                            title: Text(loc.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text(loc.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                            onTap: () => _selectSearchResult(loc),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // 4. Floating "🎯 Current location" Button (Exact Swiggy style - Image 3)
          Positioned(
            right: 16,
            bottom: 210,
            child: GestureDetector(
              onTap: _isLocatingGps ? null : _animateToCurrentGps,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isLocatingGps)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD97706)),
                      )
                    else
                      const Icon(Icons.gps_fixed_rounded, color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 6),
                    const Text(
                      "Current location",
                      style: TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 5. Bottom Sheet Card (Exact Swiggy Style - Image 3)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location Icon + Title
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isGeocoding ? "Locating pin position..." : _areaTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Full Address Subtitle
                  Text(
                    _isGeocoding ? "Reverse geocoding coordinates..." : _fullAddress,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Delivery Zone Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: Color(0xFF047857),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "⚡ ~$_etaMinutes Mins • Delivery Available",
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // "Confirm & proceed" Primary Button (Exact Swiggy Style - Image 3)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isGeocoding ? null : _handleConfirmAndProceed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isServiceable ? const Color(0xFF2563EB) : Colors.grey.shade400,
                        foregroundColor: Colors.white,
                        elevation: _isServiceable ? 4 : 0,
                        shadowColor: const Color(0xFF2563EB).withOpacity(0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _isServiceable ? "Confirm & proceed" : "Location Outside Delivery Zone",
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
