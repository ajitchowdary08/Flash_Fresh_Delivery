import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';
import 'map_pin_picker_screen.dart';

class SelectLocationScreen extends StatefulWidget {
  final LocationModel currentLocation;
  final String? userId;
  final bool isLoggedIn;
  final Function(LocationModel selectedLocation) onSelectLocation;
  final VoidCallback? onOpenLogin;

  const SelectLocationScreen({
    super.key,
    required this.currentLocation,
    this.userId,
    this.isLoggedIn = false,
    required this.onSelectLocation,
    this.onOpenLogin,
  });

  @override
  State<SelectLocationScreen> createState() => _SelectLocationScreenState();
}

class _SelectLocationScreenState extends State<SelectLocationScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<LocationModel> _searchResults = [];
  List<SavedAddressModel> _savedAddresses = [];
  List<LocationModel> _nearbyLocations = [];
  bool _isLoading = false;
  bool _isDetectingGps = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    List<SavedAddressModel> saved = [];
    if (widget.isLoggedIn && widget.userId != null && widget.userId!.isNotEmpty) {
      saved = await ApiService.getSavedAddresses(widget.userId!);
    }
    final nearby = await ApiService.getNearbyLocations(
      lat: widget.currentLocation.latitude,
      lng: widget.currentLocation.longitude,
    );

    if (mounted) {
      setState(() {
        _savedAddresses = saved;
        _nearbyLocations = nearby;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isLoading = true);
    final results = await ApiService.getLocations(query: q);
    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleUseCurrentLocation() async {
    setState(() => _isDetectingGps = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          LiquidToast.show(
            context,
            message: "Please enable GPS location on your device",
            icon: Icons.location_off_rounded,
            accentColor: Colors.orange.shade800,
          );
        }
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) {
          LiquidToast.show(
            context,
            message: "Location permission denied",
            icon: Icons.gpp_bad_rounded,
            accentColor: Colors.red.shade700,
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return;

      // Open Map Pin Picker centered on detected GPS coordinates
      _openMapPinPicker(pos.latitude, pos.longitude);
    } catch (e) {
      if (mounted) {
        // Fallback to hub coordinates if GPS fail
        _openMapPinPicker(widget.currentLocation.latitude, widget.currentLocation.longitude);
      }
    } finally {
      if (mounted) setState(() => _isDetectingGps = false);
    }
  }

  void _openMapPinPicker(double initialLat, double initialLng, {String initialName = ""}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapPinPickerScreen(
          initialLatitude: initialLat,
          initialLongitude: initialLng,
          initialAreaName: initialName,
          onLocationConfirmed: (selectedLoc) {
            widget.onSelectLocation(selectedLoc);
            Navigator.pop(context); // Pop SelectLocationScreen back to Home
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF111827), size: 22),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            "Select Your Location",
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          centerTitle: false,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Search Input Box
              GlassCard(
                blur: 14,
                opacity: 0.95,
                borderRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                borderColor: Colors.grey.shade300,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Color(0xFF111827), fontSize: 14),
                        onChanged: _onSearchChanged,
                        decoration: const InputDecoration(
                          hintText: "Search an area or address",
                          hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const Icon(Icons.search_rounded, color: Colors.black45, size: 22),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // "Use Current Location" Button (exact Swiggy style - image 2)
              GlassCard(
                blur: 16,
                opacity: 0.95,
                borderRadius: 16,
                borderColor: const Color(0xFF2563EB).withOpacity(0.3),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                onTap: _isDetectingGps ? null : _handleUseCurrentLocation,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isDetectingGps)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2563EB)),
                      )
                    else
                      const Icon(Icons.my_location_rounded, color: Color(0xFF2563EB), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _isDetectingGps ? "Locating..." : "Use Current Location",
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Search Results (if typing in search box)
              if (_searchController.text.trim().isNotEmpty) ...[
                const Text(
                  "SEARCH RESULTS",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 10),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
                else if (_searchResults.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0),
                    child: Center(
                      child: Text(
                        "No matching places found.",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ),
                  )
                else
                  ..._searchResults.map((loc) => _buildPlaceItemTile(loc)),
              ]

              // Logged Out Banner Section (exact Swiggy style - Image 2)
              else if (!widget.isLoggedIn) ...[
                const SizedBox(height: 24),
                Center(
                  child: Column(
                    children: [
                      // Circular graphic with lock and magnifying glass inside map circle
                      Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue.shade50.withOpacity(0.6),
                          border: Border.all(color: Colors.blue.shade100, width: 2),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Map grid circles background
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue.shade200.withOpacity(0.5), width: 1.5),
                              ),
                            ),
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.blue.shade300.withOpacity(0.5), width: 1.5),
                              ),
                            ),
                            // Magnifying glass with Lock
                            Icon(Icons.search_rounded, size: 52, color: Colors.blue.shade400.withOpacity(0.7)),
                            Positioned(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.blue.shade200.withOpacity(0.4),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Icon(Icons.lock_rounded, size: 22, color: Colors.blue.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      Text(
                        "Looks like you're logged out",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        "Please log in to see\nsaved addresses",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                          height: 1.2,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Swiggy style primary Login Button
                      SizedBox(
                        width: 220,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: () {
                            if (widget.onOpenLogin != null) {
                              widget.onOpenLogin!();
                            } else {
                              Navigator.pop(context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: const Color(0xFF2563EB).withOpacity(0.4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            "Login to Flash Fresh",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ]

              // Logged In Saved Addresses Section
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "SAVED ADDRESSES",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Colors.black54,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _openMapPinPicker(widget.currentLocation.latitude, widget.currentLocation.longitude),
                      icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF2563EB)),
                      label: const Text(
                        "Add New",
                        style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (_savedAddresses.isEmpty)
                  GlassCard(
                    blur: 14,
                    opacity: 0.9,
                    borderRadius: 16,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.location_city_rounded, color: Colors.grey.shade400, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "No saved addresses yet. Tap 'Use Current Location' or search your area.",
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ..._savedAddresses.map((addr) => _buildSavedAddressCard(addr)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedAddressCard(SavedAddressModel addr) {
    final isSelected = widget.currentLocation.name.contains(addr.houseNumber) ||
        widget.currentLocation.address.contains(addr.streetAddress);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: GlassCard(
        blur: 14,
        opacity: 0.95,
        borderRadius: 16,
        borderColor: isSelected ? const Color(0xFF2563EB) : Colors.grey.shade200,
        onTap: () {
          final loc = LocationModel(
            id: addr.id,
            name: "${addr.label}: ${addr.houseNumber}",
            address: addr.landmark.isNotEmpty ? "${addr.streetAddress} (Near ${addr.landmark})" : addr.streetAddress,
            latitude: addr.latitude,
            longitude: addr.longitude,
            landmark: addr.landmark,
            distanceKm: addr.distanceKm,
            isServiceable: addr.isServiceable,
            etaMinutes: 10,
          );
          widget.onSelectLocation(loc);
          Navigator.pop(context);
        },
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF2563EB).withOpacity(0.12),
              child: Icon(
                addr.label.toLowerCase() == "work" ? Icons.business_rounded : Icons.home_rounded,
                color: const Color(0xFF2563EB),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${addr.label}: ${addr.houseNumber}",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    addr.landmark.isNotEmpty ? "${addr.streetAddress} • Near ${addr.landmark}" : addr.streetAddress,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle_rounded, color: Color(0xFF2563EB)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceItemTile(LocationModel loc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: GlassCard(
        blur: 14,
        opacity: 0.95,
        borderRadius: 16,
        borderColor: Colors.grey.shade200,
        onTap: () {
          _openMapPinPicker(loc.latitude, loc.longitude, initialName: loc.name);
        },
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey.shade100,
              ),
              child: const Icon(Icons.location_on_outlined, color: Colors.black87, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827)),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.black38, size: 14),
          ],
        ),
      ),
    );
  }
}
