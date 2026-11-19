import 'dart:math' show cos, asin, sqrt;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../utils/preferences.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';
import 'help_support_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String phone;
  final String name;
  final Function(String newName)? onProfileUpdated;
  final VoidCallback onLogout;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.phone,
    required this.name,
    this.onProfileUpdated,
    required this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfileModel? _profile;
  List<SavedAddressModel> _addresses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfileAndAddresses();
  }

  void _fetchProfileAndAddresses() async {
    setState(() => _isLoading = true);
    final prof = await ApiService.getUserProfile(
      widget.userId,
      defaultPhone: widget.phone,
    );
    final addrs = await ApiService.getSavedAddresses(widget.userId);

    if (!mounted) return;
    setState(() {
      _profile = prof;
      _addresses = addrs;
      _isLoading = false;
    });
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _profile?.name ?? widget.name);
    final emailCtrl = TextEditingController(text: _profile?.email ?? "");

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: GlassCard(
          blur: 24,
          opacity: 0.96,
          borderRadius: 28,
          borderColor: Colors.grey.shade300,
          padding: const EdgeInsets.all(22),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF059669),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Edit Profile Details",
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: Color(0xFF111827),
                            ),
                          ),
                          Text(
                            "Update your details for order updates & receipts",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Colors.black12),

                const Text(
                  "Full Name",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: TextField(
                    controller: nameCtrl,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: "Enter your full name",
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  "Email Address",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: TextField(
                    controller: emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: "name@example.com",
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 13,
                      ),
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: Color(0xFF059669),
                        size: 20,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  "Verified Mobile Number",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.phone_iphone_rounded,
                        color: Colors.black45,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "+91 ${widget.phone.isNotEmpty ? widget.phone : '9876543210'}",
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.lock_outline_rounded,
                        color: Colors.black38,
                        size: 16,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: BorderSide(color: Colors.grey.shade400),
                        ),
                        child: const Text(
                          "Cancel",
                          style: TextStyle(
                            color: Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          final newName = nameCtrl.text.trim();
                          final newEmail = emailCtrl.text.trim();
                          Navigator.pop(ctx);
                          await ApiService.updateUserProfile(
                            widget.userId,
                            newName,
                            newEmail,
                          );
                          if (newName.isNotEmpty) {
                            widget.onProfileUpdated?.call(newName);
                          }
                          if (!mounted) return;
                          setState(() {
                            _profile = UserProfileModel(
                              id: widget.userId,
                              name: newName.isNotEmpty
                                  ? newName
                                  : (widget.name),
                              phone: widget.phone,
                              email: newEmail,
                              totalOrders: _profile?.totalOrders ?? 0,
                              savedAddressesCount:
                                  _profile?.savedAddressesCount ?? 1,
                              memberSince:
                                  _profile?.memberSince ?? "November 2026",
                            );
                          });
                          LiquidToast.show(
                            context,
                            message: "👤 Profile details saved successfully",
                            icon: Icons.person_rounded,
                            accentColor: const Color(0xFF059669),
                          );
                        },
                        icon: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: const Text(
                          "Save Details",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddAddressDialog() {
    final flatCtrl = TextEditingController();
    final streetCtrl = TextEditingController();
    final landmarkCtrl = TextEditingController();
    String selectedTag = "Home";

    bool isGpsDetecting = false;
    double? detectedLat;
    double? detectedLng;
    bool? detectedServiceable;
    String? statusMessage;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassCard(
            blur: 24,
            opacity: 0.96,
            borderRadius: 28,
            borderColor: Colors.grey.shade300,
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF059669)
                            .withOpacity(0.12),
                        child: const Icon(
                          Icons.add_location_alt_rounded,
                          color: Color(0xFF059669),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Add Delivery Address",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: Color(0xFF111827),
                              ),
                            ),
                            Text(
                              "10-minute instant delivery pin from Dark Store",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Colors.black12),

                  // GPS Auto-Fill Button inside Profile Add Address Dialog
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
                              final dist = (res["distance_km"] ?? 0.0)
                                  .toDouble();
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
                                detectedLng =
                                    (res["longitude"] ?? pos.longitude)
                                        .toDouble();
                                detectedServiceable = true;
                                // We deliver ANYWHERE — there is no radius cap.
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

                  const Text(
                    "Address Label",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children:
                        [
                          {"tag": "Home", "icon": Icons.home_rounded},
                          {"tag": "Work", "icon": Icons.business_rounded},
                          {"tag": "Other", "icon": Icons.place_rounded},
                        ].map((item) {
                          final tag = item["tag"] as String;
                          final icon = item["icon"] as IconData;
                          final isSel = selectedTag == tag;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              avatar: Icon(
                                icon,
                                size: 16,
                                color: isSel
                                    ? Colors.white
                                    : const Color(0xFF059669),
                              ),
                              label: Text(
                                tag,
                                style: TextStyle(
                                  color: isSel
                                      ? Colors.white
                                      : const Color(0xFF111827),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSel,
                              selectedColor: const Color(0xFF059669),
                              backgroundColor: Colors.grey.shade100,
                              onSelected: (val) {
                                if (val) setModalState(() => selectedTag = tag);
                              },
                            ),
                          );
                        }).toList(),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "House / Flat / Floor No.",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: flatCtrl,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "e.g. Flat 402, Block A",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.home_outlined,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "Street / Area / Colony",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: streetCtrl,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "e.g. Allwyn Colony Road, Hyderabad",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.map_outlined,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "Landmark (Optional)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: landmarkCtrl,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "e.g. Near Metro Pillar 84",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.near_me_outlined,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: Colors.grey.shade400),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            final flatText = flatCtrl.text.trim();
                            final streetText = streetCtrl.text.trim();
                            final landmarkText = landmarkCtrl.text.trim();

                            if (flatText.isEmpty || streetText.isEmpty) {
                              LiquidToast.show(
                                context,
                                message: "Please enter Flat/House No. & Street Address",
                                icon: Icons.warning_amber_rounded,
                                accentColor: Colors.redAccent,
                              );
                              return;
                            }

                            // We deliver ANYWHERE — there is no radius cap, so
                            // we no longer block saving on distance. The GPS
                            // serviceability flag is always treated as true.

                            double finalLat = detectedLat ?? 17.495101;
                            double finalLng = detectedLng ?? 78.367535;

                            Navigator.pop(ctx);
                            await ApiService.addSavedAddress(
                              userId: widget.userId,
                              label: selectedTag,
                              houseNumber: flatText,
                              streetAddress: streetText,
                              landmark: landmarkText,
                              latitude: finalLat,
                              longitude: finalLng,
                            );

                            // Persist the FULL active-location record (lat, lng,
                            // distance, ETA) so the cart screen can show the
                            // address + ETA and send real coordinates to the
                            // backend. We always set isServiceable=true since we
                            // deliver anywhere; distance is recorded for display.
                            const hubLat = 17.495101;
                            const hubLng = 78.367535;
                            const earthRadiusKm = 6371.0;
                            double dLat =
                                (finalLat - hubLat) *
                                (3.141592653589793 / 180.0);
                            double dLng =
                                (finalLng - hubLng) *
                                (3.141592653589793 / 180.0);
                            double a =
                                0.5 -
                                0.5 *
                                    (cos(dLat) +
                                        cos(
                                              hubLat *
                                                  (3.141592653589793 / 180.0),
                                            ) *
                                            cos(
                                              finalLat *
                                                  (3.141592653589793 / 180.0),
                                            ) *
                                            cos(dLng));
                            double distKm = (earthRadiusKm * 2 * asin(sqrt(a)));
                            int etaMins = (distKm * 1.5 + 8)
                                .clamp(8, 120)
                                .round();

                            await Preferences.setString(
                              Preferences.keyActiveLocId,
                              "loc_${DateTime.now().millisecondsSinceEpoch}",
                            );
                            await Preferences.setString(
                              Preferences.keyActiveLocName,
                              "$selectedTag: $flatText",
                            );
                            await Preferences.setString(
                              Preferences.keyActiveLocAddress,
                              landmarkText.isNotEmpty
                                  ? "$streetText (Near $landmarkText)"
                                  : streetText,
                            );
                            await Preferences.setDouble(
                              Preferences.keyActiveLocLat,
                              finalLat,
                            );
                            await Preferences.setDouble(
                              Preferences.keyActiveLocLng,
                              finalLng,
                            );
                            await Preferences.setDouble(
                              Preferences.keyActiveLocDist,
                              distKm,
                            );
                            await Preferences.setBoolean(
                              Preferences.keyActiveLocServiceable,
                              true,
                            );
                            await Preferences.setInt(
                              Preferences.keyActiveLocEta,
                              etaMins,
                            );

                            if (!mounted) return;
                            _fetchProfileAndAddresses();
                            LiquidToast.show(
                              context,
                              message:
                                  "📍 Delivery address saved to your account",
                              icon: Icons.home_rounded,
                              accentColor: const Color(0xFF059669),
                            );
                          },
                          icon: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: const Text(
                            "Save Address",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditAddressDialog(SavedAddressModel addr) {
    final flatCtrl = TextEditingController(text: addr.houseNumber);
    final streetCtrl = TextEditingController(text: addr.streetAddress);
    final landmarkCtrl = TextEditingController(text: addr.landmark);
    String selectedTag = addr.label;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: GlassCard(
            blur: 24,
            opacity: 0.96,
            borderRadius: 28,
            borderColor: Colors.grey.shade300,
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFF059669)
                            .withOpacity(0.12),
                        child: const Icon(
                          Icons.edit_location_alt_rounded,
                          color: Color(0xFF059669),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Edit Delivery Address",
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: Color(0xFF111827),
                              ),
                            ),
                            Text(
                              "Update house number, street, or landmark",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Colors.black12),

                  const Text(
                    "Address Label",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children:
                        [
                          {"tag": "Home", "icon": Icons.home_rounded},
                          {"tag": "Work", "icon": Icons.business_rounded},
                          {"tag": "Other", "icon": Icons.place_rounded},
                        ].map((item) {
                          final tag = item["tag"] as String;
                          final icon = item["icon"] as IconData;
                          final isSel = selectedTag == tag;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ChoiceChip(
                              avatar: Icon(
                                icon,
                                size: 16,
                                color: isSel
                                    ? Colors.white
                                    : const Color(0xFF059669),
                              ),
                              label: Text(
                                tag,
                                style: TextStyle(
                                  color: isSel
                                      ? Colors.white
                                      : const Color(0xFF111827),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              selected: isSel,
                              selectedColor: const Color(0xFF059669),
                              backgroundColor: Colors.grey.shade100,
                              onSelected: (val) {
                                if (val) setModalState(() => selectedTag = tag);
                              },
                            ),
                          );
                        }).toList(),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "House / Flat / Floor No.",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: flatCtrl,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "e.g. Flat 402, Block A",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.home_outlined,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "Street / Area / Colony",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: streetCtrl,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "e.g. Allwyn Colony Road, Hyderabad",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.map_outlined,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    "Landmark (Optional)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: landmarkCtrl,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: "e.g. Near Metro Pillar 84",
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.near_me_outlined,
                          color: Color(0xFF059669),
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 22),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            side: BorderSide(color: Colors.grey.shade400),
                          ),
                          child: const Text(
                            "Cancel",
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            final flatText = flatCtrl.text.trim();
                            final streetText = streetCtrl.text.trim();
                            final landmarkText = landmarkCtrl.text.trim();

                            if (flatText.isEmpty || streetText.isEmpty) {
                              LiquidToast.show(
                                context,
                                message: "Please enter Flat/House No. & Street Address",
                                icon: Icons.warning_amber_rounded,
                                accentColor: Colors.redAccent,
                              );
                              return;
                            }

                            Navigator.pop(ctx);
                            await ApiService.deleteSavedAddress(
                              widget.userId,
                              addr.id,
                            );
                            await ApiService.addSavedAddress(
                              userId: widget.userId,
                              label: selectedTag,
                              houseNumber: flatText,
                              streetAddress: streetText,
                              landmark: landmarkText,
                              latitude: addr.latitude,
                              longitude: addr.longitude,
                            );

                            // Persist the FULL active-location record so the cart
                            // screen picks up the edited address with real coords.
                            const hubLat = 17.495101;
                            const hubLng = 78.367535;
                            const earthRadiusKm = 6371.0;
                            double dLat =
                                (addr.latitude - hubLat) *
                                (3.141592653589793 / 180.0);
                            double dLng =
                                (addr.longitude - hubLng) *
                                (3.141592653589793 / 180.0);
                            double a =
                                0.5 -
                                0.5 *
                                    (cos(dLat) +
                                        cos(
                                              hubLat *
                                                  (3.141592653589793 / 180.0),
                                            ) *
                                            cos(
                                              addr.latitude *
                                                  (3.141592653589793 / 180.0),
                                            ) *
                                            cos(dLng));
                            double distKm = (earthRadiusKm * 2 * asin(sqrt(a)));
                            int etaMins = (distKm * 1.5 + 8)
                                .clamp(8, 120)
                                .round();

                            await Preferences.setString(
                              Preferences.keyActiveLocId,
                              "loc_${DateTime.now().millisecondsSinceEpoch}",
                            );
                            await Preferences.setString(
                              Preferences.keyActiveLocName,
                              "$selectedTag: $flatText",
                            );
                            await Preferences.setString(
                              Preferences.keyActiveLocAddress,
                              landmarkText.isNotEmpty
                                  ? "$streetText (Near $landmarkText)"
                                  : streetText,
                            );
                            await Preferences.setDouble(
                              Preferences.keyActiveLocLat,
                              addr.latitude,
                            );
                            await Preferences.setDouble(
                              Preferences.keyActiveLocLng,
                              addr.longitude,
                            );
                            await Preferences.setDouble(
                              Preferences.keyActiveLocDist,
                              distKm,
                            );
                            await Preferences.setBoolean(
                              Preferences.keyActiveLocServiceable,
                              true,
                            );
                            await Preferences.setInt(
                              Preferences.keyActiveLocEta,
                              etaMins,
                            );

                            if (!mounted) return;
                            _fetchProfileAndAddresses();
                            LiquidToast.show(
                              context,
                              message:
                                  "📍 Delivery address updated successfully",
                              icon: Icons.check_circle_rounded,
                              accentColor: const Color(0xFF059669),
                            );
                          },
                          icon: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          label: const Text(
                            "Update Address",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              title: const Text(
                "Profile",
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 18,
                  letterSpacing: 0.3,
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(
                    Icons.edit_note_rounded,
                    size: 26,
                    color: Colors.white,
                  ),
                  onPressed: _showEditProfileDialog,
                ),
              ],
            ),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF059669)),
              )
            : RefreshIndicator(
                color: const Color(0xFF059669),
                onRefresh: () async {
                  _fetchProfileAndAddresses();
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // User Profile Header Glass Card
                      GlassCard(
                        blur: 20,
                        opacity: 0.9,
                        borderRadius: 24,
                        borderColor: Colors.grey.shade200,
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: const Color(0xFF059669),
                              child: Text(
                                (_profile?.name.isNotEmpty ?? false)
                                    ? _profile!.name[0].toUpperCase()
                                    : "F",
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _profile?.name ?? widget.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "+91 ${_profile?.phone ?? widget.phone}",
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (_profile?.email.isNotEmpty ?? false)
                                    Text(
                                      _profile!.email,
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669)
                                          .withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      "⚡ Flash Fresh Member",
                                      style: TextStyle(
                                        color: Color(0xFF059669),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Flash Monthly Pay Later Khata Card
                      GlassCard(
                        blur: 20,
                        opacity: 0.9,
                        borderRadius: 24,
                        borderColor: const Color(0xFF059669).withOpacity(0.3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF059669)
                                        .withOpacity(0.12),
                                  ),
                                  child: const Icon(
                                    Icons.event_note_rounded,
                                    color: Color(0xFF059669),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Flash Monthly Pay Later",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      Text(
                                        "Order anytime • Pay bill at end of month",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF059669),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    "ACTIVE",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20, color: Colors.black12),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Monthly Credit Limit:",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                Text(
                                  "₹5,000 / month",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Current Monthly Tab:",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                Text(
                                  "₹0 (No Dues)",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF059669),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 38,
                              child: ElevatedButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "No outstanding dues for this month! Your available credit is ₹5,000.",
                                      ),
                                      backgroundColor: Color(0xFF059669),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  "View Statement & Pay Bill",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Saved Addresses Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Saved Delivery Addresses",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _showAddAddressDialog,
                            icon: const Icon(
                              Icons.add,
                              size: 16,
                              color: Color(0xFF059669),
                            ),
                            label: const Text(
                              "Add New",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (_addresses.isEmpty)
                        GlassCard(
                          blur: 16,
                          opacity: 0.9,
                          borderRadius: 20,
                          borderColor: Colors.grey.shade200,
                          child: Column(
                            children: [
                              Icon(
                                Icons.location_off_outlined,
                                color: Colors.grey.shade400,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "No saved addresses yet",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Tap 'Add New' to save your house address for 10-minute delivery.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        ..._addresses.map(
                          (addr) => GlassCard(
                            blur: 16,
                            opacity: 0.9,
                            borderRadius: 20,
                            margin: const EdgeInsets.only(bottom: 10),
                            borderColor: Colors.grey.shade200,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  addr.label.toLowerCase() == "work"
                                      ? Icons.business_rounded
                                      : Icons.home_rounded,
                                  color: const Color(0xFF059669),
                                  size: 22,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            addr.label,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Color(0xFF111827),
                                            ),
                                          ),
                                          if (addr.isDefault) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF059669),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                "DEFAULT",
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "${addr.houseNumber}, ${addr.streetAddress}",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Edit & Delete Action Buttons
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_outlined,
                                        size: 18,
                                        color: Color(0xFF059669),
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () =>
                                          _showEditAddressDialog(addr),
                                    ),
                                    const SizedBox(width: 10),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: Colors.redAccent,
                                      ),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () async {
                                        await ApiService.deleteSavedAddress(
                                          widget.userId,
                                          addr.id,
                                        );
                                        _fetchProfileAndAddresses();
                                        if (mounted) {
                                          LiquidToast.show(
                                            context,
                                            message: "Address removed",
                                            icon: Icons.delete_forever_rounded,
                                            accentColor: Colors.redAccent,
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // 24x7 Help & Support Tile
                      GlassCard(
                        blur: 16,
                        opacity: 0.9,
                        borderRadius: 20,
                        borderColor: Colors.grey.shade200,
                        margin: const EdgeInsets.only(bottom: 20),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.support_agent_rounded,
                              color: Color(0xFF059669),
                              size: 24,
                            ),
                          ),
                          title: const Text(
                            "24x7 Help & Support",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFF111827),
                            ),
                          ),
                          subtitle: const Text(
                            "Raise ticket, FAQs, WhatsApp & Instant Callback",
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.black45,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HelpSupportScreen(
                                  userId: widget.userId,
                                  phone: widget.phone,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Logout Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: widget.onLogout,
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Colors.redAccent,
                          ),
                          label: const Text(
                            "Log Out Account",
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
