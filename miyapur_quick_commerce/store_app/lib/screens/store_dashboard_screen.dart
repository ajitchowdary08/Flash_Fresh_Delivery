import 'dart:async';
import 'package:flutter/material.dart';
import '../services/store_api_service.dart';

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({super.key});

  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  int _currentTab = 0; // 0: Packing, 1: Meat Weighing, 2: Ratings
  bool _isLoading = true;
  Timer? _autoRefreshTimer;

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _packingQueue = [];
  Map<String, dynamic>? _ratingsData;

  final TextEditingController _meatWeightController = TextEditingController(text: "1.050");
  String? _selectedMeatOrderId;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _meatWeightController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _loadDashboardData(isBackground: true);
    });
  }

  Future<void> _loadDashboardData({bool isBackground = false}) async {
    if (!isBackground) setState(() => _isLoading = true);

    final summary = await StoreApiService.getDashboardSummary();
    final queue = await StoreApiService.getPackingQueue();
    final ratings = await StoreApiService.getRatings();

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _packingQueue = queue;
      _ratingsData = ratings;
      _isLoading = false;
    });
  }

  void _handleMarkPacked(String orderId) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("📦 Order marked as Packed & Ready for Rider Pickup!"),
        backgroundColor: Color(0xFF059669),
      ),
    );
    await StoreApiService.markOrderPacked(orderId);
    _loadDashboardData();
  }

  void _handleMeatWeigh() async {
    if (_selectedMeatOrderId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a Sunday Meat order to weigh.")),
      );
      return;
    }
    final w = double.tryParse(_meatWeightController.text) ?? 1.0;
    await StoreApiService.submitMeatWeight(_selectedMeatOrderId!, w);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("🥩 Meat weighed (${w}kg) & sealed in temp-controlled bag!"),
        backgroundColor: const Color(0xFFD97706),
      ),
    );
    _loadDashboardData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF064E3B),
        foregroundColor: Colors.white,
        elevation: 2,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Flash Fresh Manager", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            Text("Central Dark Store Hub • Metro Pillar 84", style: TextStyle(fontSize: 11, color: Color(0xFF6EE7B7))),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _loadDashboardData(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              onRefresh: () => _loadDashboardData(),
              color: const Color(0xFF059669),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KPI Overview Grid Cards
                    _buildKpiGrid(),

                    const SizedBox(height: 16),

                    // Custom Segment Navigation Tabs
                    _buildSegmentTabs(),

                    const SizedBox(height: 16),

                    // Active Tab Section View
                    if (_currentTab == 0) _buildPackingQueueTab(),
                    if (_currentTab == 1) _buildMeatWeighingTab(),
                    if (_currentTab == 2) _buildCustomerRatingsTab(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKpiGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _kpiCard("To Pack", "${_summary?['orders_to_pack'] ?? 0}", Icons.dolly_rounded, Colors.amber.shade900, Colors.amber.shade50),
        _kpiCard("Ready Pickup", "${_summary?['orders_ready_for_pickup'] ?? 0}", Icons.check_circle_outline_rounded, Colors.blue.shade900, Colors.blue.shade50),
        _kpiCard("In Transit", "${_summary?['orders_in_transit'] ?? 0}", Icons.two_wheeler_rounded, Colors.purple.shade900, Colors.purple.shade50),
        _kpiCard("Delivered Today", "${_summary?['orders_delivered_today'] ?? 0}", Icons.verified_rounded, const Color(0xFF047857), const Color(0xFFECFDF5)),
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentTabs() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          _tabButton(0, "Packing Queue", Icons.inventory_2_rounded),
          _tabButton(1, "Meat Weigh", Icons.scale_rounded),
          _tabButton(2, "Ratings", Icons.star_rounded),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label, IconData icon) {
    final isSel = _currentTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _currentTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSel ? const Color(0xFF064E3B) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSel ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSel ? Colors.white : Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackingQueueTab() {
    if (_packingQueue.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.inventory_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            const Text("No Active Packing Orders", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text("New 10-minute customer orders will appear here automatically.", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      children: _packingQueue.map((o) {
        final items = o["items"] as List<dynamic>? ?? [];
        final isPacked = o["status"] == "PACKED";

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isPacked ? Colors.blue.shade200 : Colors.amber.shade300, width: 1.5),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o["order_number"] ?? "#MYP-ORDER", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF111827))),
                      Text("Address: ${o['delivery_address'] ?? 'Customer Address'}", style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPacked ? Colors.blue.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isPacked ? "✓ READY FOR RIDER" : "⏳ WEIGH & PACK",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: isPacked ? Colors.blue.shade900 : Colors.amber.shade900,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),

              const Text("Item Packing Checklist:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
              const SizedBox(height: 6),

              ...items.map((itm) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.check_box_rounded, size: 18, color: Color(0xFF059669)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "${itm['product_name']} (${itm['variant_label']})",
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF111827)),
                          ),
                        ),
                        Text(
                          "x${itm['quantity']}",
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                  )),

              const SizedBox(height: 14),

              if (!isPacked)
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _handleMarkPacked(o["order_id"]),
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text("Mark Packed & Ready for Rider Pickup", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMeatWeighingTab() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
                child: Icon(Icons.scale_rounded, color: Colors.amber.shade900, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Sunday Meat Weighing Station", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text("Digital scale integration • Turmeric wash & seal", style: TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          const Text("Enter Weighed Net Weight (Kg):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),

          TextField(
            controller: _meatWeightController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF059669)),
            decoration: InputDecoration(
              suffixText: "KG",
              suffixStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _handleMeatWeigh,
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: const Text("Confirm Weight & Seal Temperature-Controlled Bag", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerRatingsTab() {
    final reviews = _ratingsData?["recent_reviews"] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Customer Ratings & Reviews", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  Text("Live produce freshness & rider speed feedback", style: TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  "${_ratingsData?['avg_rating'] ?? 4.9} ⭐",
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFB45309)),
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          ...reviews.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r["order_number"] ?? "#ORDER", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text("⭐ ${r['rider_rating']} Stars", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('"${r['review']}"', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                    const SizedBox(height: 2),
                    Text(r["date"] ?? "", style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
