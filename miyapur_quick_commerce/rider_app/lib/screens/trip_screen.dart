import 'dart:async';
import 'package:flutter/material.dart';
import '../models/rider_order.dart';
import '../services/rider_api_service.dart';

class TripScreen extends StatefulWidget {
  final RiderOrderModel order;
  final VoidCallback onTripCompleted;

  const TripScreen({super.key, required this.order, required this.onTripCompleted});

  @override
  State<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends State<TripScreen> {
  // Stages: 0 = heading_to_hub, 1 = en_route_to_customer, 2 = delivered
  int _stage = 0;
  bool _isLoading = false;
  final TextEditingController _otpCtrl = TextEditingController();

  // Live GPS simulation & sync
  Timer? _simTimer;
  bool _isSimulating = false;
  List<Map<String, double>> _routeWaypoints = [];
  int _currentWpIdx = 0;

  @override
  void initState() {
    super.initState();
    if (widget.order.status == 'OUT_FOR_DELIVERY') {
      _stage = 1;
      _fetchWaypoints();
    }
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _fetchWaypoints() async {
    final pts = await RiderApiService.getRoutePoints(
      originLat: 17.495101,
      originLng: 78.367535,
      destLat: 17.4985,
      destLng: 78.3720,
    );
    if (!mounted) return;
    setState(() {
      _routeWaypoints = pts;
      _currentWpIdx = 0;
    });
  }

  void _toggleSimulatedRide() {
    if (_isSimulating) {
      _simTimer?.cancel();
      setState(() => _isSimulating = false);
    } else {
      setState(() => _isSimulating = true);
      _simTimer = Timer.periodic(const Duration(milliseconds: 1400), (timer) async {
        if (_currentWpIdx >= _routeWaypoints.length - 1) {
          timer.cancel();
          if (!mounted) return;
          setState(() {
            _isSimulating = false;
            _currentWpIdx = _routeWaypoints.length - 1;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("🛵 Arrived at customer doorstep! Ask customer for 4-digit PIN."),
              backgroundColor: Colors.green,
            ),
          );
          _showOtpVerificationDialog();
          return;
        }

        setState(() {
          _currentWpIdx++;
        });

        final wp = _routeWaypoints[_currentWpIdx];
        await RiderApiService.updateLocation(
          widget.order.orderId,
          wp["lat"]!,
          wp["lng"]!,
        );
      });
    }
  }

  void _handlePickupFromHub() async {
    setState(() => _isLoading = true);
    await RiderApiService.pickupOrder(widget.order.orderId);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _stage = 1;
    });
    _fetchWaypoints();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Bag collected & verified! En route to customer location."),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showOtpVerificationDialog() {
    _otpCtrl.clear();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Colors.green),
            SizedBox(width: 8),
            Text("Customer Delivery PIN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Ask customer for the 4-digit PIN displayed on their order tracking screen.",
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              autofocus: true,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: "••••",
                counterText: "",
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final otp = _otpCtrl.text.trim();
              if (otp.length != 4) return;

              Navigator.pop(ctx);
              _handleVerifyOtpAndComplete(otp);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade800,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Verify PIN & Deliver", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _handleVerifyOtpAndComplete(String otp) async {
    setState(() => _isLoading = true);
    final res = await RiderApiService.verifyDeliveryOtp(widget.order.orderId, otp);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      setState(() => _stage = 2);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Column(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 54),
              SizedBox(height: 8),
              Text("Delivery Completed!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "₹${widget.order.payoutAmount.toStringAsFixed(0)}",
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.green),
              ),
              const Text("Credited to your Rider Wallet", style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: const Text(
                  "⚡ Verified with OTP • 10-Minute SLA Maintained",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                  widget.onTripCompleted();
                },
                child: const Text("Next Delivery", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['detail'] ?? "Incorrect PIN code! Please re-verify with customer."),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          _stage == 0 ? "Pickup: Central Dark Store" : "Drop: Customer Doorstep",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Status Header Banner
            Container(
              padding: const EdgeInsets.all(16),
              color: _stage == 0 ? Colors.amber.shade700 : Colors.green.shade800,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Icon(
                      _stage == 0 ? Icons.store : Icons.two_wheeler,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _stage == 0 ? "STEP 1: PICKUP FROM HUB" : "STEP 2: EN ROUTE TO CUSTOMER",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          _stage == 0
                              ? "Head to Central Dark Store Hub (Pillar 84)"
                              : "Deliver bag to customer & verify 4-digit PIN",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      "₹${widget.order.payoutAmount.toStringAsFixed(0)} Pay",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green.shade900),
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Order Details Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Order #${widget.order.orderNumber}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              "${widget.order.distanceKm} KM Trip",
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )
                        ],
                      ),
                      const Divider(height: 20),

                      _routeStep(
                        icon: Icons.storefront,
                        color: Colors.amber.shade800,
                        title: "Pickup Point:",
                        address: widget.order.pickupHub,
                        isDone: _stage > 0,
                      ),
                      const SizedBox(height: 12),

                      _routeStep(
                        icon: Icons.location_on,
                        color: Colors.green.shade700,
                        title: "Drop Location:",
                        address: widget.order.deliveryAddress,
                        isDone: _stage == 2,
                      ),

                      const Divider(height: 24),

                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Customer Contact:", style: TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(
                                  widget.order.customerPhone,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Calling ${widget.order.customerPhone}...")),
                              );
                            },
                            icon: const Icon(Icons.phone, size: 16, color: Colors.green),
                            label: const Text("Call", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.green),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Items List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Items in Bag (Verify at Hub):",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      ...widget.order.items.map((i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.check_box, color: Colors.green, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "${i.name} (${i.variant})",
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  "x${i.quantity}",
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                )
                              ],
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Live GPS Trip Sync Card (Active during Stage 1)
            if (_stage == 1) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.satellite_alt_rounded, color: Colors.green, size: 20),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "⚡ Live GPS Trip Sync",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  Text(
                                    "Broadcasting coordinates to customer map",
                                    style: TextStyle(fontSize: 11, color: Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isSimulating ? Colors.green.shade100 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 3,
                                    backgroundColor: _isSimulating ? Colors.green : Colors.grey,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isSimulating ? "Live Streaming" : "Standby",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _isSimulating ? Colors.green.shade900 : Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _routeWaypoints.isEmpty
                                ? 0.0
                                : (_currentWpIdx / (_routeWaypoints.length - 1)).clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation(Colors.green),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Hub: Pillar 84",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                            Text(
                              _routeWaypoints.isEmpty
                                  ? "Calculating route..."
                                  : "${((_currentWpIdx / (_routeWaypoints.length - 1)) * 100).toInt()}% Traveled",
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            Text(
                              "Customer Doorstep",
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _routeWaypoints.isEmpty ? null : _toggleSimulatedRide,
                            icon: Icon(_isSimulating ? Icons.pause_circle : Icons.play_circle_fill, size: 20),
                            label: Text(
                              _isSimulating ? "Pause Ride Simulation" : "⚡ Simulate Live Ride (Stream GPS)",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isSimulating ? Colors.orange.shade700 : Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 12),

            // Action Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_stage == 0 ? _handlePickupFromHub : _showOtpVerificationDialog),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _stage == 0 ? Colors.amber.shade800 : Colors.green.shade700,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _stage == 0
                              ? "✓ Confirm Bag Picked Up from Hub"
                              : "🔑 Enter Customer PIN & Complete Delivery",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _routeStep({
    required IconData icon,
    required Color color,
    required String title,
    required String address,
    required bool isDone,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: isDone ? Colors.grey : color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDone ? Colors.grey : Colors.black87,
                ),
              ),
              Text(
                address,
                style: TextStyle(
                  fontSize: 13,
                  color: isDone ? Colors.grey : Colors.black54,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ],
          ),
        ),
        if (isDone) const Icon(Icons.check_circle, color: Colors.green, size: 18),
      ],
    );
  }
}
