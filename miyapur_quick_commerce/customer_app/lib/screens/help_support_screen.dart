import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';

class HelpSupportScreen extends StatefulWidget {
  final String? userId;
  final String? phone;
  final String? orderId;

  const HelpSupportScreen({
    super.key,
    this.userId,
    this.phone,
    this.orderId,
  });

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _supportData;
  final TextEditingController _issueDescController = TextEditingController();
  String _selectedIssueCategory = "Order & Delivery";
  bool _isSubmittingTicket = false;

  final List<String> _issueCategories = [
    "Order & Delivery",
    "Missing / Damaged Items",
    "Refund / Payment Query",
    "Quality Issue",
    "Monthly Khata Credit",
    "Other Query",
  ];

  @override
  void initState() {
    super.initState();
    _loadSupportData();
  }

  @override
  void dispose() {
    _issueDescController.dispose();
    super.dispose();
  }

  void _loadSupportData() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getFaqs();
    if (!mounted) return;
    setState(() {
      _supportData = res;
      _isLoading = false;
    });
  }

  void _launchWhatsApp(String numStr) async {
    final cleanNum = numStr.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse("https://wa.me/$cleanNum?text=Hi%20Flash%20Fresh%20Support,%20I%20need%20help%20with%20my%20order.");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      LiquidToast.show(
        context,
        message: "Cannot open WhatsApp. Contact: +91 90000 11111",
        icon: Icons.chat_rounded,
        accentColor: const Color(0xFF059669),
      );
    }
  }

  void _launchPhoneCall(String phoneNum) async {
    final uri = Uri.parse("tel:${phoneNum.replaceAll(' ', '')}");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      LiquidToast.show(
        context,
        message: "Contact Support: +91 90000 11111",
        icon: Icons.phone_rounded,
        accentColor: const Color(0xFF059669),
      );
    }
  }

  void _submitTicket() async {
    final desc = _issueDescController.text.trim();
    if (desc.isEmpty) {
      LiquidToast.show(
        context,
        message: "Please describe your issue before submitting",
        icon: Icons.warning_amber_rounded,
        accentColor: Colors.orange.shade800,
      );
      return;
    }

    setState(() => _isSubmittingTicket = true);

    final res = await ApiService.createSupportTicket(
      userId: widget.userId ?? "guest_user",
      phone: widget.phone ?? "9000011111",
      orderId: widget.orderId,
      issueCategory: _selectedIssueCategory,
      description: desc,
    );

    if (!mounted) return;
    setState(() => _isSubmittingTicket = false);

    _issueDescController.clear();
    Navigator.pop(context); // Close modal sheet

    LiquidToast.show(
      context,
      message: res["message"] ?? "Ticket submitted! Callback in 5 mins.",
      icon: Icons.check_circle_rounded,
      accentColor: const Color(0xFF059669),
    );
  }

  void _showTicketModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Raise Support Ticket",
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    color: Color(0xFF111827),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.black54),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              "Select Category",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _issueCategories.map((cat) {
                final isSelected = _selectedIssueCategory == cat;
                return ChoiceChip(
                  label: Text(cat),
                  selected: isSelected,
                  selectedColor: const Color(0xFF059669),
                  backgroundColor: Colors.grey.shade100,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 12,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedIssueCategory = cat);
                    (ctx as Element).markNeedsBuild();
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              "Describe Issue",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF374151)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _issueDescController,
              maxLines: 3,
              style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
              decoration: InputDecoration(
                hintText: "Enter details (e.g. Tomatoes damaged, rider delayed...)",
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                fillColor: Colors.grey.shade50,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
            ),
            const SizedBox(height: 20),
            LiquidButton(
              label: "Submit Ticket & Get Callback",
              icon: Icons.headset_mic_rounded,
              isLoading: _isSubmittingTicket,
              onPressed: _submitTicket,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contact = _supportData?["support_contact"] as Map<String, dynamic>?;

    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF082219), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF059669).withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                "24x7 Help & Support",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quick Action Banner
                    GlassCard(
                      blur: 20,
                      opacity: 0.95,
                      borderRadius: 24,
                      padding: const EdgeInsets.all(18),
                      borderColor: Colors.grey.shade200,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669).withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.support_agent_rounded, size: 28, color: Color(0xFF059669)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "How can we help you?",
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF111827)),
                                    ),
                                    Text(
                                      contact?["operating_hours"] ?? "24x7 Express Support Available",
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _launchWhatsApp(contact?["whatsapp"] ?? "919000011111"),
                                  icon: const Icon(Icons.chat_rounded, size: 18),
                                  label: const Text("WhatsApp", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF25D366),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _launchPhoneCall(contact?["phone"] ?? "+91 90000 11111"),
                                  icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                                  label: const Text("Call Support", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF059669),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Raise Ticket Card
                    GlassCard(
                      blur: 16,
                      opacity: 0.95,
                      borderRadius: 24,
                      padding: const EdgeInsets.all(16),
                      borderColor: Colors.grey.shade200,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.confirmation_number_rounded, color: Colors.amber.shade900, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Have an issue with an order?",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF111827)),
                                ),
                                Text(
                                  "Submit ticket to get instant 5-min callback",
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _showTicketModal,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: const Text("Raise Ticket", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      "Frequently Asked Questions",
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Color(0xFF111827),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // FAQ Categories & Accordions
                    ...?((_supportData?["faq_categories"] as List<dynamic>?)?.map((cat) {
                      final title = cat["title"] ?? "FAQs";
                      final faqs = cat["faqs"] as List<dynamic>? ?? [];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: GlassCard(
                          blur: 16,
                          opacity: 0.95,
                          borderRadius: 20,
                          padding: EdgeInsets.zero,
                          borderColor: Colors.grey.shade200,
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.help_outline_rounded, color: Color(0xFF059669), size: 20),
                            ),
                            title: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Color(0xFF111827),
                              ),
                            ),
                            children: faqs.map((f) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                                decoration: BoxDecoration(
                                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Q: ${f['question']}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFF059669),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      f["answer"] ?? "",
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    }).toList()),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}
