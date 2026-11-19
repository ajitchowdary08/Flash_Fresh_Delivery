import 'dart:async';
import 'package:flutter/material.dart';
import '../services/store_api_service.dart';

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({super.key});

  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  int _currentTab = 0; // 0: Packing, 1: Meat, 2: Inventory, 3: Catalog, 4: Ratings
  bool _isLoading = true;
  bool _soundEnabled = true;
  Timer? _autoRefreshTimer;

  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _activeRiders = [];
  List<Map<String, dynamic>> _packingQueue = [];
  List<Map<String, dynamic>> _inventoryList = [];
  List<Map<String, dynamic>> _categories = [];
  Map<String, dynamic>? _ratingsData;

  // Persistent Stock Intake Controllers
  final Map<String, TextEditingController> _nameCtrls = {};
  final Map<String, TextEditingController> _labelCtrls = {};
  final Map<String, TextEditingController> _priceCtrls = {};
  final Map<String, TextEditingController> _stockCtrls = {};

  // Selected Rider map per order
  final Map<String, String> _selectedRiders = {};

  // Add Product Form Controllers
  String? _newSelectedCategoryId;
  final _newProductNameCtrl = TextEditingController();
  final _newProductDescCtrl = TextEditingController();
  final _newProductImageCtrl = TextEditingController();
  bool _newProductIsSunday = false;
  final _vLabelCtrl = TextEditingController(text: "1kg");
  final _vMrpCtrl = TextEditingController(text: "50");
  final _vPriceCtrl = TextEditingController(text: "40");
  final _vStockCtrl = TextEditingController(text: "100");

  // Meat Weigh Modal State
  String? _weighOrderId;
  String? _weighOrderNum;
  final _weighWeightCtrl = TextEditingController(text: "520");
  String _cutStyle = "Curry Cut (Medium with bone)";
  bool _turmericWash = true;
  bool _skinless = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _newProductNameCtrl.dispose();
    _newProductDescCtrl.dispose();
    _newProductImageCtrl.dispose();
    _vLabelCtrl.dispose();
    _vMrpCtrl.dispose();
    _vPriceCtrl.dispose();
    _vStockCtrl.dispose();
    _weighWeightCtrl.dispose();
    for (final c in _nameCtrls.values) {
      c.dispose();
    }
    for (final c in _labelCtrls.values) {
      c.dispose();
    }
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    for (final c in _stockCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) _loadDashboardData(isBackground: true);
    });
  }

  Future<void> _loadDashboardData({bool isBackground = false}) async {
    if (!isBackground && _summary == null) setState(() => _isLoading = true);

    final results = await Future.wait([
      StoreApiService.getDashboardSummary(),
      StoreApiService.getActiveRiders(),
      StoreApiService.getPackingQueue(),
      StoreApiService.getInventory(),
      StoreApiService.getCatalogCategories(),
      StoreApiService.getRatings(),
    ]);

    if (!mounted) return;
    setState(() {
      _summary = results[0] as Map<String, dynamic>;
      _activeRiders = results[1] as List<Map<String, dynamic>>;
      _packingQueue = results[2] as List<Map<String, dynamic>>;
      _inventoryList = results[3] as List<Map<String, dynamic>>;
      for (var item in _inventoryList) {
        final vId = item["variant_id"] as String? ?? "";
        if (vId.isNotEmpty && !_nameCtrls.containsKey(vId)) {
          _nameCtrls[vId] = TextEditingController(text: item["product_name"] ?? "");
          _labelCtrls[vId] = TextEditingController(text: item["weight_label"] ?? "");
          _priceCtrls[vId] = TextEditingController(text: "${item['price'] ?? 0}");
          _stockCtrls[vId] = TextEditingController(text: "${item['stock_qty'] ?? 0}");
        }
      }
      _categories = results[4] as List<Map<String, dynamic>>;
      if (_newSelectedCategoryId == null && _categories.isNotEmpty) {
        _newSelectedCategoryId = _categories.first["id"];
      }
      _ratingsData = results[5] as Map<String, dynamic>;
      _isLoading = false;
    });
  }

  void _handleMarkPacked(String orderId) async {
    final res = await StoreApiService.markOrderPacked(orderId);
    if (!mounted) return;
    final ok = res["success"] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? (res["message"] ?? "📦 Order Marked Packed!") : "❌ ${res["message"] ?? "Mark packed failed."}"),
        backgroundColor: ok ? const Color(0xFF059669) : Colors.redAccent,
      ),
    );
    if (ok) _loadDashboardData();
  }

  void _handleAssignRider(String orderId) async {
    if (_activeRiders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No delivery riders currently online. Please wait for a rider to go on duty."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    final riderId = _selectedRiders[orderId] ?? _activeRiders.first["id"]!;
    final res = await StoreApiService.assignRider(orderId, riderId);
    if (!mounted) return;
    final ok = res["success"] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? (res["message"] ?? "🛵 Rider Assigned! Order Out for Delivery.") : "❌ ${res["message"] ?? "Rider assignment failed."}"),
        backgroundColor: ok ? const Color(0xFF7C3AED) : Colors.redAccent,
      ),
    );
    if (ok) _loadDashboardData();
  }

  void _showWeighModal(String orderId, String orderNum) {
    setState(() {
      _weighOrderId = orderId;
      _weighOrderNum = orderNum;
      _weighWeightCtrl.text = "520";
    });

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
                child: Icon(Icons.scale_rounded, color: Colors.amber.shade900, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Weigh Meat & Custom Cut", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    Text("Order #$_weighOrderNum", style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Text("DIGITAL WEIGHT SCALE OUTPUT", style: TextStyle(color: Colors.grey, fontSize: 9, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        "${_weighWeightCtrl.text} g",
                        style: const TextStyle(color: Color(0xFF34D399), fontSize: 28, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text("Enter Weighed Weight (Grams):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: _weighWeightCtrl,
                  keyboardType: TextInputType.number,
                  onChanged: (val) => setModalState(() {}),
                  decoration: InputDecoration(
                    suffixText: "g",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text("Select Cut Style:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _cutStyle,
                  items: [
                    "Curry Cut (Medium with bone)",
                    "Biryani Big Cut (Juicy pieces)",
                    "Boneless Breast Cubes",
                    "Fine Mince Keema",
                    "Soup Bones & Head Cuts"
                  ]
                      .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12))))
                      .toList(),
                  onChanged: (v) => setModalState(() => _cutStyle = v!),
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: _turmericWash,
                      activeColor: const Color(0xFF059669),
                      onChanged: (v) => setModalState(() => _turmericWash = v ?? true),
                    ),
                    const Text("Turmeric Wash", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Checkbox(
                      value: _skinless,
                      activeColor: const Color(0xFF059669),
                      onChanged: (v) => setModalState(() => _skinless = v ?? true),
                    ),
                    const Text("Skinless Cleaned", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () async {
                Navigator.pop(ctx);
                final messenger = ScaffoldMessenger.of(context);
                final w = double.tryParse(_weighWeightCtrl.text) ?? 520;
                final res = await StoreApiService.recordMeatWeight(
                  orderId: _weighOrderId!,
                  weightG: w,
                  cutType: _cutStyle,
                  turmericWash: _turmericWash,
                  skinless: _skinless,
                );
                if (!mounted) return;
                final ok = res['success'] == true;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(ok ? "🥩 Weight ${w.toInt()}g Recorded & Bag Sealed!" : "❌ ${res['message'] ?? 'Failed to record weight'}"),
                    backgroundColor: ok ? const Color(0xFF059669) : Colors.redAccent,
                  ),
                );
                if (ok) _loadDashboardData();
              },
              child: const Text("Save & Seal Bag", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showSlipModal(String orderNum, String address, String otp, List items) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("⚡ FLASH_FRESH_DELIVERY", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              const Text("Central Dark Store Hub • Pillar 84", style: TextStyle(fontSize: 10, color: Colors.grey)),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("ORDER:", style: TextStyle(fontWeight: FontWeight.bold)),
                  Text(orderNum, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF059669))),
                ],
              ),
              const SizedBox(height: 4),
              Align(alignment: Alignment.centerLeft, child: Text(address, style: const TextStyle(fontSize: 11, color: Colors.black87))),
              const Divider(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF10B981))),
                child: Column(
                  children: [
                    const Text("CUSTOMER VERIFICATION OTP PIN", style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                    Text(otp, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: 6, color: Color(0xFF064E3B))),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), minimumSize: const Size.fromHeight(42)),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.check_rounded, color: Colors.white),
                label: const Text("Done & Seal Bag", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAddProduct() async {
    if (_newProductNameCtrl.text.trim().isEmpty || _vLabelCtrl.text.trim().isEmpty || _vPriceCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill Category, Name, Weight Label, and Selling Price."), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final res = await StoreApiService.addProduct(
      categoryId: _newSelectedCategoryId ?? "cat_veg",
      name: _newProductNameCtrl.text.trim(),
      description: _newProductDescCtrl.text.trim(),
      imageUrl: _newProductImageCtrl.text.trim(),
      isSundayOnly: _newProductIsSunday,
      weightLabel: _vLabelCtrl.text.trim(),
      mrp: double.tryParse(_vMrpCtrl.text) ?? 50,
      price: double.tryParse(_vPriceCtrl.text) ?? 40,
      stockQty: int.tryParse(_vStockCtrl.text) ?? 100,
    );

    if (!mounted) return;
    final ok = res["success"] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? (res["message"] ?? "Product Added!") : "❌ ${res["message"] ?? "Add product failed."}"),
        backgroundColor: ok ? const Color(0xFF059669) : Colors.redAccent,
      ),
    );

    if (ok) {
      _newProductNameCtrl.clear();
      _newProductDescCtrl.clear();
      _newProductImageCtrl.clear();
      _loadDashboardData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          color: const Color(0xFF064E3B),
          padding: const EdgeInsets.fromLTRB(16, 36, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFBBF24), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.flash_on_rounded, color: Color(0xFF064E3B), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Flash_Fresh_Delivery",
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16),
                    ),
                    Text(
                      "Quick-Commerce Zone",
                      style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              // Action buttons matching Web Top Header
              GestureDetector(
                onTap: () => setState(() => _soundEnabled = !_soundEnabled),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF047857), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF059669))),
                  child: Row(
                    children: [
                      Icon(_soundEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: const Color(0xFFFBBF24), size: 14),
                      const SizedBox(width: 4),
                      Text(_soundEnabled ? "ON" : "OFF", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                onPressed: () => _loadDashboardData(),
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : RefreshIndicator(
              onRefresh: () => _loadDashboardData(),
              color: const Color(0xFF059669),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // KPI Overview Row matching Web Header
                    _buildKpiOverviewRow(),

                    const SizedBox(height: 14),

                    // Top 5 Horizontal Web Tab Navigation Bar
                    _buildWebTabNavigation(),

                    const SizedBox(height: 14),

                    // Sub-Header Title & Active Riders Counter
                    _buildSubHeaderTitle(),

                    const SizedBox(height: 12),

                    // Active Tab Content
                    if (_currentTab == 0) _buildPackingQueueTab(),
                    if (_currentTab == 1) _buildMeatWeighTab(),
                    if (_currentTab == 2) _buildInventoryTab(),
                    if (_currentTab == 3) _buildCatalogTab(),
                    if (_currentTab == 4) _buildRatingsTab(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildKpiOverviewRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _webKpiCard("TO PACK", "${_summary?['orders_to_pack'] ?? 0}", "Needs weighing", const Color(0xFFD97706), const Color(0xFFFFFBEB)),
          _webKpiCard("READY FOR DISPATCH", "${_summary?['orders_ready_for_pickup'] ?? 0}", "Awaiting Rider", const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
          _webKpiCard("IN TRANSIT", "${_summary?['orders_in_transit'] ?? 0}", "Out for delivery", const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
          _webKpiCard("DELIVERED TODAY", "${_summary?['orders_delivered_today'] ?? 0}", "100% on time", const Color(0xFF059669), const Color(0xFFECFDF5)),
          _webKpiCard("TODAY'S REVENUE", "₹${(_summary?['total_revenue_today'] ?? 0).toStringAsFixed(0)}", "Gross sales", const Color(0xFF1E293B), const Color(0xFFF8FAFC)),
        ],
      ),
    );
  }

  Widget _webKpiCard(String title, String count, String subtitle, Color countColor, Color bg) {
    return Container(
      width: 145,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(count, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: countColor)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildWebTabNavigation() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: Row(
          children: [
            _webTabChip(0, "Packing & Dispatch Station", Icons.shopping_bag_outlined, const Color(0xFF059669)),
            _webTabChip(1, "Sunday Meat Scale", Icons.scale_outlined, const Color(0xFFD97706)),
            _webTabChip(2, "Daily Veg & Stock Intake", Icons.inventory_2_outlined, const Color(0xFF2563EB)),
            _webTabChip(3, "Catalog Management", Icons.storefront_outlined, const Color(0xFF7C3AED)),
            _webTabChip(4, "Customer Ratings", Icons.star_outline_rounded, const Color(0xFFB45309)),
          ],
        ),
      ),
    );
  }

  Widget _webTabChip(int index, String label, IconData icon, Color accentColor) {
    final isSel = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? accentColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSel ? accentColor : Colors.transparent, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: isSel ? accentColor : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSel ? accentColor : Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  Widget _buildSubHeaderTitle() {
    String title = "Live Packing & Fleet Dispatch Queue";
    if (_currentTab == 1) title = "Sunday Meat Weighing & Cutting Precision Station";
    if (_currentTab == 2) title = "Flash Fresh Dark Store Stock Inventory";
    if (_currentTab == 3) title = "Catalog Management & Product Control";
    if (_currentTab == 4) title = "Customer Ratings & Real-Time Produce Scores";

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFFD97706), shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF1E293B)))),
            ],
          ),
        ),
        Text("${_activeRiders.length} Riders Active", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF059669))),
      ],
    );
  }

  Widget _buildPackingQueueTab() {
    if (_packingQueue.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          children: [
            Icon(Icons.inventory_rounded, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 10),
            const Text("No Orders in Packing Queue", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );
    }

    return Column(
      children: _packingQueue.map((o) {
        final items = o["items"] as List<dynamic>? ?? [];
        final isPacked = o["status"] == "PACKED";
        final orderId = o["order_id"];

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isPacked ? Colors.blue.shade200 : Colors.amber.shade300, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o["order_number"] ?? "#MYP-ORDER", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                        Text(o["delivery_address"] ?? "", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: isPacked ? Colors.blue.shade50 : Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Text(isPacked ? "✓ READY" : "⏳ WEIGH & PACK", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: isPacked ? Colors.blue.shade900 : Colors.amber.shade900)),
                  ),
                ],
              ),
              const Divider(height: 20),
              ...items.map((itm) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.check_box_rounded, size: 16, color: Color(0xFF059669)),
                        const SizedBox(width: 6),
                        Expanded(child: Text("${itm['name']} (${itm['variant']})", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                        Text("x${itm['quantity']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF059669))),
                      ],
                    ),
                  )),
              const SizedBox(height: 14),

              if (!isPacked) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.amber), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _showWeighModal(o["order_id"], o["order_number"]),
                        icon: const Icon(Icons.scale_rounded, size: 16, color: Colors.amber),
                        label: const Text("Weigh Scale", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _handleMarkPacked(o["order_id"]),
                        icon: const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                        label: const Text("Mark Packed", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: _activeRiders.isNotEmpty
                          ? DropdownButtonFormField<String>(
                              value: _selectedRiders[orderId] ?? _activeRiders.first["id"],
                              items: _activeRiders
                                  .map((r) => DropdownMenuItem(
                                        value: r["id"] as String,
                                        child: Text("${r['name']} (${r['vehicle']})", style: const TextStyle(fontSize: 11)),
                                      ))
                                  .toList(),
                              onChanged: (val) => setState(() => _selectedRiders[orderId] = val!),
                              decoration: InputDecoration(contentPadding: const EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                              child: const Text("No riders online", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      onPressed: () => _handleAssignRider(orderId),
                      icon: const Icon(Icons.two_wheeler_rounded, size: 16, color: Colors.white),
                      label: const Text("Dispatch", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => _showSlipModal(o["order_number"], o["delivery_address"], o["delivery_otp"] ?? "4921", items),
                    icon: const Icon(Icons.print_rounded, size: 16),
                    label: Text("Print Thermal Slip (PIN: ${o['delivery_otp'] ?? '4921'})", style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMeatWeighTab() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle), child: Icon(Icons.scale_rounded, color: Colors.amber.shade900, size: 20)),
              const SizedBox(width: 10),
              const Expanded(child: Text("Sunday Meat Weighing & Custom Cut Station", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
            ],
          ),
          const Divider(height: 20),
          const Text("Select Order to Weigh:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _packingQueue.any((o) => o['order_id'] == _weighOrderId) ? _weighOrderId : null,
            hint: const Text("Choose an active order...", style: TextStyle(fontSize: 12)),
            items: _packingQueue.map((o) {
              final isMeat = o['is_sunday_meat_order'] == true;
              return DropdownMenuItem<String>(
                value: o['order_id'] as String,
                child: Text(
                  "${o['order_number']}${isMeat ? ' 🥩' : ''} - ₹${o['total']}",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isMeat ? FontWeight.bold : FontWeight.normal,
                    color: isMeat ? const Color(0xFFD97706) : Colors.black87,
                  ),
                ),
              );
            }).toList(),
            onChanged: (val) {
              setState(() => _weighOrderId = val);
            },
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(height: 12),
          const Text("Enter Weight (Grams):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          TextField(
            controller: _weighWeightCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF059669)),
            decoration: InputDecoration(suffixText: "g", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () async {
                final w = double.tryParse(_weighWeightCtrl.text) ?? 520;
                if (_weighOrderId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Please select an order from the dropdown before recording weight."),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  return;
                }
                final targetOrderId = _weighOrderId!;
                final res = await StoreApiService.recordMeatWeight(
                  orderId: targetOrderId,
                  weightG: w,
                  cutType: _cutStyle,
                  turmericWash: _turmericWash,
                  skinless: _skinless,
                );
                if (!mounted) return;
                final ok = res['success'] == true;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? "🥩 Verified Weight ${w.toInt()}g Sealed for Order!" : "❌ ${res['message'] ?? 'Failed to record weight'}"),
                    backgroundColor: ok ? const Color(0xFFD97706) : Colors.redAccent,
                  ),
                );
                if (ok) _loadDashboardData();
              },
              icon: const Icon(Icons.verified_rounded, size: 18, color: Colors.white),
              label: const Text("Save Net Weight & Seal Bag", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    return Container(
      padding: const EdgeInsets.all(16),
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
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Flash Fresh Dark Store Stock Inventory", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                    Text("Update stock intake when fresh farm trucks arrive.", style: TextStyle(fontSize: 10, color: Colors.black54)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _loadDashboardData(),
                icon: const Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF059669)),
                tooltip: "Refresh Stock",
              ),
            ],
          ),
          const Divider(height: 20),

          ..._inventoryList.map((item) {
            final pId = item["product_id"] ?? "";
            final vId = item["variant_id"] ?? "";
            final isSunday = item["is_sunday_only"] ?? false;

            _nameCtrls.putIfAbsent(vId, () => TextEditingController(text: item["product_name"] ?? ""));
            _labelCtrls.putIfAbsent(vId, () => TextEditingController(text: item["weight_label"] ?? ""));
            _priceCtrls.putIfAbsent(vId, () => TextEditingController(text: "${item['price'] ?? 0}"));
            _stockCtrls.putIfAbsent(vId, () => TextEditingController(text: "${item['stock_qty'] ?? 0}"));

            final nameCtrl = _nameCtrls[vId]!;
            final labelCtrl = _labelCtrls[vId]!;
            final priceCtrl = _priceCtrls[vId]!;
            final qtyCtrl = _stockCtrls[vId]!;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
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
                          color: isSunday ? Colors.amber.shade100 : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isSunday ? "🍗 SUNDAY MEAT" : "🥬 DAILY VEG",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: isSunday ? Colors.amber.shade900 : const Color(0xFF047857),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final q = int.tryParse(qtyCtrl.text) ?? (item['stock_qty'] as int);
                              final res = await StoreApiService.updateStock(vId, q);
                              if (!mounted) return;
                              final ok = res["success"] == true;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? "📦 ${res["message"] ?? "Stock Updated!"}" : "❌ ${res["message"] ?? "Stock update failed."}"),
                                  backgroundColor: ok ? const Color(0xFF059669) : Colors.redAccent,
                                ),
                              );
                              if (ok) _loadDashboardData();
                            },
                            icon: const Icon(Icons.inventory_2_rounded, size: 12),
                            label: const Text("Stock", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C3AED),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              final name = nameCtrl.text.trim();
                              final label = labelCtrl.text.trim();
                              final price = double.tryParse(priceCtrl.text) ?? (item['price'] as num).toDouble();
                              final stock = int.tryParse(qtyCtrl.text) ?? (item['stock_qty'] as int);

                              final res = await StoreApiService.updateProductDetail(
                                productId: pId,
                                variantId: vId,
                                productName: name,
                                weightLabel: label,
                                price: price,
                                stockQty: stock,
                              );
                              if (!mounted) return;
                              // CRITICAL: only show success if the backend actually saved.
                              // Previously this always said "✏️ Details Saved!" even when
                              // the request failed — which is why price updates didn't reach
                              // the customer app (the save silently failed).
                              final ok = res["success"] == true;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok ? "✏️ ${res["message"] ?? "Details Saved!"}" : "❌ ${res["message"] ?? "Save failed. Please retry."}"),
                                  backgroundColor: ok ? const Color(0xFF7C3AED) : Colors.redAccent,
                                ),
                              );
                              if (ok) _loadDashboardData();
                            },
                            icon: const Icon(Icons.edit_rounded, size: 12),
                            label: const Text("Save All", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      labelText: "Product Name",
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: labelCtrl,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText: "Weight",
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                          decoration: InputDecoration(
                            labelText: "Price (₹)",
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                          decoration: InputDecoration(
                            labelText: "Stock",
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCatalogTab() {
    return Column(
      children: [
        // Add Product Form
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.purple.shade200)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.add_circle_rounded, color: Colors.purple.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text("Add New Product to Catalog", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.purple.shade900)),
                ],
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _newSelectedCategoryId,
                items: _categories.map((c) => DropdownMenuItem(value: c["id"] as String, child: Text(c["name"] as String, style: const TextStyle(fontSize: 12)))).toList(),
                onChanged: (v) => setState(() => _newSelectedCategoryId = v),
                decoration: InputDecoration(labelText: "Category", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 10),

              TextField(controller: _newProductNameCtrl, decoration: InputDecoration(labelText: "Product Name", hintText: "e.g. Fresh Palak", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 10),

              TextField(controller: _newProductDescCtrl, decoration: InputDecoration(labelText: "Description", hintText: "e.g. Crisp baby leaves", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 10),

              TextField(controller: _newProductImageCtrl, decoration: InputDecoration(labelText: "ImageKit URL", hintText: "https://ik.imagekit.io/...", border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 10),

              Row(
                children: [
                  Checkbox(value: _newProductIsSunday, onChanged: (v) => setState(() => _newProductIsSunday = v ?? false)),
                  const Text("Sunday Only (Fresh Meat/Fish)", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(child: TextField(controller: _vLabelCtrl, decoration: const InputDecoration(labelText: "Weight Label", hintText: "1kg", border: OutlineInputBorder()))),
                  const SizedBox(width: 6),
                  Expanded(child: TextField(controller: _vPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Selling Price", hintText: "40", border: OutlineInputBorder()))),
                  const SizedBox(width: 6),
                  Expanded(child: TextField(controller: _vStockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Stock Units", hintText: "100", border: OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple.shade700, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _handleAddProduct,
                  icon: const Icon(Icons.add_rounded, color: Colors.white),
                  label: const Text("Add to Catalog Immediately", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatingsTab() {
    final reviews = _ratingsData?["recent_reviews"] as List<dynamic>? ?? [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Customer Ratings & Reviews", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text("${_ratingsData?['avg_rating'] ?? 4.9} ⭐", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFB45309))),
              ),
            ],
          ),
          const Divider(height: 20),
          if (reviews.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text("No reviews yet today.", style: TextStyle(color: Colors.grey))),

          ...reviews.map((r) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(r["order_number"] ?? "#ORDER", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text("⭐ ${r['rider_rating']} Stars", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 11)),
                      ],
                    ),
                    Text('"${r['review']}"', style: TextStyle(fontSize: 12, color: Colors.grey.shade800)),
                    Text(r["date"] ?? "", style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
