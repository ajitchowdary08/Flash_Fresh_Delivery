import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/rider_order.dart';
import '../services/rider_api_service.dart';
import 'trip_screen.dart';
import 'earnings_screen.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isOnline = true;
  double _todayEarnings = 0.0;
  int _completedTrips = 0;
  String _riderName = "Delivery Partner";
  String _vehicleInfo = "Assigned Vehicle";
  double _riderRating = 5.0;

  List<RiderOrderModel> _availableOrders = [];
  bool _isLoading = true;
  Timer? _radarTimer;
  Timer? _shiftTimer;
  int _shiftSeconds = 0;
  final Set<String> _dismissedOrderIds = {};

  // Incoming Order Alert Modal state
  RiderOrderModel? _activeAlertOrder;
  Timer? _countdownTimer;
  int _countdownSeconds = 30;

  @override
  void initState() {
    super.initState();
    _loadRiderData();
    _startRadarTimer();
    _startShiftTimer();
  }

  @override
  void dispose() {
    _radarTimer?.cancel();
    _shiftTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startShiftTimer() {
    _shiftTimer?.cancel();
    _shiftTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isOnline && mounted) {
        setState(() => _shiftSeconds++);
      }
    });
  }

  String _formatShiftDuration(int totalSecs) {
    final hours = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    return "${hours}h ${mins}m";
  }

  void _startRadarTimer() {
    _radarTimer?.cancel();
    _radarTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      if (_isOnline && mounted) {
        final orders = await RiderApiService.getAvailableOrders();
        if (!mounted) return;
        setState(() {
          _availableOrders = orders;
        });

        // If not already presenting an alert and an un-dismissed order is available, pop up Swiggy alert
        if (_activeAlertOrder == null && orders.isNotEmpty) {
          final candidate = orders.firstWhere(
            (o) => !_dismissedOrderIds.contains(o.orderId),
            orElse: () => orders.first,
          );
          if (!_dismissedOrderIds.contains(candidate.orderId)) {
            _triggerIncomingOrderAlert(candidate);
          }
        }
      }
    });
  }

  void _loadRiderData() async {
    setState(() => _isLoading = true);
    final profile = await RiderApiService.getProfile();
    final orders = await RiderApiService.getAvailableOrders();

    if (!mounted) return;
    setState(() {
      _riderName = profile['name'] ?? "Delivery Partner";
      _vehicleInfo = profile['vehicle'] ?? "Assigned Fleet";
      _riderRating = (profile['rating'] as num?)?.toDouble() ?? 5.0;
      _isOnline = profile['is_online'] ?? true;
      _todayEarnings = (profile['today_earnings'] as num?)?.toDouble() ?? 0.0;
      _completedTrips = profile['completed_trips_today'] ?? 0;
      _availableOrders = orders;
      _isLoading = false;
    });

    if (_isOnline && orders.isNotEmpty && _activeAlertOrder == null) {
      _triggerIncomingOrderAlert(orders.first);
    }
  }

  void _toggleDuty(bool val) async {
    HapticFeedback.heavyImpact();
    final res = await RiderApiService.toggleDuty(val);
    if (!mounted) return;
    final bool isOnlineNow = (res["is_online"] as bool?) ?? (res["success"] == true ? val : _isOnline);
    setState(() {
      _isOnline = isOnlineNow;
      if (!_isOnline) {
        _countdownTimer?.cancel();
        _activeAlertOrder = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isOnlineNow
                  ? Icons.check_circle_rounded
                  : Icons.power_settings_new_rounded,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Text(
              isOnlineNow
                  ? "🟢 You are ONLINE in Central Hub!"
                  : "⚪ You are now OFFLINE. Duty paused.",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: isOnlineNow
            ? const Color(0xFF00A352)
            : const Color(0xFF2C2F3E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _triggerIncomingOrderAlert(RiderOrderModel order) {
    HapticFeedback.vibrate();
    _countdownTimer?.cancel();
    setState(() {
      _activeAlertOrder = order;
      _countdownSeconds = 30;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds > 0) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
        setState(() {
          _dismissedOrderIds.add(order.orderId);
          _activeAlertOrder = null;
        });
      }
    });
  }

  void _dismissAlert(RiderOrderModel order) {
    HapticFeedback.lightImpact();
    _countdownTimer?.cancel();
    setState(() {
      _dismissedOrderIds.add(order.orderId);
      _activeAlertOrder = null;
    });
  }

  void _handleAcceptOrder(RiderOrderModel order) async {
    HapticFeedback.heavyImpact();
    _countdownTimer?.cancel();
    setState(() {
      _dismissedOrderIds.add(order.orderId);
      _activeAlertOrder = null;
    });

    final res = await RiderApiService.acceptOrder(order.orderId);
    if (!mounted) return;
    if (res["success"] == true) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TripScreen(
            order: order,
            onTripCompleted: () {
              _loadRiderData();
              setState(() {
                _availableOrders.removeWhere((o) => o.orderId == order.orderId);
                _dismissedOrderIds.add(order.orderId);
              });
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res["message"] ?? "Order acceptance failed."),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1118),
      appBar: _buildSwiggyAppBar(),
      body: Stack(
        children: [
          // Main Scrollable Dashboard
          RefreshIndicator(
            color: const Color(0xFFFC8019),
            onRefresh: () async => _loadRiderData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                children: [
                  _buildDutyControlCard(),
                  const SizedBox(height: 12),
                  _buildEarningsSummaryPill(),
                  const SizedBox(height: 16),
                  _buildDailyTargetTracker(),
                  const SizedBox(height: 16),
                  _buildOrdersSectionHeader(),
                  const SizedBox(height: 12),
                  _buildOrdersListOrStandby(),
                ],
              ),
            ),
          ),

          // High Priority Swiggy Instamart Order Ringing Overlay
          if (_isOnline && _activeAlertOrder != null)
            _buildIncomingOrderModal(_activeAlertOrder!),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildSwiggyAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF161822),
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFC8019), Color(0xFFFF9238)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: Colors.white, size: 14),
                SizedBox(width: 2),
                Text(
                  "INSTAMART FLEET",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _riderName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _vehicleInfo,
                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 14),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF262938),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFFFB300).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.star_rounded,
                color: Color(0xFFFFB300),
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                "$_riderRating",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDutyControlCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF191B26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isOnline
              ? const Color(0xFF00C853).withValues(alpha: 0.3)
              : Colors.white10,
        ),
        boxShadow: [
          BoxShadow(
            color: _isOnline
                ? const Color(0xFF00C853).withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isOnline ? const Color(0xFF00C853) : Colors.grey,
                      boxShadow: _isOnline
                          ? [
                              BoxShadow(
                                color: const Color(0xFF00C853)
                                    .withValues(alpha: 0.8),
                                blurRadius: 10,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isOnline ? "YOU ARE ONLINE" : "YOU ARE OFFLINE",
                        style: TextStyle(
                          color: _isOnline
                              ? const Color(0xFF00C853)
                              : Colors.white60,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Text(
                        "Miyapur Central Dark Store Hub (Pillar 84)",
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: _isOnline,
                activeThumbColor: const Color(0xFF00C853),
                activeTrackColor: const Color(0xFF00C853)
                    .withValues(alpha: 0.25),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.grey.withValues(alpha: 0.2),
                onChanged: _toggleDuty,
              ),
            ],
          ),

          if (_isOnline) ...[
            const Divider(color: Colors.white10, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDiagnosticChip(
                  icon: Icons.timer_outlined,
                  label: "Shift: ${_formatShiftDuration(_shiftSeconds)}",
                ),
                _buildDiagnosticChip(
                  icon: Icons.gps_fixed_rounded,
                  label: "GPS: High (3m)",
                  color: const Color(0xFF00C853),
                ),
                _buildDiagnosticChip(
                  icon: Icons.battery_charging_full_rounded,
                  label: "86% Batt",
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFC8019).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFC8019).withValues(alpha: 0.25),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.trending_up_rounded,
                    color: Color(0xFFFC8019),
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "High demand in Miyapur Central! Switch online to receive instant delivery batches.",
                      style: TextStyle(
                        color: Color(0xFFFFB380),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiagnosticChip({
    required IconData icon,
    required String label,
    Color color = Colors.white70,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF222432),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsSummaryPill() {
    return InkWell(
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF202334), Color(0xFF171926)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFC8019).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.currency_rupee_rounded,
                    color: Color(0xFFFC8019),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "₹${_todayEarnings.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "$_completedTrips Deliveries Completed Today",
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF2C2F40),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Text(
                    "Wallet",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white70,
                    size: 10,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyTargetTracker() {
    const int targetTrips = 10;
    final int progress = _completedTrips.clamp(0, targetTrips);
    final double percent = progress / targetTrips;
    final int remaining = (targetTrips - _completedTrips).clamp(0, 10);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF191B26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFFB300).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.military_tech_rounded,
                    color: Color(0xFFFFB300),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    "Daily Target Incentive",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "+₹120 BONUS",
                  style: TextStyle(
                    color: Color(0xFFFFB300),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 8,
              backgroundColor: const Color(0xFF2A2D3D),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB300)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            remaining == 0
                ? "🎉 Target Achieved! ₹120 bonus added to weekly payout."
                : "Deliver $remaining more order${remaining > 1 ? 's' : ''} today to claim your ₹120 daily bonus!",
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersSectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFC8019),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                "Orders Ready for Pickup",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh_rounded,
              color: Colors.white60,
              size: 20,
            ),
            onPressed: _loadRiderData,
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersListOrStandby() {
    if (!_isOnline) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(
                Icons.bedtime_outlined,
                size: 54,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 12),
              const Text(
                "Duty Paused",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Slide online when ready to receive deliveries",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(color: Color(0xFFFC8019)),
        ),
      );
    }

    if (_availableOrders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Icon(
                Icons.radar_rounded,
                size: 54,
                color: Color(0xFFFC8019),
              ),
              const SizedBox(height: 12),
              const Text(
                "Scanning Miyapur Dark Store Hub...",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "You are priority #1 in Central Zone queue",
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      itemCount: _availableOrders.length,
      itemBuilder: (context, index) {
        final order = _availableOrders[index];
        return _buildOrderCard(order);
      },
    );
  }

  Widget _buildOrderCard(RiderOrderModel order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFC8019).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "⚡ 10-MIN QUICK TRIP",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFFFC8019),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                "₹${order.payoutAmount.toStringAsFixed(0)} PAY",
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: Color(0xFF00C853),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "#${order.orderNumber}",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          const Divider(color: Colors.white10, height: 18),

          Row(
            children: [
              const Icon(
                Icons.storefront_rounded,
                size: 16,
                color: Color(0xFFFFB300),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.pickupHub,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.location_on_rounded,
                size: 16,
                color: Color(0xFF00C853),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.deliveryAddress,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF262836),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  "${order.distanceKm} km",
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => _handleAcceptOrder(order),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFC8019),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Accept Delivery Order",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Swiggy Instamart Order Ringing Overlay with 30s Countdown
  Widget _buildIncomingOrderModal(RiderOrderModel order) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF161824),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: const Color(0xFFFC8019).withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFC8019).withValues(alpha: 0.3),
              blurRadius: 36,
              spreadRadius: 4,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Bar with Timer
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFC8019),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          "NEW DELIVERY BATCH",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "#${order.orderNumber}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),

                  // Circular Countdown Badge
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          value: _countdownSeconds / 30.0,
                          backgroundColor: Colors.white12,
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFFFC8019),
                          ),
                          strokeWidth: 3.5,
                        ),
                      ),
                      Text(
                        "$_countdownSeconds",
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Payout Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF222536),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF00C853).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "TOTAL EARNINGS FOR THIS TRIP",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white60,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "₹${order.payoutAmount.toStringAsFixed(0)}",
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF00C853),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C853).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "${order.distanceKm} KM total",
                        style: const TextStyle(
                          color: Color(0xFF00C853),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Pickup & Drop Steps
              _buildAlertStep(
                icon: Icons.storefront_rounded,
                iconColor: const Color(0xFFFFB300),
                label: "PICKUP DARK STORE",
                title: order.pickupHub,
              ),
              const SizedBox(height: 8),
              _buildAlertStep(
                icon: Icons.location_on_rounded,
                iconColor: const Color(0xFF00C853),
                label: "CUSTOMER DROP",
                title: order.deliveryAddress,
              ),

              const SizedBox(height: 18),

              // Accept / Reject Actions
              Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: () => _dismissAlert(order),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        "Pass",
                        style: TextStyle(
                          color: Colors.white60,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      onPressed: () => _handleAcceptOrder(order),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFC8019),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "ACCEPT ORDER",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertStep({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String title,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: iconColor,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
