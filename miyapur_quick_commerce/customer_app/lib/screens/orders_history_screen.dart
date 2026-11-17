import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import 'order_tracking_screen.dart';

class OrdersHistoryScreen extends StatefulWidget {
  final String userId;
  final Function(List<CartItemModel> reorderedItems) onReorder;

  const OrdersHistoryScreen({
    super.key,
    required this.userId,
    required this.onReorder,
  });

  @override
  State<OrdersHistoryScreen> createState() => _OrdersHistoryScreenState();
}

class _OrdersHistoryScreenState extends State<OrdersHistoryScreen> {
  List<OrderHistoryModel> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  void _fetchHistory() async {
    setState(() => _isLoading = true);
    final history = await ApiService.getOrderHistory(widget.userId);
    if (!mounted) return;
    setState(() {
      _orders = history;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text("My Orders", style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF111827))),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
            : RefreshIndicator(
                color: const Color(0xFF059669),
                onRefresh: () async {
                  _fetchHistory();
                },
                child: _orders.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                          Center(
                            child: GlassCard(
                              blur: 20,
                              opacity: 0.9,
                              borderRadius: 28,
                              padding: const EdgeInsets.all(28),
                              margin: const EdgeInsets.symmetric(horizontal: 24),
                              borderColor: Colors.grey.shade200,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shopping_bag_outlined, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  const Text("No past orders yet", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF111827))),
                                  const SizedBox(height: 6),
                                  Text("Your 10-minute delivery orders will appear here", style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: _orders.length,
                        itemBuilder: (context, index) {
                          final order = _orders[index];
                          final isLive = order.status != "DELIVERED" && order.status != "CANCELLED";

                          return GlassCard(
                            blur: 16,
                            opacity: 0.9,
                            borderRadius: 22,
                            margin: const EdgeInsets.only(bottom: 12),
                            borderColor: Colors.grey.shade200,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Order #${order.orderNumber}",
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827)),
                                        ),
                                        Text(
                                          order.createdAt,
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isLive ? const Color(0xFF059669).withOpacity(0.12) : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        order.status,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: isLive ? const Color(0xFF059669) : Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20, color: Colors.black12),

                                ...order.items.map((item) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3.0),
                                      child: Row(
                                        children: [
                                          const Text(
                                            "•",
                                            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              "${item.name} (${item.variant}) x${item.quantity}",
                                              style: const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                                            ),
                                          ),
                                          Text(
                                            "₹${item.totalPrice.toStringAsFixed(0)}",
                                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF111827)),
                                          )
                                        ],
                                      ),
                                    )),

                                const Divider(height: 20, color: Colors.black12),

                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text("Grand Total", style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                        Text(
                                          "₹${order.grandTotal.toStringAsFixed(0)}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 18,
                                            color: Color(0xFF059669),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isLive)
                                      ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => OrderTrackingScreen(
                                                orderId: order.orderId,
                                                orderNumber: order.orderNumber,
                                                grandTotal: order.grandTotal,
                                                etaMinutes: order.deliveryEtaMins,
                                                deliveryAddress: order.deliveryAddress,
                                                destinationLatitude: order.latitude,
                                                destinationLongitude: order.longitude,
                                                items: const [],
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.flash_on_rounded, size: 14, color: Colors.white),
                                        label: const Text("Track Live", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF059669),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      )
                                    else
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                            onPressed: () => _showRatingDialog(order.orderId),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: () {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text("Reordered items added to basket!")),
                                              );
                                            },
                                            icon: const Icon(Icons.replay_rounded, size: 14, color: Color(0xFF059669)),
                                            label: const Text("Repeat Order", style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 12)),
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(color: Color(0xFF059669)),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }

  void _showRatingDialog(String orderId) {
    int productRating = 5;
    int riderRating = 5;
    final reviewCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Column(
            children: [
              Icon(Icons.stars_rounded, color: Color(0xFFD97706), size: 48),
              SizedBox(height: 8),
              Text("Rate Delivery & Freshness", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF111827))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Product & Vegetable Freshness", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF111827))),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (idx) {
                    final star = idx + 1;
                    return IconButton(
                      icon: Icon(
                        star <= productRating ? Icons.star_rounded : Icons.star_border_rounded,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () => setModalState(() => productRating = star),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                const Text("Rider Speed & Behavior", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF111827))),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (idx) {
                    final star = idx + 1;
                    return IconButton(
                      icon: Icon(
                        star <= riderRating ? Icons.star_rounded : Icons.star_border_rounded,
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
                  style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
                  decoration: InputDecoration(
                    hintText: "Write a comment (optional)...",
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Skip", style: TextStyle(color: Colors.black54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await ApiService.rateOrder(orderId, productRating, reviewCtrl.text.trim());
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Thank you for your rating & feedback! ⭐"),
                    backgroundColor: Color(0xFF059669),
                  ),
                );
              },
              child: const Text("Submit Rating", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
