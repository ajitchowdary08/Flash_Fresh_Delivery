import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/rider_order.dart';
import '../services/rider_api_service.dart';
import '../services/rider_location_service.dart';

class TripScreen extends StatefulWidget {
  final RiderOrderModel order;
  final VoidCallback onTripCompleted;

  const TripScreen({
    super.key,
    required this.order,
    required this.onTripCompleted,
  });

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  // Stages:
  // 0 = heading_to_hub
  // 1 = at_hub_verifying_bag
  // 2 = en_route_to_customer
  // 3 = at_doorstep_collecting_pin
  // 4 = delivered
  int _stage = 0;
  bool _isLoading = false;
  final TextEditingController _otpCtrl = TextEditingController();

  // Bag verification checklist
  late List<bool> _checkedItems;
  bool _sealVerified = true;
  bool _cashCollected = false;

  // Live GPS hardware streaming & sync
  bool _isGpsStreaming = false;
  List<Map<String, double>> _routeWaypoints = [];
  int _currentWpIdx = 0;
  final RiderLocationService _locationService = RiderLocationService();

  @override
  void initState() {
    super.initState();
    _checkedItems = List.generate(widget.order.items.length, (_) => true);

    if (widget.order.status == 'OUT_FOR_DELIVERY') {
      _stage = 2;
      _fetchWaypoints();
      _startLiveGpsTracking();
    }
  }

