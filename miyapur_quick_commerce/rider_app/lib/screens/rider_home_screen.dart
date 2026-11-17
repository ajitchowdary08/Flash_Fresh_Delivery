import 'package:flutter/material.dart';
import '../models/rider_order.dart';
import '../services/rider_api_service.dart';
import 'trip_screen.dart';
import 'earnings_screen.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  bool _isOnline = true;
  double _todayEarnings = 385.0;
  int _completedTrips = 9;
  String _riderName = "Ravi Kumar";
  String _vehicleInfo = "Hero Electric (TS 07 EK 4921)";

  List<RiderOrderModel> _availableOrders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRiderData();
  }

  void _loadRiderData() async {
    setState(() => _isLoading = true);
    final profile = await RiderApiService.getProfile();
    final orders = await RiderApiService.getAvailableOrders();

    if (!mounted) return;
    setState(() {
      _riderName = profile['name'] ?? "Ravi Kumar";
      _vehicleInfo = profile['vehicle'] ?? "Hero Electric";
      _isOnline = profile['is_online'] ?? true;
      _todayEarnings = (profile['today_earnings'] as num?)?.toDouble() ?? 385.0;
      _completedTrips = profile['completed_trips_today'] ?? 9;
      _availableOrders = orders;
      _isLoading = false;
    });
  }

  void _toggleDuty(bool val) async {
    final res = await RiderApiService.toggleDuty(val);
    if (!mounted) return;
    setState(() => _isOnline = res);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res ? "You are now ONLINE in Central Zone!" : "You are now OFFLINE."),
        backgroundColor: res ? Colors.green : Colors.grey.shade700,
      ),
    );
  }

  void _handleAcceptOrder(RiderOrderModel order) async {
    final success = await RiderApiService.acceptOrder(order.orderId);
    if (!mounted) return;
    if (success) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TripScreen(
            order: order,
            onTripCompleted: () {
              setState(() {
                _todayEarnings += order.payoutAmount;
                _completedTrips += 1;
                _availableOrders.removeWhere((o) => o.orderId == order.orderId);
              });
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.green.shade800,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_riderName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(_vehicleInfo, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          // Online / Offline Switch
          Row(
            children: [
              Text(
                _isOnline ? "ONLINE" : "OFFLINE",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: _isOnline ? Colors.amber.shade300 : Colors.white60,
                ),
              ),
              Switch(
                value: _isOnline,
                activeThumbColor: Colors.amber,
                activeTrackColor: Colors.amber.shade200,
                onChanged: _toggleDuty,
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Earnings Header Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.green.shade800,
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EarningsScreen(
                      todayEarnings: _todayEarnings,
                      completedTrips: _completedTrips,
                    ),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade900,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.amber,
                          child: Icon(Icons.currency_rupee, color: Colors.black87, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "₹${_todayEarnings.toStringAsFixed(0)} Earned Today",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            Text(
                              "$_completedTrips Deliveries Completed",
                              style: TextStyle(color: Colors.green.shade200, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Row(
                      children: [
                        Text("View Wallet", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),

          // Main Orders Section
          Expanded(
            child: !_isOnline
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.power_settings_new, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text("You are currently OFFLINE", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 8),
                        Text("Toggle the switch above to receive delivery orders", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      ],
                    ),
                  )
                : _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _availableOrders.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.two_wheeler, size: 64, color: Colors.green),
                                const SizedBox(height: 16),
                                const Text("Waiting for New Orders...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                const SizedBox(height: 6),
                                Text(
                                  "Scanning 10 KM delivery zone",
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _loadRiderData,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text("Refresh Radar"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                )
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _availableOrders.length,
                            itemBuilder: (context, index) {
                              final order = _availableOrders[index];

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                elevation: 1,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                child: Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Top Order Header
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.green.shade50,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  "⚡ QUICK DELIVERY",
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green.shade800,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                "#${order.orderNumber}",
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            "₹${order.payoutAmount.toStringAsFixed(0)} PAY",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16,
                                              color: Colors.green.shade900,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 18),

                                      // Pickup & Drop
                                      Row(
                                        children: [
                                          const Icon(Icons.storefront, size: 18, color: Colors.amber),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              order.pickupHub,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on, size: 18, color: Colors.green),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              order.deliveryAddress,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                                            child: Text("${order.distanceKm} km", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                          )
                                        ],
                                      ),
                                      const SizedBox(height: 12),

                                      // Accept button
                                      SizedBox(
                                        width: double.infinity,
                                        height: 44,
                                        child: ElevatedButton(
                                          onPressed: () => _handleAcceptOrder(order),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green.shade700,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text("Accept Delivery Order", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                              SizedBox(width: 8),
                                              Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
