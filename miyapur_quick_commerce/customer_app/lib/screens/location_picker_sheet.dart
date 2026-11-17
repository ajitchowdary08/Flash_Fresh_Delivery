import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/preferences.dart';
import '../widgets/glass_card.dart';

/// Central Dark Store hub constants (single source of truth — matches backend config).
/// Verified from https://maps.app.goo.gl/5fc6a8ZMgjfttUiB9
const double _kHubLatitude = 17.495101;
const double _kHubLongitude = 78.367535;
const double _kMaxDeliveryRadiusKm = 10.0;

class LocationPickerSheet extends StatefulWidget {
  final LocationModel currentLocation;
  final Function(LocationModel selectedLocation) onSelectLocation;
  final String? userId;

  const LocationPickerSheet({
    super.key,
    required this.currentLocation,
    required this.onSelectLocation,
    this.userId,
  });

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<LocationModel> _locations = [];
  List<SavedAddressModel> _savedAddresses = [];
  List<LocationModel> _nearbyLocations = [];
  bool _isLoading = true;
  bool _isDetectingGps = false;

  // Map state
  GoogleMapController? _mapController;
  CameraPosition _cameraPosition = const CameraPosition(
    target: LatLng(_kHubLatitude, _kHubLongitude),
    zoom: 12.0,
  );
  // Detected GPS location (shown as a separate marker + banner if out of radius)
  LocationModel? _detectedLocation;

  @override
  void initState() {
    super.initState();
    _loadSavedAddressesAndFetch();
  }


  double get _refLat {
    if (_detectedLocation != null && _detectedLocation!.latitude != 0.0) {
      return _detectedLocation!.latitude;
    }
    if (widget.currentLocation.latitude != 0.0) {
      return widget.currentLocation.latitude;
    }
    return _kHubLatitude;
  }

  double get _refLng {
    if (_detectedLocation != null && _detectedLocation!.longitude != 0.0) {
      return _detectedLocation!.longitude;
    }
    if (widget.currentLocation.longitude != 0.0) {
      return widget.currentLocation.longitude;
    }
    return _kHubLongitude;
  }