  @override
  void dispose() {
    _locationService.stopStreaming();
    _isGpsStreaming = false;
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _startLiveGpsTracking() async {
    try {
      await RiderLocationService.ensurePermission();
      if (!mounted) return;
      setState(() => _isGpsStreaming = true);
      _locationService.startStreaming((lat, lng) async {
        if (!mounted || _stage >= 4) return;
        await RiderApiService.updateLocation(widget.order.orderId, lat, lng);
      });
    } catch (e) {
      debugPrint("[RiderLocation] Live GPS notice: $e");
    }
  }

  void _fetchWaypoints() async {
    final pts = await RiderApiService.getRoutePoints(
      originLat: 17.495101,
      originLng: 78.367535,
      destLat: widget.order.latitude ?? 17.4985,
      destLng: widget.order.longitude ?? 78.3720,
    );
    if (!mounted) return;
    setState(() {
      _routeWaypoints = pts;
      _currentWpIdx = 0;
    });
  }

  void _showArrivalToast() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.doorbell_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text(
              "📍 Arrived at Customer Doorstep! Verify 4-digit PIN.",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF00C853),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _openGoogleMaps(double lat, double lng) async {
    final uri = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$lat,$lng");
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open Google Maps navigation.")),
      );
    }
  }

  Future<void> _callCustomer(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (clean.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Customer phone number not available for this order.")),
      );
      return;
    }
    final uri = Uri.parse("tel:$clean");
    try {
      await launchUrl(uri);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Calling customer: $phone")),
      );
    }
  }

  void _handlePickupFromHub() async {
    HapticFeedback.heavyImpact();
    setState(() => _isLoading = true);
    final res = await RiderApiService.pickupOrder(widget.order.orderId);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      setState(() {
        _stage = 2;
      });
      _fetchWaypoints();
      _startLiveGpsTracking();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.two_wheeler_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text("Bag collected & verified! En route to customer."),
            ],
          ),
          backgroundColor: const Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      final msg = res['message'] ?? res['detail'] ?? "Could not confirm pickup from hub. Please retry.";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleVerifyOtpAndComplete(String otp) async {
    HapticFeedback.heavyImpact();
    setState(() => _isLoading = true);
    final res = await RiderApiService.verifyDeliveryOtp(widget.order.orderId, otp);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      _locationService.stopStreaming();
      _isGpsStreaming = false;
      setState(() => _stage = 4);
      _showSuccessCelebrationDialog();
    } else {
      final msg = res['message'] ?? res['detail'] ?? "Incorrect PIN! Please check customer's order screen.";
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSuccessCelebrationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Color(0xFF00C853), size: 54),
            ),
            const SizedBox(height: 16),
            const Text(
              "Delivery Completed!",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "₹${widget.order.payoutAmount.toStringAsFixed(0)}",
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: Color(0xFF00C853),
              ),
            ),
            const Text(
              "Credited instantly to your Rider Wallet",
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF242738),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt, color: Color(0xFFFC8019), size: 16),
                  SizedBox(width: 6),
                  Text(
                    "⚡ 10-Minute SLA Maintained",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFC8019),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFC8019),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                widget.onTripCompleted();
              },
              child: const Text(
                "Back to Radar for Next Order",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161822),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _stage == 0
                  ? "Step 1: Head to Dark Store"
                  : _stage == 1
                      ? "Step 2: Bag & Produce Check"
                      : _stage == 2
                          ? "Step 3: Delivering to Customer"
                          : "Step 4: Doorstep Handover",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              "#${widget.order.orderNumber}",
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00C853).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "₹${widget.order.payoutAmount.toStringAsFixed(0)} Pay",
              style: const TextStyle(
                color: Color(0xFF00C853),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStageProgressIndicator(),
            const SizedBox(height: 14),

            // Payment Badge (COD vs Online)
            _buildPaymentMethodBanner(),
            const SizedBox(height: 14),

            // Route Summary Card
            _buildRouteDetailsCard(),
            const SizedBox(height: 14),

            // Dynamic Stage Action Content
            if (_stage == 0) _buildStage0HeadToHub(),
            if (_stage == 1) _buildStage1BagChecklist(),
            if (_stage == 2) _buildStage2LiveNavigation(),
            if (_stage >= 3) _buildStage3DoorstepHandover(),
          ],
        ),
      ),
    );
  }

  Widget _buildStageProgressIndicator() {
    final stages = ["Hub", "Verify", "Ride", "Handover"];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF191B26),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(4, (index) {
          final isCompleted = _stage > index;
          final isCurrent = _stage == index;

          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? const Color(0xFF00C853)
                        : isCurrent
                            ? const Color(0xFFFC8019)
                            : const Color(0xFF282B3B),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : Text(
                            "${index + 1}",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isCurrent ? Colors.white : Colors.white60,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  stages[index],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? Colors.white : Colors.white60,
                  ),
                ),
                if (index < 3)
                  const Expanded(
                    child: Divider(
                      color: Colors.white12,
                      indent: 8,
                      endIndent: 8,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildPaymentMethodBanner() {
    final isCod = widget.order.paymentMethod.toUpperCase() == "COD";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isCod
            ? const Color(0xFFFFB300).withValues(alpha: 0.12)
            : const Color(0xFF00C853).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCod
              ? const Color(0xFFFFB300).withValues(alpha: 0.4)
              : const Color(0xFF00C853).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCod ? Icons.payments_rounded : Icons.verified_rounded,
            color: isCod ? const Color(0xFFFFB300) : const Color(0xFF00C853),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isCod
                      ? "CASH ON DELIVERY (COD)"
                      : "PAID ONLINE (UPI / CASHFREE)",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    color: isCod ? const Color(0xFFFFB300) : const Color(0xFF00C853),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isCod
                      ? "Collect ₹${widget.order.grandTotal.toStringAsFixed(0)} CASH at doorstep"
                      : "Collect ₹0.00 — Do NOT ask customer for cash",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteDetailsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF191B26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pickup
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.storefront_rounded, color: Color(0xFFFFB300), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "PICKUP: DARK STORE HUB",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFFB300)),
                    ),
                    Text(
                      widget.order.pickupHub,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: SizedBox(
              height: 18,
              child: VerticalDivider(color: Colors.white24, thickness: 1),
            ),
          ),
          // Drop
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.location_on_rounded, color: Color(0xFF00C853), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "DROP: CUSTOMER DOORSTEP",
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00C853)),
                    ),
                    Text(
                      widget.order.deliveryAddress,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF262838),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${widget.order.distanceKm} km",
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),

          // Customer Contact Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Customer Contact", style: TextStyle(fontSize: 10, color: Colors.white60)),
                  Text(
                    widget.order.customerPhone,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _callCustomer(widget.order.customerPhone),
                    icon: const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF00C853)),
                    label: const Text("Call", style: TextStyle(color: Color(0xFF00C853), fontSize: 12, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF00C853)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _openGoogleMaps(
                      widget.order.latitude ?? 17.4985,
                      widget.order.longitude ?? 78.3720,
                    ),
                    icon: const Icon(Icons.navigation_rounded, size: 14),
                    label: const Text("Navigate", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFC8019),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Stage 0: Reach Dark Store
  Widget _buildStage0HeadToHub() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF191B26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          const Icon(Icons.store_mall_directory_rounded, size: 48, color: Color(0xFFFFB300)),
          const SizedBox(height: 12),
          const Text(
            "Navigate to Miyapur Dark Store Hub",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            "Park at Delivery Bay #3 (Beside Pillar 84)",
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                setState(() => _stage = 1);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFC8019),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.where_to_vote_rounded, size: 18),
                  SizedBox(width: 8),
                  Text("I HAVE REACHED DARK STORE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Stage 1: Bag & Items Checklist
  Widget _buildStage1BagChecklist() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF191B26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Verify Order Items & Bag Seal",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF262838),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "${widget.order.items.length} Items",
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),

          // Items with checkboxes
          ...List.generate(widget.order.items.length, (index) {
            final item = widget.order.items[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: CheckboxListTile(
                value: _checkedItems[index],
                activeColor: const Color(0xFF00C853),
                checkColor: Colors.black,
                contentPadding: EdgeInsets.zero,
                dense: true,
                onChanged: (val) {
                  setState(() => _checkedItems[index] = val ?? false);
                },
                title: Text(
                  item.name,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                subtitle: Text(
                  "${item.variant} • Qty: ${item.quantity}",
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ),
            );
          }),

          const Divider(color: Colors.white10, height: 20),

          // Tamper seal confirmation
          CheckboxListTile(
            value: _sealVerified,
            activeColor: const Color(0xFFFC8019),
            contentPadding: EdgeInsets.zero,
            dense: true,
            onChanged: (val) => setState(() => _sealVerified = val ?? false),
            title: const Text(
              "Tamper-proof bag seal is intact & verified",
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFFB380)),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handlePickupFromHub,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C853),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_bag_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "CONFIRM BAG PICKED UP & START RIDE",
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // Stage 2: Live Navigation & GPS Stream
  Widget _buildStage2LiveNavigation() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF191B26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.two_wheeler_rounded, color: Color(0xFFFC8019), size: 20),
                  SizedBox(width: 8),
                  Text(
                    "En Route to Customer",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isGpsStreaming ? const Color(0xFF00C853).withValues(alpha: 0.15) : const Color(0xFF262838),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3,
                      backgroundColor: _isGpsStreaming ? const Color(0xFF00C853) : Colors.grey,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isGpsStreaming ? "GPS Streaming Live" : "GPS Ready",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _isGpsStreaming ? const Color(0xFF00C853) : Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Route Waypoint Progress
          if (_routeWaypoints.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (_currentWpIdx + 1) / _routeWaypoints.length,
                minHeight: 6,
                backgroundColor: const Color(0xFF262838),
                valueColor: const AlwaysStoppedAnimation(Color(0xFFFC8019)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Route waypoint ${_currentWpIdx + 1} of ${_routeWaypoints.length} • Updating customer tracking map via live device GPS",
              style: const TextStyle(fontSize: 10, color: Colors.white60),
            ),
            const SizedBox(height: 16),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                setState(() => _stage = 3);
                _showArrivalToast();
              },
              icon: const Icon(Icons.location_on_rounded, size: 18),
              label: const Text("Arrived at Customer Location", style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFC8019),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Stage 3: Doorstep Handover & 4-Digit Delivery PIN Verification
  Widget _buildStage3DoorstepHandover() {
    final isCod = widget.order.paymentMethod.toUpperCase() == "COD";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF191B26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00C853).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined, color: Color(0xFF00C853), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Doorstep Delivery Verification",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                    Text(
                      "Ask customer for the 4-digit Delivery PIN",
                      style: TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (isCod) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB300).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.3)),
              ),
              child: CheckboxListTile(
                value: _cashCollected,
                activeColor: const Color(0xFFFFB300),
                checkColor: Colors.black,
                contentPadding: EdgeInsets.zero,
                dense: true,
                onChanged: (val) => setState(() => _cashCollected = val ?? false),
                title: Text(
                  "Collected ₹${widget.order.grandTotal.toStringAsFixed(0)} CASH from customer",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFFFB300)),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // 4-Digit OTP Entry
          TextField(
            controller: _otpCtrl,
            keyboardType: TextInputType.number,
            maxLength: 4,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 16,
              color: Color(0xFF00C853),
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: "••••",
              hintStyle: const TextStyle(letterSpacing: 16, color: Colors.white24),
              counterText: "",
              filled: true,
              fillColor: const Color(0xFF222536),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF00C853), width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      final otp = _otpCtrl.text.trim();
                      if (otp.length != 4) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Please enter the complete 4-digit PIN.")),
                        );
                        return;
                      }
                      if (isCod && !_cashCollected) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Please confirm cash collection first.")),
                        );
                        return;
                      }
                      _handleVerifyOtpAndComplete(otp);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C853),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text(
                      "VERIFY PIN & COMPLETE DELIVERY",
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
