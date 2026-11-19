import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/preferences.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';
import 'cashfree_web_view.dart';
import 'order_tracking_screen.dart';

class CartScreen extends StatefulWidget {
  final List<CartItemModel> cartItems;
  final LocationModel deliveryLocation;
  final String? userId;
  final Function(LocationModel selectedLocation)? onLocationChanged;
  final VoidCallback onCartUpdated;
  final VoidCallback onClearCart;

  const CartScreen({
    super.key,
    required this.cartItems,
    required this.deliveryLocation,
    required this.userId,
    this.onLocationChanged,
    required this.onCartUpdated,
    required this.onClearCart,
  });

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  bool _isPlacingOrder = false;

  late LocationModel _activeLocation;
  String _selectedInstruction = "Don't ring bell";

  final List<String> _instructions = [
    "Don't ring bell",
    "Leave at gate/security",
    "Avoid calling",
    "Leave with neighbor",
  ];

  @override
  void initState() {
    super.initState();
    _activeLocation = widget.deliveryLocation;
    _refreshActiveLocationFromPrefs();
  }

  /// Reloads the active delivery location from SharedPreferences. The Profile
  /// screen saves a new address directly to prefs, but the cart screen holds a
  /// stale copy of the home-screen's location — so without this refresh the
  /// customer could open the cart and still see "Tap to Set Delivery Address"
  /// even after adding an address in their profile. We re-read the persisted
  /// record so the cart always reflects the latest saved address.
  void _refreshActiveLocationFromPrefs() {
    final savedName = Preferences.getString(Preferences.keyActiveLocName);
    if (savedName.isNotEmpty && !savedName.contains("Tap to Set")) {
      final refreshed = LocationModel(
        id: Preferences.getString(Preferences.keyActiveLocId, "loc_saved"),
        name: savedName,
        address: Preferences.getString(Preferences.keyActiveLocAddress),
        latitude: Preferences.getDouble(Preferences.keyActiveLocLat, 17.495101),
        longitude: Preferences.getDouble(
          Preferences.keyActiveLocLng,
          78.367535,
        ),
        landmark: "",
        distanceKm: Preferences.getDouble(Preferences.keyActiveLocDist, 0.0),
        isServiceable: Preferences.getBoolean(
          Preferences.keyActiveLocServiceable,
          true,
        ),
        etaMinutes: Preferences.getInt(Preferences.keyActiveLocEta, 10),
      );
      // Only adopt it if it's more complete than what we already have (avoids
      // overwriting an in-memory selection the user just made in this session).
      if (_activeLocation.id == "unset_loc" ||
          _activeLocation.name.contains("Tap to Set") ||
          _activeLocation.address.contains("Select location")) {
        _activeLocation = refreshed;
      } else if (refreshed.id != _activeLocation.id) {
        _activeLocation = refreshed;
      }
    }
  }

  double get itemsTotal =>
      widget.cartItems.fold(0.0, (sum, item) => sum + item.totalPrice);

  // Promo codes have been retired — no discount is ever applied.
  double get netItemsTotal => itemsTotal;
  double get deliveryFee =>
      (netItemsTotal >= 199.0 || itemsTotal == 0.0) ? 0.0 : 15.0;
  double get handlingFee => itemsTotal > 0 ? 4.0 : 0.0;
  double get gstAmount =>
      itemsTotal > 0 ? (0.18 * (deliveryFee + handlingFee)) : 0.0;
  double get grandTotal =>
      netItemsTotal + deliveryFee + handlingFee + gstAmount;

