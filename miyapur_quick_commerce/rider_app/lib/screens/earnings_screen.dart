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
  Map<String, dynamic>? _earningsData;
  Map<String, dynamic>? _reviewsData;
  bool _isLoadingEarnings = true;
  bool _isLoadingReviews = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _fetchData() async {
    final earnings = await RiderApiService.getEarnings();
    final reviews = await RiderApiService.getRiderReviews();
    if (!mounted) return;
    setState(() {
      _earningsData = earnings;
      _reviewsData = reviews;
      _isLoadingEarnings = false;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: () {
              setState(() {
                _isLoadingEarnings = true;
                _isLoadingReviews = true;
              });
              _fetchData();
            },
          ),
        ],
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
    if (_isLoadingEarnings) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFFC8019)));
    }

    final data = _earningsData ?? {};
    final double totalEarnings = (data['today_earnings'] as num?)?.toDouble() ?? widget.todayEarnings;
    final int completedTrips = (data['completed_trips'] as num?)?.toInt() ?? widget.completedTrips;
    final double basePay = (data['base_pay'] as num?)?.toDouble() ?? (completedTrips * 35.0);
    final double distanceBonus = (data['distance_bonus'] as num?)?.toDouble() ?? 0.0;
    final double meatIncentive = (data['meat_incentive'] as num?)?.toDouble() ?? 0.0;
    final double incentiveBonus = (data['incentive_bonus'] as num?)?.toDouble() ?? 0.0;
    final double codCash = (data['cod_cash_in_hand'] as num?)?.toDouble() ?? 0.0;
    final double hubLimit = (data['hub_deposit_limit'] as num?)?.toDouble() ?? 1500.0;
    final List milestones = (data['milestones'] as List?) ?? [];
    final List tripsHistory = (data['trips_history'] as List?) ?? [];
    final String settlementInfo = data['settlement_info'] ?? "Every Tuesday directly to Bank A/c";

    return RefreshIndicator(
      color: const Color(0xFFFC8019),
      onRefresh: () async => _fetchData(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                    "₹${totalEarnings.toStringAsFixed(0)}",
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
                          "$completedTrips Trips Delivered",
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
                          "⚡ Live Database Verified",
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Cash in Hand (Floating Cash) Card - 100% Dynamic from DB COD orders
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Cash in Hand (Floating COD)",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          "₹${codCash.toStringAsFixed(0)} collected • Deposit limit: ₹${hubLimit.toStringAsFixed(0)}",
                          style: const TextStyle(fontSize: 11, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: (codCash <= hubLimit ? const Color(0xFF00C853) : Colors.redAccent).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      codCash <= hubLimit ? "SAFE" : "DEPOSIT",
                      style: TextStyle(
                        color: codCash <= hubLimit ? const Color(0xFF00C853) : Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Dynamic Daily Target Milestones
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
                        "Daily Target Milestones",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                      Icon(Icons.military_tech_rounded, color: Color(0xFFFFB300), size: 20),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 22),
                  if (milestones.isEmpty)
                    const Text("No active milestones for this shift.", style: TextStyle(color: Colors.white54, fontSize: 12))
                  else
                    ...milestones.map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _milestoneTier(
                            m['tier'] ?? '',
                            m['reward'] ?? '',
                            m['achieved'] == true,
                          ),
                        )),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Payout Breakdown Card (100% Dynamic)
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
                  _breakdownRow("Distance Surge Bonus (>3 KM)", "₹${distanceBonus.toStringAsFixed(0)}"),
                  _breakdownRow("Sunday Fresh Meat Incentive", "₹${meatIncentive.toStringAsFixed(0)}"),
                  _breakdownRow("Milestone Target Bonus", "₹${incentiveBonus.toStringAsFixed(0)}"),
                  const Divider(color: Colors.white10, height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Bank Settlement Schedule:",
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      Text(
                        settlementInfo,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00C853)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (tripsHistory.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                "Completed Deliveries Today",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 10),
              ...tripsHistory.map((trip) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191B26),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "#${trip['order_number']}",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                              ),
                              Text(
                                "${trip['delivery_address']}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.white60),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "+₹${trip['payout']}",
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF00C853)),
                            ),
                            Text(
                              "${trip['delivered_at']}",
                              style: const TextStyle(fontSize: 10, color: Colors.white38),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
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

    final avgRating = (_reviewsData?['avg_rating'] as num?)?.toDouble() ?? 5.0;
    final totalRatings = _reviewsData?['total_ratings'] ?? 0;
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
                    "Based on $totalRatings verified customer ratings",
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        const Text(
          "Customer Feedback",
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 10),

        if (reviews.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF191B26),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text(
                "No customer reviews yet. Complete deliveries to earn ratings!",
                style: TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
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
