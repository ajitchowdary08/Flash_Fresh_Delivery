import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../services/firebase_auth_service.dart';
import '../utils/preferences.dart';
import '../widgets/liquid_toast.dart';
import 'home_screen.dart';
import 'orders_history_screen.dart';
import 'profile_screen.dart';
import 'auth_screen.dart';
import 'cart_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  String? _userId;
  String _userPhone = "";
  String _userName = "";
  bool _isLoggedIn = false;

  final List<CartItemModel> _cartItems = [];
  final Set<String> _favoriteProductIds = {};
  LocationModel _currentLocation = LocationModel(
    id: "unset_loc",
    name: "Tap to Set Delivery Address",
    address: "Select location or add your flat / house address",
    latitude: 17.495101,
    longitude: 78.367535,
    landmark: "Central Hub",
    distanceKm: 0.1,
    isServiceable: true,
    etaMinutes: 10,
  );

  @override
  void initState() {
    super.initState();
    _loadSavedSession();
    _loadSavedFavorites();
    _loadInitialProducts();
  }

  void _loadSavedFavorites() {
    final favList = Preferences.getStringList(Preferences.keyFavoriteProducts);
    setState(() {
      _favoriteProductIds.addAll(favList);
    });
  }

  void _toggleFavorite(String productId) async {
    setState(() {
      if (_favoriteProductIds.contains(productId)) {
        _favoriteProductIds.remove(productId);
      } else {
        _favoriteProductIds.add(productId);
      }
    });
    await Preferences.setStringList(
      Preferences.keyFavoriteProducts,
      _favoriteProductIds.toList(),
    );
  }

  Future<void> _updateActiveLocation(LocationModel loc) async {
    await Preferences.setString(Preferences.keyActiveLocId, loc.id);
    await Preferences.setString(Preferences.keyActiveLocName, loc.name);
    await Preferences.setString(Preferences.keyActiveLocAddress, loc.address);
    await Preferences.setDouble(Preferences.keyActiveLocLat, loc.latitude);
    await Preferences.setDouble(Preferences.keyActiveLocLng, loc.longitude);
    await Preferences.setDouble(Preferences.keyActiveLocDist, loc.distanceKm);
    await Preferences.setBoolean(
      Preferences.keyActiveLocServiceable,
      loc.isServiceable,
    );
    await Preferences.setInt(Preferences.keyActiveLocEta, loc.etaMinutes);

    setState(() {
      _currentLocation = loc;
    });
  }

  void _loadSavedSession() async {
    final savedId = Preferences.getString(Preferences.keyUserId);
    final savedPhone = Preferences.getString(Preferences.keyUserPhone);
    final savedName = Preferences.getString(Preferences.keyUserName);

    final activeLocName = Preferences.getString(Preferences.keyActiveLocName);
    final activeLocAddress =
        Preferences.getString(Preferences.keyActiveLocAddress);
    LocationModel? storedLoc;
    if (activeLocName.isNotEmpty &&
        !activeLocName.contains("Tap to Set") &&
        activeLocAddress.isNotEmpty &&
        !activeLocAddress.contains("Select location")) {
      storedLoc = LocationModel(
        id: Preferences.getString(Preferences.keyActiveLocId, "loc_saved"),
        name: activeLocName,
        address: activeLocAddress,
        latitude: Preferences.getDouble(Preferences.keyActiveLocLat, 17.495101),
        longitude: Preferences.getDouble(Preferences.keyActiveLocLng, 78.367535),
        landmark: "",
        distanceKm: Preferences.getDouble(Preferences.keyActiveLocDist, 0.8),
        isServiceable: Preferences.getBoolean(
          Preferences.keyActiveLocServiceable,
          true,
        ),
        etaMinutes: Preferences.getInt(Preferences.keyActiveLocEta, 10),
      );
    }

    if (savedId.isNotEmpty && savedPhone.isNotEmpty) {
      final savedAddrs = await ApiService.getSavedAddresses(savedId);
      if (savedAddrs.isNotEmpty) {
        final topAddr = savedAddrs.firstWhere((a) => a.isDefault,
            orElse: () => savedAddrs.first);
        if (storedLoc == null ||
            storedLoc.id == "unset_loc" ||
            storedLoc.name.contains("Tap to Set") ||
            storedLoc.address.contains("Select location") ||
            storedLoc.address.trim().isEmpty) {
          storedLoc = LocationModel(
            id: topAddr.id,
            name: "${topAddr.label}: ${topAddr.houseNumber}",
            address: topAddr.landmark.isNotEmpty
                ? "${topAddr.streetAddress} (Near ${topAddr.landmark})"
                : topAddr.streetAddress,
            latitude: topAddr.latitude,
            longitude: topAddr.longitude,
            landmark: topAddr.landmark,
            distanceKm: topAddr.distanceKm,
            isServiceable: topAddr.isServiceable,
            etaMinutes: 10,
          );
          await _updateActiveLocation(storedLoc);
        }
      }

      setState(() {
        _userId = savedId;
        _userPhone = savedPhone;
        _userName = savedName.isNotEmpty ? savedName : "Customer";
        _isLoggedIn = true;
        if (storedLoc != null) {
          _currentLocation = storedLoc;
        }
      });
    } else if (storedLoc != null) {
      setState(() {
        _currentLocation = storedLoc!;
      });
    }
  }

  void _saveSession(String phone, String name, String id) async {
    await Preferences.setString(Preferences.keyUserId, id);
    await Preferences.setString(Preferences.keyUserPhone, phone);

    final existingName = Preferences.getString(Preferences.keyUserName);
    String finalName = name;
    if (existingName.isNotEmpty &&
        existingName != "Customer" &&
        !existingName.startsWith("Customer (")) {
      if (name.isEmpty || name == "Customer" || name.startsWith("Customer (")) {
        finalName = existingName;
      }
    }

    await Preferences.setString(Preferences.keyUserName, finalName);

    // Fetch and sync user's saved addresses automatically upon login
    final savedAddrs = await ApiService.getSavedAddresses(id);
    if (savedAddrs.isNotEmpty) {
      final topAddr = savedAddrs.firstWhere((a) => a.isDefault, orElse: () => savedAddrs.first);
      final loc = LocationModel(
        id: topAddr.id,
        name: "${topAddr.label}: ${topAddr.houseNumber}",
        address: topAddr.landmark.isNotEmpty
            ? "${topAddr.streetAddress} (Near ${topAddr.landmark})"
            : topAddr.streetAddress,
        latitude: topAddr.latitude,
        longitude: topAddr.longitude,
        landmark: topAddr.landmark,
        distanceKm: topAddr.distanceKm,
        isServiceable: topAddr.isServiceable,
        etaMinutes: 10,
      );
      await _updateActiveLocation(loc);
    }

    if (!mounted) return;
    setState(() {
      _userId = id;
      _userPhone = phone;
      _userName = finalName;
      _isLoggedIn = true;
      _currentIndex = 0; // Always land on Home after login
    });
  }

  void _clearSession() async {
    // Clear EVERYTHING: JWT token, profile, cart, favorites, saved addresses,
    // cached orders. Previously this only removed profile keys, leaving the JWT
    // and the previous user's cart/orders/favorites on the device — a cross-user
    // data leak on shared phones.
    await ApiService.clearLocalCache();
    await FirebaseAuthService.signOut();

    if (!mounted) return;
    setState(() {
      _currentIndex = 0;
      _isLoggedIn = false;
      _userId = null;
      _userPhone = "";
      _userName = "";
      _cartItems.clear();
      _favoriteProductIds.clear();
    });
  }

  void _loadInitialProducts() async {
    await ApiService.getProducts();
    if (!mounted) return;
    setState(() {});
  }

  void _addToCart(ProductModel product, ProductVariantModel variant) {
    setState(() {
      for (var item in _cartItems) {
        if (item.product.id == product.id &&
            item.selectedVariant.id == variant.id) {
          item.quantity++;
          return;
        }
      }
      _cartItems.add(
        CartItemModel(product: product, selectedVariant: variant, quantity: 1),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = _isLoggedIn
        ? [
            HomeScreen(
              currentLocation: _currentLocation,
              cartItems: _cartItems,
              userId: _userId,
              isLoggedIn: true,
              favoriteProductIds: _favoriteProductIds,
              onToggleFavorite: _toggleFavorite,
              onLocationChanged: (loc) => _updateActiveLocation(loc),
              onAddToCart: _addToCart,
              onCartUpdated: () => setState(() {}),
              onOpenCart: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CartScreen(
                      cartItems: _cartItems,
                      deliveryLocation: _currentLocation,
                      userId: _userId,
                      onLocationChanged: (loc) => _updateActiveLocation(loc),
                      onCartUpdated: () => setState(() {}),
                      onClearCart: () => setState(() => _cartItems.clear()),
                    ),
                  ),
                ).then((_) => setState(() {}));
              },
            ),
            OrdersHistoryScreen(
              userId: _userId!,
              onReorder: (items) {
                setState(() => _cartItems.addAll(items));
              },
            ),
            ProfileScreen(
              userId: _userId!,
              phone: _userPhone,
              name: _userName,
              onLocationChanged: (loc) => _updateActiveLocation(loc),
              onProfileUpdated: (newName) async {
                await Preferences.setString(Preferences.keyUserName, newName);
                setState(() {
                  _userName = newName;
                });
              },
              onLogout: () {
                _clearSession();
                LiquidToast.show(
                  context,
                  message: "👋 Logged out successfully",
                  icon: Icons.logout_rounded,
                  accentColor: Colors.grey.shade800,
                );
              },
            ),
          ]
        : [
            HomeScreen(
              currentLocation: _currentLocation,
              cartItems: _cartItems,
              userId: _userId,
              isLoggedIn: false,
              favoriteProductIds: _favoriteProductIds,
              onToggleFavorite: _toggleFavorite,
              onLocationChanged: (loc) => _updateActiveLocation(loc),
              onAddToCart: _addToCart,
              onCartUpdated: () => setState(() {}),
              onOpenLogin: () {
                setState(() => _currentIndex = 1);
              },
              onOpenCart: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CartScreen(
                      cartItems: _cartItems,
                      deliveryLocation: _currentLocation,
                      userId: _userId,
                      onLocationChanged: (loc) => _updateActiveLocation(loc),
                      onCartUpdated: () => setState(() {}),
                      onClearCart: () => setState(() => _cartItems.clear()),
                    ),
                  ),
                ).then((_) => setState(() {}));
              },
            ),
            AuthScreen(
              onLoginSuccess: (phone, name, id) {
                _saveSession(phone, name, id);
              },
              onCancel: () {
                setState(() => _currentIndex = 0);
              },
            ),
          ];

    int safeIndex = _currentIndex;
    if (safeIndex >= screens.length) {
      safeIndex = 0;
    }

    // Hide bottom navigation bar on Login screen
    final bool showBottomNav = _isLoggedIn || safeIndex == 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8F6),
      body: Stack(
        children: [
          IndexedStack(index: safeIndex, children: screens),

          // Floating Dark Glass Navigation Bar (Hidden on Login Screen)
          if (showBottomNav)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF082219).withOpacity(0.92),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF87).withOpacity(0.15),
                          blurRadius: 28,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: _isLoggedIn
                          ? [
                              _buildNavItem(
                                0,
                                Icons.home_rounded,
                                Icons.home_outlined,
                                "Home",
                              ),
                              _buildNavItem(
                                1,
                                Icons.receipt_long_rounded,
                                Icons.receipt_long_outlined,
                                "Orders",
                              ),
                              _buildNavItem(
                                2,
                                Icons.person_rounded,
                                Icons.person_outline_rounded,
                                "Account",
                              ),
                            ]
                          : [
                              _buildNavItem(
                                0,
                                Icons.home_rounded,
                                Icons.home_outlined,
                                "Home",
                              ),
                              _buildNavItem(
                                1,
                                Icons.login_rounded,
                                Icons.login_outlined,
                                "Login",
                              ),
                            ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData activeIcon,
    IconData inactiveIcon,
    String label,
  ) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () {
        if (_currentIndex != index) {
          final savedName = Preferences.getString(Preferences.keyActiveLocName);
          final savedAddress =
              Preferences.getString(Preferences.keyActiveLocAddress);
          if (savedName.isNotEmpty &&
              !savedName.contains("Tap to Set") &&
              savedAddress.isNotEmpty &&
              !savedAddress.contains("Select location")) {
            _currentLocation = LocationModel(
              id: Preferences.getString(Preferences.keyActiveLocId, "loc_saved"),
              name: savedName,
              address: savedAddress,
              latitude:
                  Preferences.getDouble(Preferences.keyActiveLocLat, 17.495101),
              longitude:
                  Preferences.getDouble(Preferences.keyActiveLocLng, 78.367535),
              landmark: "",
              distanceKm:
                  Preferences.getDouble(Preferences.keyActiveLocDist, 0.8),
              isServiceable: Preferences.getBoolean(
                Preferences.keyActiveLocServiceable,
                true,
              ),
              etaMinutes: Preferences.getInt(Preferences.keyActiveLocEta, 10),
            );
          }
        }
        setState(() => _currentIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00FF87).withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF00FF87).withOpacity(0.4),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? activeIcon : inactiveIcon,
              color: isSelected ? const Color(0xFF00FF87) : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00FF87) : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