  void _showMandatoryAddressPrompt() {
    final flatCtrl = TextEditingController();
    final streetCtrl = TextEditingController();
    final landmarkCtrl = TextEditingController();

    bool isGpsDetecting = false;
    double? detectedLat;
    double? detectedLng;
    double? detectedDistKm;
    bool? detectedServiceable;
    int? detectedEta;
    String? statusMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.location_on_rounded, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Text(
                "Shipping Address Required",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Please enter your house / flat delivery address to proceed with your order.",
                  style: TextStyle(color: Colors.black87, fontSize: 13),
                ),
                const SizedBox(height: 12),

                // GPS Auto-Fill Button inside Cart Address Prompt
                InkWell(
                  onTap: isGpsDetecting
                      ? null
                      : () async {
                          setModalState(() {
                            isGpsDetecting = true;
                            statusMessage =
                                "Detecting device GPS coordinates...";
                          });

                          try {
                            bool serviceEnabled = false;
                            try {
                              serviceEnabled =
                                  await Geolocator.isLocationServiceEnabled();
                            } catch (err) {
                              setModalState(() {
                                isGpsDetecting = false;
                                statusMessage = "GPS unavailable: $err";
                              });
                              return;
                            }

                            if (!serviceEnabled) {
                              setModalState(() {
                                isGpsDetecting = false;
                                statusMessage = "Please enable GPS/Location in device settings.";
                              });
                              return;
                            }

                            var perm = await Geolocator.checkPermission();
                            if (perm == LocationPermission.denied) {
                              perm = await Geolocator.requestPermission();
                            }
                            if (perm == LocationPermission.denied ||
                                perm == LocationPermission.deniedForever) {
                              setModalState(() {
                                isGpsDetecting = false;
                                statusMessage = "Location permission denied.";
                              });
                              return;
                            }

                            final pos = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high,
                              timeLimit: const Duration(seconds: 12),
                            );

                            final res = await ApiService.reverseGeocode(
                              pos.latitude,
                              pos.longitude,
                            );
                            final dist = (res["distance_km"] ?? 0.0).toDouble();
                            final eta = res["eta_minutes"] != null
                                ? (res["eta_minutes"] as num).toInt()
                                : (res["estimated_delivery_minutes"] as num?)
                                          ?.toInt() ??
                                      10;

                            final addr = res["address"] ?? res["name"] ?? "";
                            final lm = res["landmark"] ?? "";

                            streetCtrl.text = addr;
                            if (lm.isNotEmpty) landmarkCtrl.text = lm;

                            setModalState(() {
                              isGpsDetecting = false;
                              detectedLat = (res["latitude"] ?? pos.latitude)
                                  .toDouble();
                              detectedLng = (res["longitude"] ?? pos.longitude)
                                  .toDouble();
                              detectedDistKm = dist;
                              detectedServiceable = true; // we deliver anywhere
                              detectedEta = eta;
                              statusMessage =
                                  "✅ Location detected (${dist.toStringAsFixed(1)} KM from hub • ETA ~${eta} mins)";
                            });
                          } catch (e) {
                            setModalState(() {
                              isGpsDetecting = false;
                              statusMessage = "GPS detection error: $e";
                            });
                          }
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF059669).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (isGpsDetecting)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF059669),
                            ),
                          )
                        else
                          const Icon(
                            Icons.my_location_rounded,
                            color: Color(0xFF059669),
                            size: 18,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isGpsDetecting
                                ? "Detecting location..."
                                : "📍 Auto-Fill with Current Location (GPS)",
                            style: const TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (detectedServiceable ?? false)
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (detectedServiceable ?? false)
                            ? const Color(0xFF10B981)
                            : Colors.redAccent,
                      ),
                    ),
                    child: Text(
                      statusMessage!,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: (detectedServiceable ?? false)
                            ? const Color(0xFF047857)
                            : Colors.red.shade700,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                TextField(
                  controller: flatCtrl,
                  style: const TextStyle(color: Color(0xFF111827)),
                  decoration: const InputDecoration(
                    labelText: "House / Flat / Floor No.",
                    hintText: "e.g. Flat 301, Block B",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: streetCtrl,
                  style: const TextStyle(color: Color(0xFF111827)),
                  decoration: const InputDecoration(
                    labelText: "Street / Area / Colony",
                    hintText: "e.g. Allwyn Colony Road, Hyderabad",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: landmarkCtrl,
                  style: const TextStyle(color: Color(0xFF111827)),
                  decoration: const InputDecoration(
                    labelText: "Landmark (Optional)",
                    hintText: "e.g. Near Metro Station",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.black54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
              ),
              onPressed: () async {
                final flat = flatCtrl.text.trim();
                final street = streetCtrl.text.trim();
                final landmark = landmarkCtrl.text.trim();

                if (flat.isEmpty || street.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Please enter house number and street address",
                      ),
                    ),
                  );
                  return;
                }

                // We deliver ANYWHERE — no radius cap, so we never block on
                // distance. detectedServiceable is always true.

                double finalLat = detectedLat ?? 17.495101;
                double finalLng = detectedLng ?? 78.367535;
                double finalDist = detectedDistKm ?? 0.8;
                bool finalSvc = true; // we deliver anywhere
                int finalEta = detectedEta ?? 10;

                if (detectedLat == null) {
                  final svc = await ApiService.checkServiceability(
                    finalLat,
                    finalLng,
                  );
                  finalLat = (svc["store_latitude"] ?? 17.495101).toDouble();
                  finalLng = (svc["store_longitude"] ?? 78.367535).toDouble();
                  finalDist = (svc["distance_km"] ?? 0.8).toDouble();
                  finalSvc = svc["is_serviceable"] ?? true;
                  finalEta =
                      (svc["estimated_delivery_minutes"] as num?)?.toInt() ??
                      10;
                }

                Navigator.pop(ctx);

                final newLoc = LocationModel(
                  id: "custom_${DateTime.now().millisecondsSinceEpoch}",
                  name: "Home: $flat",
                  address: landmark.isNotEmpty
                      ? "$street (Near $landmark)"
                      : street,
                  latitude: finalLat,
                  longitude: finalLng,
                  landmark: landmark,
                  distanceKm: finalDist,
                  isServiceable: finalSvc,
                  etaMinutes: finalEta,
                );

                setState(() {
                  _activeLocation = newLoc;
                });

                widget.onLocationChanged?.call(newLoc);

                if (widget.userId != null) {
                  await ApiService.addSavedAddress(
                    userId: widget.userId!,
                    label: "Home",
                    houseNumber: flat,
                    streetAddress: street,
                    landmark: landmark,
                    latitude: finalLat,
                    longitude: finalLng,
                  );
                }

                // Continue to checkout after address is saved
                _handleCheckout();
              },
              child: const Text(
                "Save & Continue to Pay",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaymentSuccessDialog({
    required String orderId,
    required String orderNum,
    required double grandTotal,
    required List<CartItemModel> orderedItems,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassCard(
          blur: 24,
          opacity: 0.96,
          borderRadius: 32,
          padding: const EdgeInsets.all(28),
          borderColor: const Color(0xFF059669).withOpacity(0.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (context, val, child) {
                  return Transform.scale(
                    scale: val,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF059669),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF059669).withOpacity(0.4),
                            blurRadius: 28,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                "Payment Successful! 🎉",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Order #$orderNum Confirmed (₹${grandTotal.toStringAsFixed(0)})",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF059669),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Sent to Central Dark Store for 3-minute packing & 10-min delivery.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 20),
              LiquidButton(
                label: "Track Live Delivery ⚡",
                icon: Icons.flash_on_rounded,
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onClearCart();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderTrackingScreen(
                        orderId: orderId,
                        orderNumber: orderNum,
                        grandTotal: grandTotal,
                        etaMinutes: _activeLocation.etaMinutes,
                        deliveryAddress:
                            "${_activeLocation.name}, ${_activeLocation.address}",
                        destinationLatitude: _activeLocation.latitude,
                        destinationLongitude: _activeLocation.longitude,
                        items: orderedItems,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentFailedDialog({required String reason}) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: GlassCard(
          blur: 24,
          opacity: 0.96,
          borderRadius: 32,
          padding: const EdgeInsets.all(28),
          borderColor: Colors.redAccent.withOpacity(0.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.elasticOut,
                builder: (context, val, child) {
                  return Transform.scale(
                    scale: val,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.redAccent,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.redAccent.withOpacity(0.4),
                            blurRadius: 28,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              const Text(
                "Payment Unsuccessful ❌",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red.shade900,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Your cart is saved. Zero amount was debited from your account.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: const Text(
                    "Retry Payment",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows the list of price changes detected during cart re-pricing and asks
  /// the customer to confirm before placing the order. Returns true if the
  /// customer accepts the new prices.
  Future<bool> _showPriceChangeDialog(List<dynamic> changes) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(
              Icons.price_change_rounded,
              color: Color(0xFFD97706),
              size: 28,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "Prices updated",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Some prices changed since you added these items. Your cart has been updated to the latest prices.",
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              ...changes.map((c) {
                final name = (c.name as String?) ?? '';
                final variant = (c.variant as String?) ?? '';
                final oldP = (c.oldPrice as num?)?.toDouble() ?? 0.0;
                final newP = (c.newPrice as num?)?.toDouble() ?? 0.0;
                final up = newP > oldP;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "$name ($variant)",
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      Text(
                        "₹${oldP.toStringAsFixed(0)} → ₹${newP.toStringAsFixed(0)}",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: up
                              ? Colors.redAccent
                              : const Color(0xFF059669),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Review cart",
              style: TextStyle(color: Colors.black54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Continue to pay",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _handleCheckout() async {
    // 1. Mandatory Address Check: Only prompt if location is truly unset or placeholder
    bool isAddressUnset =
        _activeLocation.id == "unset_loc" ||
        _activeLocation.name.contains("Tap to Set") ||
        _activeLocation.address.contains("Select location") ||
        _activeLocation.address.trim().isEmpty;

    if (isAddressUnset) {
      _showMandatoryAddressPrompt();
      return;
    }

    if (widget.cartItems.isEmpty) return;

    setState(() => _isPlacingOrder = true);

    // ── Re-price cart items against the LIVE backend catalog before checkout ──
    // The price displayed when an item was added to the cart may now be stale
    // (store manager updated the price). We refresh prices from the backend and
    // block checkout if the catalog cannot be reached or any item became
    // unavailable, so the customer is never over/under-charged.
    final reprice = await ApiService.repriceCartItems(widget.cartItems);
    if (!mounted) return;

    if (!reprice.ok) {
      setState(() => _isPlacingOrder = false);
      LiquidToast.show(
        context,
        message: reprice.error ?? "Cannot verify current prices. Please retry.",
        icon: Icons.wifi_off_rounded,
        accentColor: Colors.redAccent,
      );
      return;
    }

    // Replace cart items with the freshly-priced versions and notify parent.
    widget.cartItems
      ..clear()
      ..addAll(reprice.updatedItems);
    widget.onCartUpdated();

    if (reprice.unavailable.isNotEmpty) {
      setState(() => _isPlacingOrder = false);
      LiquidToast.show(
        context,
        message:
            "Some items are no longer available and were removed:\n${reprice.unavailable.take(3).join(', ')}${reprice.unavailable.length > 3 ? ' …' : ''}",
        icon: Icons.remove_shopping_cart_rounded,
        accentColor: Colors.redAccent,
      );
      return;
    }

    if (reprice.priceChanges.isNotEmpty) {
      // Show the price changes and ask the customer to confirm before paying.
      setState(() => _isPlacingOrder = false);
      final accepted = await _showPriceChangeDialog(reprice.priceChanges);
      if (!accepted)
        return; // user declined — cart already updated, they can review
      setState(() => _isPlacingOrder = true);
    }

    bool hasMeat = widget.cartItems.any((i) => i.product.isSundayOnly);

    final orderRes = await ApiService.createOrder(
      userId: widget.userId ?? "usr_local_mock",
      deliveryAddress: "${_activeLocation.name}, ${_activeLocation.address}",
      latitude: _activeLocation.latitude,
      longitude: _activeLocation.longitude,
      items: widget.cartItems,
      paymentMethod: "UPI",
      isSundayMeatOrder: hasMeat,
      deliveryInstructions: _selectedInstruction,
    );

    if (!mounted) return;
    setState(() => _isPlacingOrder = false);

    if (orderRes['success'] == true) {
      final orderId = orderRes['order_id'];
      final orderNum = orderRes['order_number'];
      final paymentSessionId =
          orderRes['payment_session_id'] ??
          (orderRes['payment'] != null
              ? orderRes['payment']['payment_session_id']
              : null);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CashfreeWebViewScreen(
            paymentSessionId: paymentSessionId,
            orderId: orderId,
            orderNumber: orderNum,
            grandTotal: grandTotal,
            onPaymentComplete: (result) {
              if (result.paid) {
                List<CartItemModel> orderedItems = List.from(widget.cartItems);
                _showPaymentSuccessDialog(
                  orderId: orderId,
                  orderNum: orderNum,
                  grandTotal: grandTotal,
                  orderedItems: orderedItems,
                );
              } else {
                final reason =
                    result.failureReason ??
                    "Payment was cancelled or unsuccessful. Your cart is saved — please retry.";
                _showPaymentFailedDialog(reason: reason);
              }
            },
          ),
        ),
      );
    } else {
      // Surface the REAL backend reason. Previously this showed a generic
      // "Unable to create order" snackbar, hiding the actual cause (out-of-
      // radius address, stale cart item, rate limit, etc.). The backend now
      // returns an actionable `detail`/`message` we can show verbatim.
      final reason =
          (orderRes['message'] ??
                  orderRes['detail'] ??
                  'Unable to create order. Please try again.')
              .toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Change Address',
            textColor: Colors.white,
            onPressed: () => _showMandatoryAddressPrompt(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text(
            "Basket & Checkout",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: widget.cartItems.isEmpty
            ? Center(
                child: GlassCard(
                  blur: 20,
                  opacity: 0.9,
                  borderRadius: 28,
                  padding: const EdgeInsets.all(28),
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shopping_basket_outlined,
                        size: 64,
                        color: Color(0xFF059669),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Your basket is empty",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Add fresh veggies or Sunday meats to order",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 24),
                      LiquidButton(
                        label: "Explore Catalog",
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Delivery Address Glass Banner
                    GlassCard(
                      blur: 16,
                      opacity: 0.9,
                      borderRadius: 20,
                      borderColor: Colors.grey.shade200,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF059669).withOpacity(0.12),
                            ),
                            child: Icon(
                              Icons.bolt_rounded,
                              color: const Color(0xFF059669),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Delivering to: ${_activeLocation.name}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                                Text(
                                  "⚡ ~${_activeLocation.etaMinutes} mins (${_activeLocation.distanceKm.toStringAsFixed(1)} km from Central Hub)",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: const Color(0xFF059669),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Cart Items Glass Card
                    GlassCard(
                      blur: 16,
                      opacity: 0.9,
                      borderRadius: 22,
                      borderColor: Colors.grey.shade200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Selected Fresh Items",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const Divider(height: 20, color: Colors.black12),
                          ...widget.cartItems.map((item) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6.0,
                              ),
                              child: Row(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.network(
                                      item.product.imageUrl,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              Container(
                                                width: 48,
                                                height: 48,
                                                color: Colors.green.shade50,
                                                child: const Icon(
                                                  Icons.eco_rounded,
                                                  color: Color(0xFF059669),
                                                ),
                                              ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.product.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF111827),
                                          ),
                                        ),
                                        Text(
                                          item.selectedVariant.weightLabel,
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 11,
                                          ),
                                        ),
                                        Text(
                                          "₹${item.selectedVariant.price.toStringAsFixed(0)}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            color: Color(0xFF059669),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.remove,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              if (item.quantity > 1) {
                                                item.quantity--;
                                              } else {
                                                widget.cartItems.remove(item);
                                              }
                                            });
                                            widget.onCartUpdated();
                                          },
                                        ),
                                        Text(
                                          "${item.quantity}",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.add,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(
                                            minWidth: 28,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              item.quantity++;
                                            });
                                            widget.onCartUpdated();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Delivery Instructions Glass Selector
                    GlassCard(
                      blur: 16,
                      opacity: 0.9,
                      borderRadius: 22,
                      borderColor: Colors.grey.shade200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Delivery Instructions",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _instructions.map((inst) {
                              bool isSelected = _selectedInstruction == inst;
                              return ChoiceChip(
                                label: Text(
                                  inst,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: const Color(0xFF059669),
                                backgroundColor: Colors.grey.shade100,
                                onSelected: (sel) {
                                  if (sel)
                                    setState(() => _selectedInstruction = inst);
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Bill Summary Glass Card
                    GlassCard(
                      blur: 16,
                      opacity: 0.9,
                      borderRadius: 22,
                      borderColor: Colors.grey.shade200,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Bill Summary",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF111827),
                            ),
                          ),
                          const Divider(height: 20, color: Colors.black12),
                          _billRow(
                            "Items Subtotal",
                            "₹${itemsTotal.toStringAsFixed(0)}",
                          ),
                          _billRow(
                            "Veggies & Raw Meat GST",
                            "EXEMPT (0%)",
                            isGreen: true,
                          ),
                          _billRow(
                            "Delivery Fee",
                            deliveryFee == 0
                                ? "FREE"
                                : "₹${deliveryFee.toStringAsFixed(0)}",
                            isGreen: deliveryFee == 0,
                          ),
                          _billRow(
                            "Packaging & Quality Check",
                            "₹${handlingFee.toStringAsFixed(0)}",
                          ),
                          _billRow(
                            "GST & Govt Taxes (18% on Services)",
                            "₹${gstAmount.toStringAsFixed(2)}",
                          ),
                          const Divider(height: 20, color: Colors.black12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                "To Pay",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              Text(
                                "₹${grandTotal.toStringAsFixed(0)}",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
        bottomSheet: widget.cartItems.isEmpty
            ? null
            : Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: SafeArea(
                  child: LiquidButton(
                    label: "Proceed to Pay • ₹${grandTotal.toStringAsFixed(0)}",
                    icon: Icons.lock_rounded,
                    isLoading: _isPlacingOrder,
                    onPressed: _handleCheckout,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _billRow(String title, String value, {bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isGreen ? const Color(0xFF059669) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