  double _calcDistanceKm(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a));
  }

  void _sortNearbyLocations() {
    final rLat = _refLat;
    final rLng = _refLng;
    _nearbyLocations.sort((a, b) {
      final distA = _calcDistanceKm(rLat, rLng, a.latitude, a.longitude);
      final distB = _calcDistanceKm(rLat, rLng, b.latitude, b.longitude);
      return distA.compareTo(distB);
    });
  }

  Future<void> _loadSavedAddressesAndFetch() async {
    setState(() => _isLoading = true);
    final uid = widget.userId ?? Preferences.getString(Preferences.keyUserId);
    List<SavedAddressModel> addrs = [];
    if (uid.isNotEmpty) {
      addrs = await ApiService.getSavedAddresses(uid);
    }
    final nearby = await ApiService.getNearbyLocations(lat: _refLat, lng: _refLng);
    if (mounted) {
      setState(() {
        _savedAddresses = addrs;
        _nearbyLocations = nearby;
        _sortNearbyLocations();
        _isLoading = false;
      });
    }
  }

  void _fetchLocations([String query = ""]) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _locations = [];
        _isLoading = false;
      });
      return;
    }
    setState(() => _isLoading = true);
    final results = await ApiService.getLocations(query: q);
    final matchingNearby = _nearbyLocations.where((l) =>
      l.name.toLowerCase().contains(q) || l.address.toLowerCase().contains(q)
    ).toList();

    final combined = <LocationModel>[...matchingNearby];
    for (var r in results) {
      if (!combined.any((c) => c.name.toLowerCase() == r.name.toLowerCase() || c.id == r.id)) {
        combined.add(r);
      }
    }

    if (mounted) {
      setState(() {
        _locations = combined;
        _isLoading = false;
      });
    }
  }

  /// Detects the user's current GPS location and runs the authoritative 10 KM
  /// geofence check via the backend. If the location is outside the radius, the
  /// UI shows a red "Delivery Not Available" banner and refuses to accept the
  /// address for checkout. This is the core requirement: "if the location was
  /// detected means we need to show delivery not available".
  Future<void> _detectCurrentLocation() async {
    setState(() => _isDetectingGps = true);
    try {
      // 1. Ensure permissions (the geolocator plugin throws on denial).
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          _showGeofenceBanner(
            title: "Location services disabled",
            message: "Please enable GPS / location on your device to detect your address.",
            serviceable: false,
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          _showGeofenceBanner(
            title: "Location permission denied",
            message:
                "We need location permission to check if you're within our 10 KM delivery radius.",
            serviceable: false,
          );
        }
        return;
      }

      // 2. Get the device GPS fix.
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 12),
      );

      // 3. Authoritative geofence check through the backend.
      final res = await ApiService.reverseGeocode(position.latitude, position.longitude);

      final title = res["name"] ?? "Detected Location";
      String addr = (res["address"] ?? "").toString();
      if (addr.isEmpty || addr.startsWith("GPS (")) {
        addr = "$title, Hafeezpet, Hyderabad, Telangana 500049";
      }

      final detected = LocationModel(
        id: res["id"] ?? "gps_${position.latitude}_${position.longitude}",
        name: title,
        address: addr,
        latitude: (res["latitude"] ?? position.latitude).toDouble(),
        longitude: (res["longitude"] ?? position.longitude).toDouble(),
        landmark: res["landmark"] ?? "",
        distanceKm: (res["distance_km"] ?? 0.0).toDouble(),
        isServiceable: res["is_serviceable"] ?? false,
        etaMinutes: res["eta_minutes"] != null
            ? (res["eta_minutes"] as num).toInt()
            : (res["estimated_delivery_minutes"] as num?)?.toInt() ?? 0,
      );

      setState(() {
        _detectedLocation = detected;
        _sortNearbyLocations();
        _cameraPosition = CameraPosition(
          target: LatLng(detected.latitude, detected.longitude),
          zoom: 13.5,
        );
        _mapController
            ?.animateCamera(CameraUpdate.newCameraPosition(_cameraPosition));
      });

      if (!mounted) return;
      _showGeofenceBanner(
        title: "Location Detected!",
        message: "Detected location. ETA ~${detected.etaMinutes} mins.",
        serviceable: true,
      );
    } catch (e) {
      if (mounted) {
        String errStr = e.toString();
        String msg = "GPS detection failed: $e. Please pick a location manually.";
        if (errStr.contains("MissingPluginException")) {
          msg = "Location plugin initializing. Please reopen or reinstall the app to enable device GPS.";
        }
        _showGeofenceBanner(
          title: "Couldn't detect location",
          message: msg,
          serviceable: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isDetectingGps = false);
    }
  }

  void _showGeofenceBanner(
      {required String title,
      required String message,
      required bool serviceable}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
                serviceable
                    ? Icons.check_circle_rounded
                    : Icons.warning_rounded,
                color: Colors.white,
                size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(message,
                      style: const TextStyle(fontSize: 12, color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor:
            serviceable ? const Color(0xFF059669) : Colors.red.shade700,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddCustomAddressModal() {
    final flatCtrl = TextEditingController();
    final streetCtrl = TextEditingController();
    final landmarkCtrl = TextEditingController();

    bool isGpsDetecting = false;
    double? detectedLat;
    double? detectedLng;
    double? detectedDistKm;
    bool? detectedServiceable;
    int? detectedEta;
    String? statusMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Row(
            children: [
              Icon(Icons.add_location_alt_rounded, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Text(
                "Enter Delivery Address",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // GPS Auto-Fill Button inside the modal
                InkWell(
                  onTap: isGpsDetecting
                      ? null
                      : () async {
                          setModalState(() {
                            isGpsDetecting = true;
                            statusMessage = "Detecting device GPS coordinates...";
                          });

                          try {
                            bool serviceEnabled = false;
                            try {
                              serviceEnabled = await Geolocator.isLocationServiceEnabled();
                            } catch (err) {
                              setModalState(() {
                                isGpsDetecting = false;
                                statusMessage = "GPS service unavailable: $err";
                              });
                              return;
                            }

                            if (!serviceEnabled) {
                              setModalState(() {
                                isGpsDetecting = false;
                                statusMessage = "Please enable GPS/Location in device settings.";
                              });
                              return;
                            }

                            var perm = await Geolocator.checkPermission();
                            if (perm == LocationPermission.denied) {
                              perm = await Geolocator.requestPermission();
                            }
                            if (perm == LocationPermission.denied ||
                                perm == LocationPermission.deniedForever) {
                              setModalState(() {
                                isGpsDetecting = false;
                                statusMessage = "Location permission denied.";
                              });
                              return;
                            }

                            final pos = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high,
                              timeLimit: const Duration(seconds: 12),
                            );

                            final res = await ApiService.reverseGeocode(pos.latitude, pos.longitude);
                            final isSvc = res["is_serviceable"] ?? false;
                            final dist = (res["distance_km"] ?? 0.0).toDouble();
                            final eta = res["eta_minutes"] != null
                                ? (res["eta_minutes"] as num).toInt()
                                : (res["estimated_delivery_minutes"] as num?)?.toInt() ?? 10;

                            final addr = res["address"] ?? res["name"] ?? "";
                            final lm = res["landmark"] ?? "";

                            streetCtrl.text = addr;
                            if (lm.isNotEmpty) landmarkCtrl.text = lm;

                            setModalState(() {
                              isGpsDetecting = false;
                              detectedLat = (res["latitude"] ?? pos.latitude).toDouble();
                              detectedLng = (res["longitude"] ?? pos.longitude).toDouble();
                              detectedDistKm = dist;
                              detectedServiceable = isSvc;
                              detectedEta = eta;
                              statusMessage = isSvc
                                  ? "✅ In 10 KM delivery zone (${dist} KM from hub • ETA ~${eta} mins)"
                                  : "❌ Delivery Not Available: ${dist} KM from hub (Exceeds 10 KM limit)";
                            });
                          } catch (e) {
                            setModalState(() {
                              isGpsDetecting = false;
                              statusMessage = "GPS detection error: $e";
                            });
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF059669).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        if (isGpsDetecting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF059669)),
                          )
                        else
                          const Icon(Icons.my_location_rounded, color: Color(0xFF059669), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isGpsDetecting ? "Detecting location..." : "📍 Auto-Fill with Current Location (GPS)",
                            style: const TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (detectedServiceable ?? false) ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (detectedServiceable ?? false) ? const Color(0xFF10B981) : Colors.redAccent,
                      ),
                    ),
                    child: Text(
                      statusMessage!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: (detectedServiceable ?? false) ? const Color(0xFF047857) : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                TextField(
                  controller: flatCtrl,
                  style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: "House / Flat / Floor No.",
                    labelStyle: TextStyle(color: Colors.black54),
                    hintText: "e.g. Flat 402, Block A",
                    hintStyle: TextStyle(color: Colors.black38, fontSize: 12),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: streetCtrl,
                  style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: "Street / Area / Colony",
                    labelStyle: TextStyle(color: Colors.black54),
                    hintText: "e.g. Near Metro, Hyderabad",
                    hintStyle: TextStyle(color: Colors.black38, fontSize: 12),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: landmarkCtrl,
                  style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: "Landmark (Optional)",
                    labelStyle: TextStyle(color: Colors.black54),
                    hintText: "e.g. Opposite Park",
                    hintStyle: TextStyle(color: Colors.black38, fontSize: 12),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Fast citywide delivery from Flash Fresh Central Dark Store.",
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () async {
                final flat = flatCtrl.text.trim();
                final street = streetCtrl.text.trim();
                final landmark = landmarkCtrl.text.trim();

                if (flat.isEmpty || street.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter house number and street address")),
                  );
                  return;
                }

                if (detectedServiceable == false) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Delivery not available: Location is ${detectedDistKm ?? 0.0} KM from hub, which exceeds the 10 KM limit.",
                      ),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                  return;
                }

                double finalLat = detectedLat ?? _kHubLatitude;
                double finalLng = detectedLng ?? _kHubLongitude;
                double finalDist = detectedDistKm ?? 0.5;
                bool finalSvc = detectedServiceable ?? true;
                int finalEta = detectedEta ?? 10;

                if (detectedLat == null) {
                  final svc = await ApiService.checkServiceability(_kHubLatitude, _kHubLongitude);
                  finalLat = (svc["store_latitude"] ?? _kHubLatitude).toDouble();
                  finalLng = (svc["store_longitude"] ?? _kHubLongitude).toDouble();
                  finalDist = (svc["distance_km"] ?? 0.5).toDouble();
                  finalSvc = svc["is_serviceable"] ?? true;
                  finalEta = (svc["estimated_delivery_minutes"] as num?)?.toInt() ?? 10;
                }

                if (!finalSvc) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Delivery not available outside our 10 KM delivery radius."),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(ctx);

                final newLoc = LocationModel(
                  id: "custom_${DateTime.now().millisecondsSinceEpoch}",
                  name: "Home: $flat",
                  address: landmark.isNotEmpty ? "$street (Near $landmark)" : street,
                  latitude: finalLat,
                  longitude: finalLng,
                  landmark: landmark,
                  distanceKm: finalDist,
                  isServiceable: finalSvc,
                  etaMinutes: finalEta,
                );

                // Save to user's saved addresses in backend
                final uid = widget.userId ?? Preferences.getString(Preferences.keyUserId);
                if (uid.isNotEmpty) {
                  await ApiService.addSavedAddress(
                    userId: uid,
                    label: "Home",
                    houseNumber: flat,
                    streetAddress: street,
                    landmark: landmark,
                    latitude: finalLat,
                    longitude: finalLng,
                  );
                }

                await Preferences.setString(Preferences.keyActiveLocId, newLoc.id);
                await Preferences.setString(Preferences.keyActiveLocName, newLoc.name);
                await Preferences.setString(Preferences.keyActiveLocAddress, newLoc.address);
                await Preferences.setDouble(Preferences.keyActiveLocLat, newLoc.latitude);
                await Preferences.setDouble(Preferences.keyActiveLocLng, newLoc.longitude);
                await Preferences.setDouble(Preferences.keyActiveLocDist, newLoc.distanceKm);
                await Preferences.setBoolean(Preferences.keyActiveLocServiceable, newLoc.isServiceable);
                await Preferences.setInt(Preferences.keyActiveLocEta, newLoc.etaMinutes);

                setState(() {
                  _detectedLocation = newLoc;
                  _cameraPosition = CameraPosition(
                    target: LatLng(newLoc.latitude, newLoc.longitude),
                    zoom: 14.0,
                  );
                  _mapController?.animateCamera(
                    CameraUpdate.newCameraPosition(_cameraPosition),
                  );
                });

                widget.onSelectLocation(newLoc);
                Navigator.pop(context);
              },
              child: const Text(
                "Save & Use Address",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Set<Circle> get _mapCircles {
    final Set<Circle> circles = {};
    // 10 KM delivery radius from the hub.
    circles.add(Circle(
      circleId: const CircleId("delivery_radius"),
      center: const LatLng(_kHubLatitude, _kHubLongitude),
      radius: _kMaxDeliveryRadiusKm * 1000, // meters
      strokeColor: const Color(0xFF059669),
      strokeWidth: 2,
      fillColor: const Color(0x22059969),
    ));
    return circles;
  }

  Set<Marker> get _mapMarkers {
    final Set<Marker> markers = {};
    // Hub marker
    markers.add(Marker(
      markerId: const MarkerId("hub"),
      position: const LatLng(_kHubLatitude, _kHubLongitude),
      infoWindow: const InfoWindow(
        title: "Flash Fresh Central Dark Store Hub",
        snippet: "Metro Pillar 84",
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    ));
    // Detected GPS location marker
    if (_detectedLocation != null) {
      final inZone = _detectedLocation!.isServiceable;
      markers.add(Marker(
        markerId: const MarkerId("detected"),
        position:
            LatLng(_detectedLocation!.latitude, _detectedLocation!.longitude),
        infoWindow: InfoWindow(
          title: inZone ? "In delivery zone" : "Outside delivery zone",
          snippet: "${_detectedLocation!.distanceKm} KM from hub",
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          inZone ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed,
        ),
      ));
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final detectedBlocked =
        _detectedLocation != null && !_detectedLocation!.isServiceable;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.grey.shade300, width: 1.2),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 14),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF059669).withOpacity(0.12),
                      ),
                      child: const Icon(Icons.location_on_rounded,
                          color: Color(0xFF059669), size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Choose Delivery Pin",
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF111827)),
                          ),
                          Text(
                            "Select delivery address",
                            style:
                                TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.black54),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.black12, height: 20),

              // Google Map showing the hub marker + 10 KM radius circle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 200,
                    child: GoogleMap(
                      initialCameraPosition: _cameraPosition,
                      onMapCreated: (controller) {
                        _mapController = controller;
                      },
                      onCameraMove: (pos) {
                        _cameraPosition = pos;
                      },
                      markers: _mapMarkers,
                      circles: _mapCircles,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      compassEnabled: false,
                      liteModeEnabled: false,
                    ),
                  ),
                ),
              ),

              // GPS detection banner (red if outside radius, green if inside)
              if (_detectedLocation != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: GlassCard(
                    blur: 16,
                    opacity: 0.9,
                    borderRadius: 14,
                    borderColor: _detectedLocation!.isServiceable
                        ? const Color(0xFF059669)
                        : Colors.redAccent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          _detectedLocation!.isServiceable
                              ? Icons.check_circle_rounded
                              : Icons.block_rounded,
                          color: _detectedLocation!.isServiceable
                              ? const Color(0xFF059669)
                              : Colors.redAccent,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _detectedLocation!.isServiceable
                                    ? "Delivery Available"
                                    : "Delivery Not Available",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _detectedLocation!.isServiceable
                                      ? const Color(0xFF059669)
                                      : Colors.redAccent,
                                ),
                              ),
                              Text(
                                "${_detectedLocation!.name} • ${_detectedLocation!.distanceKm} KM from hub"
                                "${_detectedLocation!.isServiceable ? ' • ETA ~${_detectedLocation!.etaMinutes} mins' : ' • exceeds 10 KM limit'}",
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        if (_detectedLocation!.isServiceable)
                          TextButton(
                            onPressed: () {
                              widget.onSelectLocation(_detectedLocation!);
                              Navigator.pop(context);
                            },
                            child: const Text(
                              "Use",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF059669)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              // GPS Detect button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: GlassCard(
                  blur: 16,
                  opacity: 0.9,
                  borderRadius: 16,
                  borderColor: const Color(0xFF059669).withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  onTap: _isDetectingGps ? null : _detectCurrentLocation,
                  child: Row(
                    children: [
                      if (_isDetectingGps)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF059669)),
                        )
                      else
                        const Icon(Icons.my_location_rounded,
                            color: Color(0xFF059669), size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _isDetectingGps
                            ? "Detecting your location..."
                            : "📍 Detect Current Location (GPS)",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF059669)),
                      ),
                    ],
                  ),
                ),
              ),

              // Search Field
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20.0, vertical: 4.0),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: TextField(
                    controller: _searchController,
                    style:
                        const TextStyle(color: Color(0xFF111827), fontSize: 13),
                    onChanged: (val) => _fetchLocations(val),
                    decoration: InputDecoration(
                      hintText: "Search landmark, area, colony...",
                      hintStyle:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF059669), size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  color: Colors.black54, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _fetchLocations();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Add Custom Address Tile
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: GlassCard(
                  blur: 16,
                  opacity: 0.9,
                  borderRadius: 14,
                  borderColor: const Color(0xFF059669).withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  onTap: _showAddCustomAddressModal,
                  child: const Row(
                    children: [
                      Icon(Icons.add_location_alt_rounded,
                          color: Color(0xFF059669), size: 20),
                      SizedBox(width: 10),
                      Text(
                        "➕ Add Your House / Flat Address",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFF059669)),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Multi-section Location Selector:
              // 1. Current Location (GPS)
              // 2. Saved Addresses
              // 3. Nearby Locations (10 KM Zone)
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: Color(0xFF059669)))
                    : _searchController.text.trim().isNotEmpty
                        ? _locations.isEmpty
                            ? Center(
                                child: Text(
                                  "No matching delivery locations found.",
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 4),
                                itemCount: _locations.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final loc = _locations[index];
                                  final isSelected =
                                      loc.id == widget.currentLocation.id;
                                  return _buildLocationCard(loc, isSelected);
                                },
                              )
                        : ListView(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 4),
                            children: [
                              // 1. CURRENT LOCATION SECTION
                              _buildSectionHeader("📍 CURRENT LOCATION"),
                              const SizedBox(height: 6),
                              _buildCurrentLocationTile(),
                              const SizedBox(height: 16),

                              // 2. SAVED ADDRESSES SECTION
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildSectionHeader("📌 SAVED ADDRESSES"),
                                  InkWell(
                                    onTap: _showAddCustomAddressModal,
                                    child: const Text(
                                      "+ Add New",
                                      style: TextStyle(
                                        color: Color(0xFF059669),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (_savedAddresses.isEmpty)
                                GlassCard(
                                  blur: 16,
                                  opacity: 0.9,
                                  borderRadius: 16,
                                  borderColor: Colors.grey.shade200,
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Icon(Icons.location_off_outlined,
                                          color: Colors.grey.shade400,
                                          size: 24),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          "No saved addresses yet. Tap '+ Add New' to save your house or flat address.",
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ..._savedAddresses.map((addr) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8.0),
                                      child: _buildSavedAddressCard(addr),
                                    )),
                              const SizedBox(height: 16),

                              // 3. NEARBY LOCATIONS (10 KM ZONE) SECTION
                              _buildSectionHeader(
                                  "📍 NEARBY LOCATIONS (NEAR YOU)"),
                              const SizedBox(height: 2),
                              Text(
                                "Spots closest to your current location within 10 KM delivery zone",
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 8),
                              ..._nearbyLocations.map((loc) {
                                final isSelected =
                                    loc.id == widget.currentLocation.id ||
                                        widget.currentLocation.name == loc.name;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _buildLocationCard(loc, isSelected),
                                );
                              }),
                              const SizedBox(height: 16),
                            ],
                          ),
              ),

              // Bottom block button when GPS detected an out-of-zone location
              if (detectedBlocked)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.redAccent, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Checkout is blocked — your detected location is outside the 10 KM delivery radius. Move closer to the Miyapur hub or pick another address.",
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
        color: Colors.black54,
      ),
    );
  }

  Widget _buildCurrentLocationTile() {
    if (_detectedLocation != null) {
      final isSvc = _detectedLocation!.isServiceable;
      return GlassCard(
        blur: 16,
        opacity: 0.9,
        borderRadius: 18,
        borderColor: isSvc ? const Color(0xFF059669) : Colors.redAccent,
        onTap: () {
          if (!isSvc) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Delivery not available: ${_detectedLocation!.distanceKm} KM from hub (outside 10 KM limit).",
                ),
                backgroundColor: Colors.red.shade700,
              ),
            );
            return;
          }
          widget.onSelectLocation(_detectedLocation!);
          Navigator.pop(context);
        },
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: isSvc
                  ? const Color(0xFF059669).withOpacity(0.12)
                  : Colors.red.withOpacity(0.12),
              child: Icon(
                isSvc ? Icons.my_location_rounded : Icons.block_rounded,
                color: isSvc ? const Color(0xFF059669) : Colors.redAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _detectedLocation!.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _detectedLocation!.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSvc
                        ? "⚡ ~${_detectedLocation!.etaMinutes} mins (${_detectedLocation!.distanceKm} km from hub)"
                        : "❌ Outside 10 KM delivery limit (${_detectedLocation!.distanceKm} km)",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSvc ? const Color(0xFF059669) : Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
            if (isSvc)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "USE",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return GlassCard(
      blur: 16,
      opacity: 0.9,
      borderRadius: 18,
      borderColor: const Color(0xFF059669).withOpacity(0.4),
      onTap: _isDetectingGps ? null : _detectCurrentLocation,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF059669).withOpacity(0.12),
            child: _isDetectingGps
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF059669),
                    ),
                  )
                : const Icon(Icons.my_location_rounded,
                    color: Color(0xFF059669), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isDetectingGps
                      ? "Detecting live GPS location..."
                      : "Use Current Location (GPS)",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Tap to auto-detect and verify 10 KM delivery boundary",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded,
              color: Color(0xFF059669), size: 14),
        ],
      ),
    );
  }

  Widget _buildSavedAddressCard(SavedAddressModel addr) {
    final isSelected =
        widget.currentLocation.address.contains(addr.streetAddress) ||
            widget.currentLocation.name.contains(addr.houseNumber);

    return GlassCard(
      blur: 16,
      opacity: 0.9,
      borderRadius: 18,
      borderColor: isSelected ? const Color(0xFF059669) : Colors.grey.shade200,
      onTap: () {
        if (!addr.isServiceable) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Delivery not available: Address is ${addr.distanceKm} KM from Miyapur hub (exceeds 10 KM limit).",
              ),
              backgroundColor: Colors.red.shade700,
            ),
          );
          return;
        }
        final loc = LocationModel(
          id: addr.id,
          name: "${addr.label}: ${addr.houseNumber}",
          address: addr.landmark.isNotEmpty
              ? "${addr.streetAddress} (Near ${addr.landmark})"
              : addr.streetAddress,
          latitude: addr.latitude,
          longitude: addr.longitude,
          landmark: addr.landmark,
          distanceKm: addr.distanceKm,
          isServiceable: addr.isServiceable,
          etaMinutes: 10,
        );
        widget.onSelectLocation(loc);
        Navigator.pop(context);
      },
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: addr.isServiceable
                ? const Color(0xFF059669).withOpacity(0.12)
                : Colors.red.withOpacity(0.12),
            child: Icon(
              addr.label.toLowerCase() == "work"
                  ? Icons.business_rounded
                  : Icons.home_rounded,
              color: addr.isServiceable
                  ? const Color(0xFF059669)
                  : Colors.redAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${addr.label}: ${addr.houseNumber}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  addr.landmark.isNotEmpty
                      ? "${addr.streetAddress} • Near ${addr.landmark}"
                      : addr.streetAddress,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  addr.isServiceable
                      ? "⚡ ~10 mins (${addr.distanceKm} km from hub)"
                      : "❌ Out of 10 KM limit (${addr.distanceKm} km)",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: addr.isServiceable
                        ? const Color(0xFF059669)
                        : Colors.redAccent,
                  ),
                ),
              ],
            ),
          ),
          if (isSelected)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669)),
        ],
      ),
    );
  }

  Widget _buildLocationCard(LocationModel loc, bool isSelected) {
    return GlassCard(
      blur: 16,
      opacity: 0.9,
      borderRadius: 18,
      borderColor: isSelected ? const Color(0xFF059669) : Colors.grey.shade200,
      onTap: () async {
        LocationModel resolved = loc;
        if (loc.latitude == 0.0 || loc.longitude == 0.0) {
          final geo = await ApiService.geocodePlace(loc.id);
          if (geo != null) {
            resolved = LocationModel(
              id: geo["id"] ?? loc.id,
              name: geo["name"] ?? loc.name,
              address: geo["address"] ?? loc.address,
              latitude: (geo["latitude"] as num).toDouble(),
              longitude: (geo["longitude"] as num).toDouble(),
              landmark: loc.landmark,
              distanceKm: (geo["distance_km"] ?? 0.0).toDouble(),
              isServiceable: geo["is_serviceable"] ?? false,
              etaMinutes: (geo["eta_minutes"] as num?)?.toInt() ?? 12,
            );
          }
        }

        if (!resolved.isServiceable) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  resolved.distanceKm > 0
                      ? "Delivery not available: ${resolved.distanceKm} KM from hub (outside 10 KM limit)."
                      : "Location outside 10 KM delivery radius from Miyapur Central Hub.",
                ),
                backgroundColor: Colors.red.shade700,
              ),
            );
          }
          return;
        }

        setState(() {
          _cameraPosition = CameraPosition(
            target: LatLng(resolved.latitude, resolved.longitude),
            zoom: 14.0,
          );
          _mapController?.animateCamera(
            CameraUpdate.newCameraPosition(_cameraPosition),
          );
        });

        widget.onSelectLocation(resolved);
        if (mounted) Navigator.pop(context);
      },
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: loc.isServiceable
                ? const Color(0xFF059669).withOpacity(0.12)
                : Colors.red.withOpacity(0.12),
            child: Icon(
              loc.isServiceable ? Icons.place_rounded : Icons.block_rounded,
              color:
                  loc.isServiceable ? const Color(0xFF059669) : Colors.redAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loc.address,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Builder(builder: (context) {
                  final distUser = _calcDistanceKm(_refLat, _refLng, loc.latitude, loc.longitude);
                  final distText = distUser < 1.0
                      ? "${(distUser * 1000).round()} m away"
                      : "${distUser.toStringAsFixed(1)} km away";
                  return Text(
                    loc.isServiceable
                        ? "📍 $distText from you • ⚡ ~${loc.etaMinutes} mins"
                        : "❌ Out of 10 KM limit",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: loc.isServiceable
                          ? const Color(0xFF059669)
                          : Colors.redAccent,
                    ),
                  );
                }),
              ],
            ),
          ),
          if (isSelected)
            const Icon(Icons.check_circle_rounded, color: Color(0xFF059669)),
        ],
      ),
    );
  }
}
