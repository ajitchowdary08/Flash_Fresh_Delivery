import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';
import 'cashfree_web_view.dart';

class PaymentDialog extends StatefulWidget {
  final double amount;
  final String orderId;
  final String gatewayOrderId;
  final Function(bool success, String paymentMethod) onPaymentComplete;

  const PaymentDialog({
    super.key,
    required this.amount,
    required this.orderId,
    required this.gatewayOrderId,
    required this.onPaymentComplete,
  });

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  String _selectedMethod = "upi_gpay";
  bool _isProcessing = false;

  final List<Map<String, dynamic>> _methods = [
    {
      "id": "pay_later",
      "name": "⚡ Flash Pay Later (Monthly Bill)",
      "subtitle": "Order now, pay bill at end of month (Limit: ₹5,000)",
      "icon": Icons.event_note_rounded
    },
    {
      "id": "upi_gpay",
      "name": "Google Pay UPI",
      "subtitle": "Fastest 10-Second Checkout",
      "icon": Icons.account_balance_wallet_rounded
    },
    {
      "id": "upi_phonepe",
      "name": "PhonePe UPI",
      "subtitle": "Pay via linked bank account",
      "icon": Icons.phone_android_rounded
    },
    {
      "id": "upi_paytm",
      "name": "Paytm UPI",
      "subtitle": "Instant UPI transfer",
      "icon": Icons.payment_rounded
    },
    {
      "id": "cod",
      "name": "Cash / UPI on Delivery",
      "subtitle": "Pay cash/UPI at doorstep",
      "icon": Icons.money_rounded
    },
  ];

  void _showCashfreeTestDetailsModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          children: [
            Icon(Icons.developer_mode_rounded, color: Color(0xFF059669)),
            SizedBox(width: 8),
            Text("Cashfree Sandbox Test Data", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF111827))),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("1. Test UPI VPA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669))),
              const Text("• VPA: testsuccess@gocash (Success)\n• VPA: testfailure@gocash (Failed)", style: TextStyle(fontSize: 12, color: Colors.black87)),
              const SizedBox(height: 12),
              const Text("2. Test Visa Debit / Credit Cards", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669))),
              const Text("• Card 1: 4706 1312 1121 2123\n• Card 2: 4576 2389 1277 1450\n• Expiry: 03/2028 | CVV: 123 | Name: Test\n• Test Card OTP: 111000", style: TextStyle(fontSize: 12, color: Colors.black87)),
              const SizedBox(height: 12),
              const Text("3. Test Pay Later & Cardless EMI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF059669))),
              const Text("• Mobile: 8714268343\n• OTP: 777777 | PAN 4 digits: 1234", style: TextStyle(fontSize: 12, color: Colors.black87)),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Got It", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openCashfreePaymentGatewayWindow() {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashfreeWebViewScreen(
          paymentSessionId: widget.gatewayOrderId,
          orderId: widget.orderId,
          orderNumber: widget.orderId.length > 8 ? "MYP-${widget.orderId.substring(widget.orderId.length - 4)}" : widget.orderId,
          grandTotal: widget.amount,
          onPaymentComplete: (result) {
            widget.onPaymentComplete(result.paid, "CASHFREE");
          },
        ),
      ),
    );
  }

  void _handlePay() async {
    if (_selectedMethod == "cod" || _selectedMethod == "pay_later") {
      setState(() => _isProcessing = true);

      await ApiService.verifyPayment(
        orderId: widget.orderId,
        razorpayOrderId: widget.gatewayOrderId,
        razorpayPaymentId: "pay_${DateTime.now().millisecondsSinceEpoch}",
        razorpaySignature: "sig_${DateTime.now().millisecondsSinceEpoch}",
        paymentMethod: _selectedMethod,
      );

      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      setState(() => _isProcessing = false);
      Navigator.pop(context);
      LiquidToast.show(
        context,
        message: "💳 Order Placed! Sent to Dark Store",
        icon: Icons.check_circle_rounded,
        accentColor: const Color(0xFF059669),
      );
      widget.onPaymentComplete(true, _selectedMethod);
    } else {
      _openCashfreePaymentGatewayWindow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: GlassCard(
        blur: 24,
        opacity: 0.95,
        borderRadius: 28,
        backgroundColor: Colors.white,
        borderColor: Colors.grey.shade300,
        padding: const EdgeInsets.all(22.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shield_rounded, color: Color(0xFF059669), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Cashfree Sandbox Checkout",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF111827)),
                      ),
                      Text(
                        "256-Bit Encrypted UPI & Card Payments",
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Cashfree Test Sandbox Info Banner
            InkWell(
              onTap: _showCashfreeTestDetailsModal,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF059669).withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.developer_mode_rounded, color: Color(0xFF059669), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "🧪 Cashfree Sandbox Active (Tap for Test VPA & Cards)",
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Color(0xFF059669), size: 18),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Grand Total to Pay:", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111827))),
                  Text(
                    "₹${widget.amount.toStringAsFixed(0)}",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Select Payment Method:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF111827)),
            ),
            const SizedBox(height: 10),

            ..._methods.map((m) {
              final isChosen = _selectedMethod == m['id'];
              return InkWell(
                onTap: () => setState(() => _selectedMethod = m['id']),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isChosen ? const Color(0xFF059669).withOpacity(0.12) : Colors.white,
                    border: Border.all(
                      color: isChosen ? const Color(0xFF059669) : Colors.grey.shade300,
                      width: isChosen ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(m['icon'] as IconData, color: isChosen ? const Color(0xFF059669) : Colors.black54),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isChosen ? const Color(0xFF059669) : const Color(0xFF111827),
                              ),
                            ),
                            Text(
                              m['subtitle'],
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isChosen ? const Color(0xFF059669) : Colors.grey.shade400,
                            width: 2,
                          ),
                        ),
                        child: isChosen
                            ? Center(
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),

            LiquidButton(
              label: "Pay ₹${widget.amount.toStringAsFixed(0)}",
              isLoading: _isProcessing,
              onPressed: _handlePay,
            ),
          ],
        ),
      ),
    );
  }
}
