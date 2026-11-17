import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/bike_marker_icon.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';

/// Flash Fresh Central Dark Store Hub (exact Google Maps pin).
/// Verified from https://maps.app.goo.gl/5fc6a8ZMgjfttUiB9
const double _kHubLatitude = 17.495101;
const double _kHubLongitude = 78.367535;

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String orderNumber;
  final double grandTotal;
  final int etaMinutes;
  final String deliveryAddress;
  final List<CartItemModel> items;

  /// Destination coordinates for the live map. If not supplied, coordinates are
  /// resolved from the delivery address or tracking API.
  final double? destinationLatitude;
  final double? destinationLongitude;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.orderNumber,
    required this.grandTotal,
    required this.etaMinutes,
    required this.deliveryAddress,
    required this.items,
    this.destinationLatitude,
    this.destinationLongitude,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen>
    with TickerProviderStateMixin {
  // --- Animation controllers ---
  late final AnimationController _pulseController;
  late final AnimationController _bikeController;
  late final AnimationController _radarController;
  late final Animation<double> _bikeAnimation;
  late final Animation<double> _radarAnimation;

  GoogleMapController? _mapController;

  // 0.0 = at hub, 1.0 = at destination.
  double _bikeProgress = 0.0;
  double _targetProgress = 0.20;

  final LatLng _hub = const LatLng(_kHubLatitude, _kHubLongitude);
  late LatLng _destination;

  // Road route points (densified curved road path from Hub to Destination)
  List<LatLng> _routePoints = [];

  Marker? _bikeMarker;
  BitmapDescriptor? _bikeIcon;
  BitmapDescriptor? _hubIcon;
  BitmapDescriptor? _destIcon;

  Timer? _pollingTimer;
  String _currentStatus = "PLACED";
  String _deliveryOtp = "4921";
  int _etaMins = 12;
  Map<String, dynamic>? _riderInfo;
  bool _followRider = false;

  // Real-time WebSocket connection to backend
  WebSocket? _webSocket;
  StreamSubscription? _wsSubscription;
  double? _liveRiderLat;
  double? _liveRiderLng;

  @override
  void initState() {
    super.initState();
    _etaMins = widget.etaMinutes > 0 ? widget.etaMinutes : 12;

    _destination = _resolveInitialDestination();
    _routePoints = _generateRoadRoute(_hub, _destination);

    // Subtle header pulse
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Live GPS radar ripple around the bike (Zomato-style)
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _radarAnimation =
        CurvedAnimation(parent: _radarController, curve: Curves.easeOutQuad)
          ..addListener(() {
            if (mounted) setState(() {});
          });

    // Bike travel animation along the road curve
    _bikeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    );
    _bikeAnimation =
        CurvedAnimation(parent: _bikeController, curve: Curves.easeInOutCubic)
          ..addListener(() {
            setState(() {
              _bikeProgress = _bikeAnimation.value * _targetProgress;
            });
            _syncBikePositionMarker();
            if (_followRider && _mapController != null) {
              final pos = _getCurrentBikePosition();
              _mapController!.animateCamera(CameraUpdate.newLatLng(pos));
            }
          });

    _targetProgress = _targetProgressForStatus(_currentStatus);
    _bikeController.value = 1.0; // initial jump

    _loadCustomMarkers();
    _fetchStreetSnappedRoute();
    _fetchTrackingData();
    _connectLiveWebSocket();

    _pollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _fetchTrackingData();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bikeController.dispose();
    _radarController.dispose();
    _pollingTimer?.cancel();
    _wsSubscription?.cancel();
    try {
      _webSocket?.close();
    } catch (_) {}
    super.dispose();
  }

  /// Establishes bidirectional WebSocket to listen for live GPS location updates & status events.
  void _connectLiveWebSocket() async {
    try {
      final wsUrl = ApiService.baseUrl
          .replaceFirst("http://", "ws://")
          .replaceFirst("https://", "wss://");
      _webSocket = await WebSocket.connect("$wsUrl/orders/ws/${widget.orderId}")
          .timeout(const Duration(seconds: 4));

      _wsSubscription = _webSocket?.listen(
        (data) {
          try {
            final json = jsonDecode(data as String);
            final event = json["event"];
            if (event == "LOCATION_UPDATE") {
              final lat = (json["rider_lat"] as num?)?.toDouble();
              final lng = (json["rider_lng"] as num?)?.toDouble();
              if (lat != null && lng != null && mounted) {
                _onRiderGpsReceived(lat, lng);
              }
            } else if (event == "STATUS_UPDATE") {
              final newStatus = json["status"]?.toString();
              if (newStatus != null && mounted) {
                setState(() {
                  _currentStatus = newStatus;
                  _targetProgress = _targetProgressForStatus(newStatus);
                });
                final from = (_bikeProgress / _targetProgress.clamp(0.001, 1.0))
                    .clamp(0.0, 1.0);
                _bikeController.forward(from: from);
                _refreshBikeIcon();
              }
            }
          } catch (_) {}
        },
        onError: (_) {},
        onDone: () {},
      );
    } catch (_) {
      // Periodic HTTP polling acts as guaranteed failover
    }
  }

  void _onRiderGpsReceived(double lat, double lng) {
    setState(() {
      _liveRiderLat = lat;
      _liveRiderLng = lng;
    });
    _syncBikePositionMarker();
    if (_followRider && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
    }
  }

  /// Fetches real road waypoints snapped to Miyapur streets from Google Directions API / road network.
  Future<void> _fetchStreetSnappedRoute() async {
    try {
      final res = await ApiService.getDirectionsRoute(
        originLat: _hub.latitude,
        originLng: _hub.longitude,
        destLat: _destination.latitude,
        destLng: _destination.longitude,
      );
      if (res["success"] == true && res["points"] is List) {
        final rawPts = res["points"] as List;
        final List<LatLng> snapped = [];
        for (final p in rawPts) {
          final lat = (p["latitude"] as num?)?.toDouble();
          final lng = (p["longitude"] as num?)?.toDouble();
          if (lat != null && lng != null) {
            snapped.add(LatLng(lat, lng));
          }
        }
        if (snapped.length >= 2 && mounted) {
          setState(() {
            _routePoints = snapped;
          });
          _syncBikePositionMarker();
          _fitBounds();
        }
      }
    } catch (_) {}
  }

  /// Resolves destination coordinates from widget parameters or addresses, ensuring
  /// destination is never identical to the Miyapur Dark Store Hub.
  LatLng _resolveInitialDestination() {
    if (widget.destinationLatitude != null &&
        widget.destinationLatitude != 0.0 &&
        (widget.destinationLatitude != _kHubLatitude ||
            widget.destinationLongitude != _kHubLongitude)) {
      return LatLng(
        widget.destinationLatitude!,
        widget.destinationLongitude ?? _kHubLongitude,
      );
    }

    final addr = widget.deliveryAddress.toLowerCase();
    if (addr.contains("allwyn")) return const LatLng(17.4985, 78.3720);
    if (addr.contains("madinaguda") || addr.contains("gsm")) {
      return const LatLng(17.4920, 78.3520);
    }
    if (addr.contains("metro") || addr.contains("pillar")) {
      return const LatLng(17.4968, 78.3614);
    }
    if (addr.contains("hafeezpet")) return const LatLng(17.4812, 78.3651);
    if (addr.contains("chandanagar")) return const LatLng(17.4895, 78.3390);
    if (addr.contains("nizampet")) return const LatLng(17.5180, 78.3820);
    if (addr.contains("kphb") || addr.contains("jntu")) {
      return const LatLng(17.4980, 78.3910);
    }
    if (addr.contains("bachupally")) return const LatLng(17.5350, 78.3650);
    if (addr.contains("kondapur")) return const LatLng(17.4580, 78.3650);

    // Realistic delivery drop-off coordinate ~2.2 km from hub
    return const LatLng(17.5028, 78.3582);
  }

  /// Generates a realistic curved road path simulating actual Hyderabad street
  /// turns rather than a straight diagonal through buildings.
  List<LatLng> _generateRoadRoute(LatLng start, LatLng end) {
    final double midLat = (start.latitude + end.latitude) / 2;
    final double midLng = (start.longitude + end.longitude) / 2;

    // Perpendicular road deviation offset
    final double dLat = end.latitude - start.latitude;
    final double dLng = end.longitude - start.longitude;
    final double perpLat = -dLng * 0.20;
    final double perpLng = dLat * 0.20;

    // Intermediate street corridor waypoints
    final wp1 = LatLng(
      start.latitude * 0.70 + midLat * 0.30 + perpLat * 0.6,
      start.longitude * 0.70 + midLng * 0.30 + perpLng * 0.6,
    );
    final wp2 = LatLng(midLat + perpLat, midLng + perpLng);
    final wp3 = LatLng(
      midLat * 0.30 + end.latitude * 0.70 - perpLat * 0.4,
      midLng * 0.30 + end.longitude * 0.70 - perpLng * 0.4,
    );

    final points = <LatLng>[];
    const int totalSteps = 60;
    for (int i = 0; i <= totalSteps; i++) {
      final t = i / totalSteps.toDouble();
      points.add(_bezierPoint([start, wp1, wp2, wp3, end], t));
    }
    return points;
  }

  LatLng _bezierPoint(List<LatLng> pts, double t) {
    if (pts.length == 1) return pts.first;
    final nextPts = <LatLng>[];
    for (int i = 0; i < pts.length - 1; i++) {
      final lat = pts[i].latitude + (pts[i + 1].latitude - pts[i].latitude) * t;
      final lng =
          pts[i].longitude + (pts[i + 1].longitude - pts[i].longitude) * t;
      nextPts.add(LatLng(lat, lng));
    }
    return _bezierPoint(nextPts, t);
  }

  Future<void> _loadCustomMarkers() async {
    _hubIcon = await BikeMarkerIcon.createStoreHubMarker();
    _destIcon = await BikeMarkerIcon.createCustomerHomeMarker(
      label: _getShortAddressLabel(),
    );
    _bikeIcon = await BikeMarkerIcon.createZomatoBikeMarker(
      etaMins: _etaMins,
      headingDeg: _getCurrentBearing(),
      riderName: _riderInfo?["name"] ?? "Ravi",
    );
    if (mounted) {
      _syncBikePositionMarker();
    }
  }

  String _getShortAddressLabel() {
    final raw = widget.deliveryAddress;
    if (raw.isEmpty) return "Your Doorstep";
    final parts = raw.split(",");
    if (parts.isNotEmpty) return parts.first.trim();
    return "Your Doorstep";
  }

  double _targetProgressForStatus(String status) {
    switch (status) {
      case "PLACED":
        return 0.10;
      case "PACKED":
        return 0.30;
      case "OUT_FOR_DELIVERY":
        return 0.82;
      case "DELIVERED":
        return 1.0;
      default:
        return 0.10;
    }
  }

  Future<void> _fetchTrackingData() async {
    final data = await ApiService.getOrderTracking(widget.orderId);
    if (!mounted) return;

    final newStatus = data["status"] ?? _currentStatus;
    final newEta = data["delivery_eta_mins"] ?? _etaMins;
    final newOtp = data["delivery_otp"] ?? _deliveryOtp;
    final newRider = data["rider"];

    // Update destination if backend returned customer_coordinates
    if (data["customer_coordinates"] != null) {
      final cLat = (data["customer_coordinates"]["lat"] as num?)?.toDouble();
      final cLng = (data["customer_coordinates"]["lng"] as num?)?.toDouble();
      if (cLat != null &&
          cLng != null &&
          (cLat != _kHubLatitude || cLng != _kHubLongitude)) {
        final newDest = LatLng(cLat, cLng);
        if ((newDest.latitude - _destination.latitude).abs() > 0.0001 ||
            (newDest.longitude - _destination.longitude).abs() > 0.0001) {
          _destination = newDest;
          _fetchStreetSnappedRoute();
        }
      }
    }

    // Update live rider coordinates from polling if not yet connected via WS
    if (newRider != null &&
        newRider["current_lat"] != null &&
        newRider["current_lng"] != null) {
      final rLat = (newRider["current_lat"] as num).toDouble();
      final rLng = (newRider["current_lng"] as num).toDouble();
      if (rLat != _kHubLatitude || rLng != _kHubLongitude) {
        _liveRiderLat = rLat;
        _liveRiderLng = rLng;
      }
    }

    setState(() {
      _currentStatus = newStatus;
      _deliveryOtp = newOtp;
      _etaMins = newEta;
      _riderInfo = newRider;
    });

    final next = _targetProgressForStatus(newStatus);
    if ((next - _targetProgress).abs() > 0.001) {
      _targetProgress = next;
      final from = (_bikeProgress / _targetProgress.clamp(0.0001, 1.0)).clamp(
        0.0,
        1.0,
      );
      _bikeController.forward(from: from);
    }

    _syncBikePositionMarker();
    _refreshBikeIcon();
    _fitBounds();
  }

  LatLng _getCurrentBikePosition() {
    if (_liveRiderLat != null && _liveRiderLng != null) {
      return LatLng(_liveRiderLat!, _liveRiderLng!);
    }
    if (_routePoints.isEmpty) return _hub;
    final double rawIndex = _bikeProgress * (_routePoints.length - 1);
    final int idx = rawIndex.clamp(0, _routePoints.length - 1).toInt();
    if (idx >= _routePoints.length - 1) return _routePoints.last;

    final fraction = rawIndex - idx;
    final p1 = _routePoints[idx];
    final p2 = _routePoints[idx + 1];
    return LatLng(
      p1.latitude + (p2.latitude - p1.latitude) * fraction,
      p1.longitude + (p2.longitude - p1.longitude) * fraction,
    );
  }

  double _getCurrentBearing() {
    if (_routePoints.isEmpty) return 0.0;
    final double rawIndex = _bikeProgress * (_routePoints.length - 1);
    final int idx = rawIndex.clamp(0, _routePoints.length - 2).toInt();
    final p1 = _routePoints[idx];
    final p2 = _routePoints[idx + 1];

    final dLat = p2.latitude - p1.latitude;
    final dLng = p2.longitude - p1.longitude;
    final angle = (math.atan2(dLng, dLat) * 180.0 / math.pi);
    return angle;
  }

  void _syncBikePositionMarker() {
    final pos = _getCurrentBikePosition();
    if (!mounted) return;
    setState(() {
      _bikeMarker = Marker(
        markerId: const MarkerId("bike"),
        position: pos,
        flat: true,
        anchor: const Offset(0.5, 0.65), // Centers scooter disc on the road
        icon:
            _bikeIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: "⚡ ${_riderInfo?["name"] ?? "Ravi Kumar"} (Hero Electric)",
          snippet: "Arriving in ~$_etaMins mins",
        ),
      );
    });
  }

  Future<void> _refreshBikeIcon() async {
    final bearing = _getCurrentBearing();
    final newIcon = await BikeMarkerIcon.createZomatoBikeMarker(
      etaMins: _etaMins,
      headingDeg: bearing,
      riderName: _riderInfo?["name"] ?? "Ravi",
    );
    if (!mounted) return;
    setState(() {
      _bikeIcon = newIcon;
      _syncBikePositionMarker();
    });
  }

  void _fitBounds() {
    if (_mapController == null || _followRider) return;
    final bounds = LatLngBounds(
      southwest: LatLng(
        math.min(_hub.latitude, _destination.latitude) - 0.003,
        math.min(_hub.longitude, _destination.longitude) - 0.003,
      ),
      northeast: LatLng(
        math.max(_hub.latitude, _destination.latitude) + 0.003,
        math.max(_hub.longitude, _destination.longitude) + 0.003,
      ),
    );
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            "Live Order Tracking",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(
                Icons.help_outline_rounded,
                color: Colors.black87,
              ),
              onPressed: _showSupportSheet,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildEtaHeroCard(),
              const SizedBox(height: 14),
              _buildDeliveryOtpBox(),
              const SizedBox(height: 14),
              _buildZomatoLiveMapCard(),
              const SizedBox(height: 14),
              _buildRiderCard(),
              const SizedBox(height: 14),
              _buildTimelineCard(),
              const SizedBox(height: 14),
              _buildOrderReceiptCard(),
              const SizedBox(height: 24),

              if (_currentStatus == "DELIVERED") ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _showRatingDialog,
                    icon: const Icon(Icons.star_rounded, color: Colors.amber),
                    label: const Text(
                      "Rate Freshness & Delivery",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (_currentStatus == "PLACED" || _currentStatus == "PACKED") ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _showCancelConfirmation,
                    icon: const Icon(
                      Icons.cancel_outlined,
                      color: Colors.redAccent,
                    ),
                    label: const Text(
                      "Cancel Order & Get Refund",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              LiquidButton(
                label: "Continue Shopping",
                icon: Icons.storefront_rounded,
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEtaHeroCard() {
    String statusTitle = "Preparing Order";
    String statusSubtitle = "Central Dark Store Hub • Metro Pillar 84";
    IconData statusIcon = Icons.flash_on_rounded;

    if (_currentStatus == "PACKED") {
      statusTitle = "Packed & Ready for Pickup";
      statusSubtitle = "Rider arriving at hub in 1 min";
      statusIcon = Icons.inventory_2_rounded;
    } else if (_currentStatus == "OUT_FOR_DELIVERY") {
      statusTitle = "On the Way to Your Doorstep";
      statusSubtitle = "Rider navigating via Central Main Road";
      statusIcon = Icons.two_wheeler_rounded;
    } else if (_currentStatus == "DELIVERED") {
      statusTitle = "Delivered Successfully! 🎉";
      statusSubtitle = "Thank you for shopping with Flash Fresh Quick Commerce";
      statusIcon = Icons.check_circle_rounded;
    }

    return GlassCard(
      blur: 24,
      opacity: 0.9,
      borderRadius: 24,
      borderColor: Colors.grey.shade200,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: Tween<double>(
                  begin: 0.9,
                  end: 1.1,
                ).animate(_pulseController),
                child: Icon(
                  statusIcon,
                  color: const Color(0xFF059669),
                  size: 30,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _currentStatus == "DELIVERED"
                    ? "Delivered"
                    : "Arriving in $_etaMins mins",
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            statusTitle,
            style: const TextStyle(
              color: Color(0xFF059669),
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            statusSubtitle,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "Order #${widget.orderNumber}",
              style: const TextStyle(
                color: Color(0xFF059669),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryOtpBox() {
    return GlassCard(
      blur: 20,
      opacity: 0.9,
      borderRadius: 22,
      borderColor: const Color(0xFF059669).withOpacity(0.4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF059669).withOpacity(0.12),
            ),
            child: const Icon(
              Icons.lock_clock_rounded,
              color: Color(0xFF059669),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Delivery Verification PIN",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Share this 4-digit PIN with rider at doorstep",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF059669),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _deliveryOtp,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Zomato/Zepto-style Redesigned Live Map with:
  /// - High-fidelity Store Hub Pin
  /// - High-fidelity Delivery Destination Pin
  /// - Animated Bike marker with floating ETA pill and heading angle
  /// - Pulsing radar ripple ring around the rider
  /// - Dual-color curved road polyline
  /// - Follow Rider vs Full Route camera switch
  Widget _buildZomatoLiveMapCard() {
    final markers = <Marker>{};

    // 1. Hub Marker (🏬 Dark Store Hub)
    markers.add(
      Marker(
        markerId: const MarkerId("hub"),
        position: _hub,
        anchor: const Offset(0.5, 0.95),
        icon:
            _hubIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(
          title: "Flash Fresh Central Dark Store Hub",
          snippet: "Metro Pillar 84",
        ),
      ),
    );

    // 2. Customer Destination Marker (🏠 Your Address)
    markers.add(
      Marker(
        markerId: const MarkerId("destination"),
        position: _destination,
        anchor: const Offset(0.5, 0.95),
        icon:
            _destIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: "Drop-off Address",
          snippet: widget.deliveryAddress,
        ),
      ),
    );

    // 3. Animated Rider Bike Marker
    if (_bikeMarker != null) {
      markers.add(_bikeMarker!);
    }

    // Split route into Traveled (solid green) and Remaining (mint)
    final int splitIdx = (_bikeProgress * (_routePoints.length - 1))
        .clamp(0, _routePoints.length - 1)
        .toInt();

    final traveledPoints = _routePoints.sublist(0, splitIdx + 1);
    final remainingPoints = _routePoints.sublist(splitIdx);

    final polylines = <Polyline>{};

    // Traveled road path (Solid Brand Emerald)
    if (traveledPoints.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId("traveled_path"),
          points: traveledPoints,
          color: const Color(0xFF059669),
          width: 6,
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
        ),
      );
    }

    // Remaining road path (Mint Green track)
    if (remainingPoints.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId("remaining_path"),
          points: remainingPoints,
          color: const Color(0xFF6EE7B7),
          width: 4,
          jointType: JointType.round,
          endCap: Cap.roundCap,
          startCap: Cap.roundCap,
        ),
      );
    }

    // Pulsing radar ripple circles around the rider (Zomato-style)
    final circles = <Circle>{};
    final riderPos = _getCurrentBikePosition();
    circles.add(
      Circle(
        circleId: const CircleId("rider_radar_glow"),
        center: riderPos,
        radius: 20.0 + (_radarAnimation.value * 45.0),
        fillColor: const Color(
          0xFF059669,
        ).withOpacity(((1.0 - _radarAnimation.value) * 0.28).clamp(0.0, 1.0)),
        strokeColor: const Color(
          0xFF059669,
        ).withOpacity(((1.0 - _radarAnimation.value) * 0.70).clamp(0.0, 1.0)),
        strokeWidth: 2,
      ),
    );

    final int pct = (_bikeProgress * 100).toInt().clamp(0, 100);

    return GlassCard(
      blur: 20,
      opacity: 0.95,
      borderRadius: 24,
      borderColor: Colors.grey.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF059669),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "LIVE RIDER GPS",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.8,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  setState(() => _followRider = !_followRider);
                  if (_followRider) {
                    _mapController?.animateCamera(
                      CameraUpdate.newLatLngZoom(riderPos, 16.0),
                    );
                  } else {
                    _fitBounds();
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _followRider
                        ? const Color(0xFF059669)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _followRider
                          ? const Color(0xFF059669)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _followRider
                            ? Icons.my_location_rounded
                            : Icons.map_outlined,
                        size: 13,
                        color: _followRider ? Colors.white : Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _followRider ? "Following Rider" : "View Whole Route",
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: _followRider ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Google Map Container
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 290,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    (_hub.latitude + _destination.latitude) / 2,
                    (_hub.longitude + _destination.longitude) / 2,
                  ),
                  zoom: 13.5,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                  _fitBounds();
                },
                markers: markers,
                polylines: polylines,
                circles: circles,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
                liteModeEnabled: false,
                trafficEnabled: true,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Journey progress HUD
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_rounded,
                          size: 15,
                          color: Color(0xFF059669),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          "Dark Store",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      _currentStatus == "DELIVERED"
                          ? "Arrived at Doorstep 🎉"
                          : "$pct% Completed (~$_etaMins mins)",
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF059669),
                      ),
                    ),
                    Row(
                      children: [
                        const Text(
                          "Home",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.home_rounded,
                          size: 15,
                          color: Colors.redAccent,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _bikeProgress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF059669),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderCard() {
    final name = _riderInfo?["name"] ?? "Ravi Kumar";
    final vehicle = _riderInfo?["vehicle"] ?? "Hero Electric (TS 07 EK 4921)";

    return GlassCard(
      blur: 16,
      opacity: 0.9,
      borderRadius: 22,
      borderColor: Colors.grey.shade200,
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF059669).withOpacity(0.12),
            child: const Icon(
              Icons.delivery_dining_rounded,
              color: Color(0xFF059669),
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF111827),
                  ),
                ),
                Text(
                  vehicle,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      color: Colors.amber,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "4.9 • Central Fleet Partner",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: CircleAvatar(
              backgroundColor: const Color(0xFF059669),
              child: const Icon(
                Icons.call_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "Calling Fleet Partner $name (+91 98480 12345)...",
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard() {
    return GlassCard(
      blur: 16,
      opacity: 0.9,
      borderRadius: 22,
      borderColor: Colors.grey.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Order Status Timeline",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 16),
          _buildTimelineStep(
            icon: Icons.check_circle_rounded,
            title: "Order Placed & Confirmed",
            subtitle: "Payment received via Cashfree",
            isCompleted: true,
            isCurrent: _currentStatus == "PLACED",
          ),
          _buildTimelineStep(
            icon: Icons.inventory_2_rounded,
            title: "Packed & Weighed at Central Hub",
            subtitle: "Inspected by Dark Store Manager",
            isCompleted:
                _currentStatus == "PACKED" ||
                _currentStatus == "OUT_FOR_DELIVERY" ||
                _currentStatus == "DELIVERED",
            isCurrent: _currentStatus == "PACKED",
          ),
          _buildTimelineStep(
            icon: Icons.two_wheeler_rounded,
            title: "Rider On the Way",
            subtitle: "Heading to ${widget.deliveryAddress}",
            isCompleted:
                _currentStatus == "OUT_FOR_DELIVERY" ||
                _currentStatus == "DELIVERED",
            isCurrent: _currentStatus == "OUT_FOR_DELIVERY",
          ),
          _buildTimelineStep(
            icon: Icons.home_rounded,
            title: "Delivered to Doorstep",
            subtitle: "Verified with 4-digit PIN",
            isCompleted: _currentStatus == "DELIVERED",
            isCurrent: _currentStatus == "DELIVERED",
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildOrderReceiptCard() {
    return GlassCard(
      blur: 16,
      opacity: 0.9,
      borderRadius: 22,
      borderColor: Colors.grey.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Order Items & Receipt",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF111827),
                ),
              ),
              Text(
                "₹${widget.grandTotal.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
          const Divider(height: 20, color: Colors.black12),
          ...widget.items.map(
            (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  Text(
                    "${i.quantity}x",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "${i.product.name} (${i.selectedVariant.weightLabel})",
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  Text(
                    "₹${i.totalPrice.toStringAsFixed(0)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
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

  Widget _buildTimelineStep({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isCompleted,
    required bool isCurrent,
    bool isLast = false,
  }) {
    Color stepColor = isCurrent
        ? const Color(0xFF059669)
        : (isCompleted ? const Color(0xFF059669) : Colors.grey.shade400);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: stepColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: stepColor, size: 20),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 36,
                color: isCompleted
                    ? const Color(0xFF059669)
                    : Colors.grey.shade300,
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isCurrent
                      ? const Color(0xFF059669)
                      : const Color(0xFF111827),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
            ],
          ),
        ),
      ],
    );
  }

  void _showRatingDialog() {
    int productRating = 5;
    int riderRating = 5;
    final reviewCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Column(
            children: [
              Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 48),
              SizedBox(height: 8),
              Text(
                "Rate Delivery & Freshness",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
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
                const Text(
                  "Product & Vegetable Freshness",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (idx) {
                    final star = idx + 1;
                    return IconButton(
                      icon: Icon(
                        star <= productRating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () =>
                          setModalState(() => productRating = star),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Rider Speed & Behavior",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (idx) {
                    final star = idx + 1;
                    return IconButton(
                      icon: Icon(
                        star <= riderRating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () => setModalState(() => riderRating = star),
                    );
                  }),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: reviewCtrl,
                  maxLines: 2,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    hintText: "Write a comment (optional)...",
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Skip",
                style: TextStyle(color: Colors.black54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await ApiService.rateOrder(
                  widget.orderId,
                  productRating,
                  reviewCtrl.text.trim(),
                );
                if (!mounted) return;
                LiquidToast.show(
                  context,
                  message: "⭐ Thank you for rating your delivery & freshness!",
                  icon: Icons.stars_rounded,
                  accentColor: Colors.amber.shade900,
                );
              },
              child: const Text(
                "Submit Rating",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          "Cancel Order?",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
        content: const Text(
          "Are you sure you want to cancel this order? Guaranteed 100% refund will be credited back to your account.",
          style: TextStyle(color: Colors.black87, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              "Keep Order",
              style: TextStyle(color: Colors.black54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await ApiService.cancelOrder(widget.orderId);
              if (!mounted) return;
              setState(() {
                _currentStatus = "CANCELLED";
              });
              LiquidToast.show(
                context,
                message:
                    res['message'] ??
                    "🚫 Order cancelled. 100% refund initiated.",
                icon: Icons.cancel_outlined,
                accentColor: Colors.redAccent,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text(
              "Yes, Cancel",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSupportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Need Help with Order?",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFF059669),
                child: Icon(Icons.call, color: Colors.white),
              ),
              title: const Text(
                "Call Delivery Partner",
                style: TextStyle(color: Color(0xFF111827)),
              ),
              subtitle: const Text(
                "Ravi Kumar (+91 98480 12345)",
                style: TextStyle(color: Colors.black54),
              ),
              onTap: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Calling Rider...")),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
