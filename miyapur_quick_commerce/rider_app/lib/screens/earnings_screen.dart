import 'package:flutter/material.dart';

class EarningsScreen extends StatelessWidget {
  final double todayEarnings;
  final int completedTrips;

  const EarningsScreen({
    super.key,
    required this.todayEarnings,
    required this.completedTrips,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("Earnings & Wallet", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.green.shade800,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Total Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade800, Colors.green.shade600],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Today's Total Earnings", style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    "₹${todayEarnings.toStringAsFixed(0)}",
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(8)),
                        child: Text(
                          "$completedTrips Trips Completed",
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(8)),
                        child: const Text(
                          "⚡ Central Zone",
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Payout breakdown
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Earnings Breakdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const Divider(height: 20),
                    _breakdownRow("Base Delivery Pay", "₹${(completedTrips * 35).toStringAsFixed(0)}"),
                    _breakdownRow("Distance Bonus (>3 KM)", "₹${(todayEarnings - (completedTrips * 35)).toStringAsFixed(0)}"),
                    _breakdownRow("Sunday Meat Rush Incentive", "₹50 (Qualified)"),
                    _breakdownRow("Customer Tips", "₹20"),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Weekly Transfer:", style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          "Every Tuesday to Bank",
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Live Customer Ratings & Feedback Card
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Customer Ratings & Feedback",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                              SizedBox(width: 4),
                              Text(
                                "4.9 ⭐",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    _buildReviewTile(
                      orderNum: "Order #MYP-20261118-2313",
                      stars: 5,
                      comment: "Super fast 10-minute delivery & polite behavior!",
                      time: "Today, 10:15 AM",
                    ),
                    const SizedBox(height: 10),
                    _buildReviewTile(
                      orderNum: "Order #MYP-20261118-1904",
                      stars: 5,
                      comment: "Produce was fresh & delivered safely on time.",
                      time: "Yesterday, 06:40 PM",
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewTile({
    required String orderNum,
    required int stars,
    required String comment,
    required String time,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                orderNum,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
              ),
              Row(
                children: List.generate(
                  stars,
                  (_) => const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            comment,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 2),
          Text(
            time,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _breakdownRow(String title, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Text(val, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
