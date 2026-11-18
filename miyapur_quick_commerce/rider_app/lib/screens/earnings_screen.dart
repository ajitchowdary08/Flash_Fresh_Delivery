import 'package:flutter/material.dart';
import '../services/rider_api_service.dart';

class EarningsScreen extends StatefulWidget {
  final double todayEarnings;
  final int completedTrips;

  const EarningsScreen({
    super.key,
    required this.todayEarnings,
    required this.completedTrips,
  });

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic>? _reviewsData;
  bool _isLoadingReviews = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchReviews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _fetchReviews() async {
    final data = await RiderApiService.getRiderReviews();
    if (!mounted) return;
    setState(() {
      _reviewsData = data;
      _isLoadingReviews = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1118),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161822),
        elevation: 0,
        title: const Text(
          "Earnings & Performance",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFC8019),
          labelColor: const Color(0xFFFC8019),
          unselectedLabelColor: Colors.white60,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: "Earnings & Wallet"),
            Tab(text: "Ratings & Reviews"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEarningsTab(),
          _buildReviewsTab(),
        ],
      ),
    );
  }

  Widget _buildEarningsTab() {
    final basePay = widget.completedTrips * 35.0;
    final bonus = (widget.todayEarnings - basePay).clamp(0.0, 500.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Hero Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFC8019), Color(0xFFD65E00)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFC8019).withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "TODAY'S TOTAL PAYOUT",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "₹${widget.todayEarnings.toStringAsFixed(0)}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "${widget.completedTrips} Trips Done",
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "⚡ Central Dark Store Fleet",
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Cash in Hand (Floating Cash) Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF191B26),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFFFFB300), size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Cash in Hand (Floating COD)",
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        "₹490 collected • Deposit limit: ₹1,500 at Hub",
                        style: TextStyle(fontSize: 11, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C853).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    "SAFE",
                    style: TextStyle(color: Color(0xFF00C853), fontSize: 10, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Daily Target Milestone
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF191B26),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Swiggy Instamart Daily Milestones",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                    ),
                    Icon(Icons.military_tech_rounded, color: Color(0xFFFFB300), size: 20),
                  ],
                ),
                const Divider(color: Colors.white10, height: 22),
                _milestoneTier("Tier 1: 5 Deliveries", "+₹50 Bonus", true),
                const SizedBox(height: 10),
                _milestoneTier("Tier 2: 10 Deliveries", "+₹120 Bonus", widget.completedTrips >= 10),
                const SizedBox(height: 10),
                _milestoneTier("Tier 3: 15 Deliveries", "+₹200 Bonus", widget.completedTrips >= 15),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Payout Breakdown Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF191B26),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Earnings Breakdown",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                const Divider(color: Colors.white10, height: 22),
                _breakdownRow("Base Delivery Pay (₹35 / trip)", "₹${basePay.toStringAsFixed(0)}"),
                _breakdownRow("Distance Surge Bonus (>3 KM)", "₹${bonus.toStringAsFixed(0)}"),
                _breakdownRow("Sunday Meat Order Incentive", "₹50 (Active)"),
                _breakdownRow("Customer Doorstep Tips", "₹20"),
                const Divider(color: Colors.white10, height: 22),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Direct Bank Transfer:",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                    Text(
                      "Every Tuesday to Bank A/c",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00C853)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _milestoneTier(String title, String reward, bool isAchieved) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              isAchieved ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isAchieved ? const Color(0xFF00C853) : Colors.white30,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: isAchieved ? Colors.white : Colors.white60,
                fontWeight: isAchieved ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        Text(
          reward,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: isAchieved ? const Color(0xFFFFB300) : Colors.white38,
          ),
        ),
      ],
    );
  }

  Widget _breakdownRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildReviewsTab() {
    if (_isLoadingReviews) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFC8019)),
      );
    }

    final avgRating = (_reviewsData?['avg_rating'] as num?)?.toDouble() ?? 4.9;
    final totalRatings = _reviewsData?['total_ratings'] ?? 128;
    final reviews = (_reviewsData?['recent_reviews'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Overall Rating Hero
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF191B26),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFB300).withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 36),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "$avgRating",
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      const Text(" / 5.0", style: TextStyle(color: Colors.white60, fontSize: 14)),
                    ],
                  ),
                  Text(
                    "Based on $totalRatings customer ratings",
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        const Text(
          "Recent Customer Feedback",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 10),

        ...reviews.map((r) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF191B26),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: List.generate(
                          (r['rider_rating'] as num?)?.toInt() ?? 5,
                          (_) => const Icon(Icons.star_rounded, color: Color(0xFFFFB300), size: 14),
                        ),
                      ),
                      Text(
                        r['date'] ?? 'Today',
                        style: const TextStyle(fontSize: 10, color: Colors.white60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "\"${r['review'] ?? 'Great delivery!'}\"",
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r['order_number'] ?? '',
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}
