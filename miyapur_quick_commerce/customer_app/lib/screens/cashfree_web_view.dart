import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/api_service.dart';

/// Cashfree drop-in checkout screen.
///
/// After the Cashfree drop-in closes — whether the user completed the payment,
/// selected "FAILED" status in the sandbox, dropped off, or closed the page —
/// this screen calls the backend's server-authoritative `POST /payments/cashfree/verify`
/// endpoint. The backend re-fetches the order status directly from Cashfree and
/// is the ONLY source of truth for whether the payment succeeded.
///
/// The result is passed back through [onPaymentComplete] as a [CashfreeResult],
/// which carries:
///   - paid          : true only when the backend confirms the payment is PAID.
///   - failed        : true when the backend reports FAILED / EXPIRED / USER_DROPPED.
///   - failureReason : a human-readable message to show the customer.
///   - gatewayStatus : the raw Cashfree order_status (PAID / FAILED / ACTIVE / ...).
class CashfreeWebViewScreen extends StatefulWidget {
  final String? paymentSessionId;
  final String orderId;
  final String orderNumber;
  final double grandTotal;
  final void Function(CashfreeResult result) onPaymentComplete;

  const CashfreeWebViewScreen({
    super.key,
    this.paymentSessionId,
    required this.orderId,
    required this.orderNumber,
    required this.grandTotal,
    required this.onPaymentComplete,
  });

  @override
  State<CashfreeWebViewScreen> createState() => _CashfreeWebViewScreenState();
}

/// Typed result returned by the Cashfree checkout screen.
class CashfreeResult {
  final bool paid;
  final bool failed;
  final String? failureReason;
  final String gatewayStatus;
  final String paymentMethod;

  const CashfreeResult({
    required this.paid,
    required this.failed,
    this.failureReason,
    this.gatewayStatus = "UNKNOWN",
    this.paymentMethod = "CASHFREE",
  });
}

class _CashfreeWebViewScreenState extends State<CashfreeWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0.0;
  bool _resolved = false; // guards against double-calling onPaymentComplete

  @override
  void initState() {
    super.initState();
    final baseUrl = "${ApiService.baseUrl}/payments/cashfree-checkout/${widget.orderId}";
    final checkoutUrl = (widget.paymentSessionId != null && widget.paymentSessionId!.isNotEmpty)
        ? "$baseUrl?session_id=${widget.paymentSessionId}"
        : baseUrl;

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress / 100.0;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            // Cashfree redirects back to the app on completion. Catch every known
            // redirect shape (success, failure, user-dropped) and verify server-side.
            final lower = url.toLowerCase();
            if (lower.contains("payment-complete") ||
                lower.contains("/payments/cashfree/return") ||
                lower.contains("status=success") ||
                lower.contains("status=failure") ||
                lower.contains("status=failed") ||
                lower.contains("status=cancelled") ||
                lower.contains("status=user_dropped") ||
                lower.contains("status=paid")) {
              _verifyWithBackend();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final lower = request.url.toLowerCase();
            // Intercept the return / status redirects so we can verify server-side
            // instead of trusting the redirect URL.
            if (lower.contains("payment-complete") ||
                lower.contains("/payments/cashfree/return") ||
                lower.contains("status=success") ||
                lower.contains("status=failure") ||
                lower.contains("status=failed") ||
                lower.contains("status=cancelled") ||
                lower.contains("status=user_dropped") ||
                lower.contains("status=paid")) {
              _verifyWithBackend();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint("Cashfree WebView Error: ${error.description}");
          },
        ),
      )
      ..loadRequest(Uri.parse(checkoutUrl));
  }

  /// Server-authoritative verification. Calls the backend which re-fetches the
  /// order status directly from Cashfree and decides PAID / FAILED / ACTIVE.
  Future<void> _verifyWithBackend() async {
    if (_resolved) return;
    setState(() => _resolved = true);

    if (!mounted) return;
    // Show a brief verifying overlay so the user knows we are confirming.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text("Verifying payment with bank..."),
          ],
        ),
        backgroundColor: Color(0xFF111827),
        duration: Duration(seconds: 8),
      ),
    );

    final res = await ApiService.verifyCashfreePayment(widget.orderId);
    if (!mounted) return;

    final isPaid = res["is_paid"] == true;
    final isFailed = res["is_failed"] == true;
    final gatewayStatus = (res["gateway_status"] ?? "UNKNOWN").toString();
    final reason = res["failure_reason"] ?? res["message"];

    Navigator.pop(context);

    if (isPaid) {
      widget.onPaymentComplete(CashfreeResult(
        paid: true,
        failed: false,
        gatewayStatus: gatewayStatus,
      ));
    } else if (isFailed) {
      // Show a clear failure dialog with the bank's reason before returning.
      _showFailureDialog(reason?.toString() ?? "Payment failed. Please retry with a different payment method.", gatewayStatus);
    } else {
      // ACTIVE / UNKNOWN — payment not decided. Treat as a soft failure so the
      // cart is preserved and the user can retry.
      _showFailureDialog(
        reason?.toString() ?? "We could not confirm your payment. Please retry.",
        gatewayStatus,
        soft: true,
      );
    }
  }

  void _showFailureDialog(String reason, String gatewayStatus, {bool soft = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Icon(
              soft ? Icons.help_outline_rounded : Icons.cancel_rounded,
              color: soft ? Colors.orangeAccent : Colors.redAccent,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              soft ? "Payment Not Confirmed" : "Payment Failed",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF111827)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              soft
                  ? "We couldn't confirm your payment with the bank. Your order has been kept on hold — please retry the payment."
                  : "Your payment was not successful. The order has been cancelled and your cart is restored so you can retry.",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Text(
                reason,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Order #${widget.orderNumber} • Gateway: $gatewayStatus",
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: soft ? Colors.orangeAccent : Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                widget.onPaymentComplete(CashfreeResult(
                  paid: false,
                  failed: !soft,
                  failureReason: reason,
                  gatewayStatus: gatewayStatus,
                ));
              },
              child: Text(
                soft ? "Retry Payment" : "Back to Cart",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showExitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Cancel Payment?", style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("Are you sure you want to cancel the Cashfree checkout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Continue Paying"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              // User explicitly cancelled — verify server-side in case a payment
              // was actually captured before they hit cancel.
              _verifyWithBackend();
            },
            child: const Text("Yes, Cancel", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: _showExitDialog,
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock, color: Color(0xFF059669), size: 16),
            ),
            const SizedBox(width: 8),
            const Text(
              "Secure Payment",
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black54),
            tooltip: "Reload Cashfree",
            onPressed: () => _controller.reload(),
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  color: const Color(0xFF6366F1), // Cashfree Indigo
                  backgroundColor: const Color(0xFFE0E7FF),
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
