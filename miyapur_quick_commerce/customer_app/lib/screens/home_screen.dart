import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/liquid_toast.dart';
import 'select_location_screen.dart';

class HomeScreen extends StatefulWidget {
  final LocationModel currentLocation;
  final List<CartItemModel> cartItems;
  final String? userId;
  final bool isLoggedIn;
  final Set<String> favoriteProductIds;
  final Function(String productId)? onToggleFavorite;
  final Function(LocationModel location) onLocationChanged;
  final Function(ProductModel product, ProductVariantModel variant) onAddToCart;
  final VoidCallback onCartUpdated;
  final VoidCallback onOpenCart;
  final VoidCallback? onOpenLogin;

  const HomeScreen({
    super.key,
    required this.currentLocation,
    required this.cartItems,
    required this.userId,
    this.isLoggedIn = false,
    this.favoriteProductIds = const {},
    this.onToggleFavorite,
    required this.onLocationChanged,
    required this.onAddToCart,
    required this.onCartUpdated,
    required this.onOpenCart,
    this.onOpenLogin,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSundayMode = false;
  bool _isLoading = true;
  String _selectedCategory = "all";
  String _sortBy = "popular"; // "popular", "price_low", "price_high", "name"
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  List<ProductModel> _allProducts = [];
  final Map<String, ProductVariantModel> _selectedVariants = {};

  final List<Map<String, String>> _shopCategoryIcons = [
    {"id": "all", "label": "All Items", "icon": "⚡", "bg": "0xFFE6F4EA"},
    {"id": "favorites", "label": "Favorites", "icon": "❤️", "bg": "0xFFFEE2E2"},
    {"id": "veg", "label": "Veggies", "icon": "🥬", "bg": "0xFFDCFCE7"},
    {"id": "leafy", "label": "Greens", "icon": "🍃", "bg": "0xFFE0E7FF"},
    {"id": "aromatics", "label": "Aromatics", "icon": "🌶️", "bg": "0xFFFEE2E2"},
    {"id": "exotics", "label": "Exotics", "icon": "🥗", "bg": "0xFFFEF3C7"},
    {"id": "meat", "label": "Chicken", "icon": "🍗", "bg": "0xFFFFEDD5"},
    {"id": "seafood", "label": "Fish", "icon": "🐟", "bg": "0xFFE0F2FE"},
  ];

  @override
  void initState() {
    super.initState();
    _isSundayMode = DateTime.now().weekday == 7;
    _loadProducts();
  }

  void _loadProducts() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getProducts(forceSunday: _isSundayMode);
    if (!mounted) return;
    setState(() {
      _allProducts = res['products'] as List<ProductModel>;
      for (var p in _allProducts) {
        if (p.variants.isNotEmpty && !_selectedVariants.containsKey(p.id)) {
          _selectedVariants[p.id] = p.variants.first;
        }
      }
      _isLoading = false;
    });
  }

  int _getCartQuantity(ProductModel product, ProductVariantModel variant) {
    for (var item in widget.cartItems) {
      if (item.product.id == product.id && item.selectedVariant.id == variant.id) {
        return item.quantity;
      }
    }
    return 0;
  }

  void _removeFromCart(ProductModel product, ProductVariantModel variant) {
    setState(() {
      for (var i = 0; i < widget.cartItems.length; i++) {
        if (widget.cartItems[i].product.id == product.id &&
            widget.cartItems[i].selectedVariant.id == variant.id) {
          if (widget.cartItems[i].quantity > 1) {
            widget.cartItems[i].quantity--;
          } else {
            widget.cartItems.removeAt(i);
          }
          widget.onCartUpdated();
          return;
        }
      }
    });
  }

  double get cartTotal => widget.cartItems.fold(0.0, (acc, item) => acc + item.totalPrice);
  int get cartCount => widget.cartItems.fold(0, (acc, item) => acc + item.quantity);

  List<ProductModel> get filteredProducts {
    List<ProductModel> list = _allProducts.where((p) {
      if (_selectedCategory == "favorites") return widget.favoriteProductIds.contains(p.id);
      if (_selectedCategory == "veg") return p.categoryId == "cat_veg" || (!p.isSundayOnly && p.categoryId != "cat_leafy" && p.categoryId != "cat_aromatics");
      if (_selectedCategory == "leafy") return p.categoryId == "cat_leafy";
      if (_selectedCategory == "aromatics") return p.categoryId == "cat_aromatics";
      if (_selectedCategory == "exotics") return p.categoryId == "cat_exotics";
      if (_selectedCategory == "meat" || _selectedCategory == "seafood") return p.isSundayOnly || p.categoryId == "cat_chicken" || p.categoryId == "cat_fish";
      return true;
    }).toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) => p.name.toLowerCase().contains(q) || p.description.toLowerCase().contains(q)).toList();
    }

    if (_sortBy == "price_low") {
      list.sort((a, b) {
        double priceA = (_selectedVariants[a.id] ?? a.variants.first).price;
        double priceB = (_selectedVariants[b.id] ?? b.variants.first).price;
        return priceA.compareTo(priceB);
      });
    } else if (_sortBy == "price_high") {
      list.sort((a, b) {
        double priceA = (_selectedVariants[a.id] ?? a.variants.first).price;
        double priceB = (_selectedVariants[b.id] ?? b.variants.first).price;
        return priceB.compareTo(priceA);
      });
    } else if (_sortBy == "name") {
      list.sort((a, b) => a.name.compareTo(b.name));
    }

    return list;
  }

  void _openSelectLocationScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectLocationScreen(
          currentLocation: widget.currentLocation,
          userId: widget.userId,
          isLoggedIn: widget.isLoggedIn,
          onSelectLocation: widget.onLocationChanged,
          onOpenLogin: widget.onOpenLogin,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Column(
              children: [
                // Top Light Swiggy-Style Location Header (Exact Image 1 layout)
                _buildSwiggyHeader(),

                // Search Bar directly on Home Screen (Exact Image 1 layout)
                _buildSearchBar(),

                // Visual Shop Categories Icons Grid/Slider
                _buildShopCategoryIconsBar(),

                // Products Grid
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
                      : GridView.builder(
                          padding: EdgeInsets.fromLTRB(16, 10, 16, widget.cartItems.isEmpty ? 100 : 160),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.84,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = filteredProducts[index];
                            final selectedVar = _selectedVariants[product.id] ?? product.variants.first;
                            final qty = _getCartQuantity(product, selectedVar);

                            return _buildLightProductCard(product, selectedVar, qty);
                          },
                        ),
                ),
              ],
            ),

            // Floating Light Cart Bar
            if (widget.cartItems.isNotEmpty)
              Positioned(
                left: 16,
                right: 16,
                bottom: 90,
                child: GestureDetector(
                  onTap: widget.onOpenCart,
                  child: Container(
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF059669).withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                "$cartCount ITEMS",
                                style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.w900, fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              "₹${cartTotal.toStringAsFixed(0)}",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
                            ),
                          ],
                        ),
                        const Row(
                          children: [
                            Text(
                              "View Basket",
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Exact Swiggy Instamart Top Location Header (Image 1 style)
  Widget _buildSwiggyHeader() {
    final etaText = "${widget.currentLocation.etaMinutes} Mins >";
    final addressSubtitle = widget.currentLocation.name.isNotEmpty
        ? "To ${widget.currentLocation.name}, ${widget.currentLocation.address}"
        : "To ${widget.currentLocation.address}";

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: GlassCard(
        blur: 16,
        opacity: 0.92,
        borderRadius: 22,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderColor: Colors.grey.shade200,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: InkWell(
                onTap: _openSelectLocationScreen,
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          etaText,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      addressSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 10),

            // Top Right Menu/Avatar Circle Button
            GestureDetector(
              onTap: _openSelectLocationScreen,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(Icons.segment_rounded, color: Color(0xFF111827), size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Exact Swiggy Instamart Search Bar (Image 1 style)
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: GlassCard(
        blur: 14,
        opacity: 0.95,
        borderRadius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        borderColor: Colors.grey.shade300,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Color(0xFF111827), fontSize: 13),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: "Search for 'Sugar Free Soda' or vegetables...",
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const Icon(Icons.search_rounded, color: Colors.black54, size: 20),
            const SizedBox(width: 10),
            Container(
              width: 1,
              height: 18,
              color: Colors.grey.shade300,
            ),
            const SizedBox(width: 10),
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined, color: Colors.black54, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() => _selectedCategory = "favorites"),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortModalSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Sort Products By", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF111827))),
            const SizedBox(height: 14),
            ListTile(
              leading: const Icon(Icons.star_rounded, color: Color(0xFF059669)),
              title: const Text("Popularity & Relevance"),
              trailing: _sortBy == "popular" ? const Icon(Icons.check_circle, color: Color(0xFF059669)) : null,
              onTap: () {
                setState(() => _sortBy = "popular");
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_downward_rounded, color: Color(0xFF059669)),
              title: const Text("Price: Low to High"),
              trailing: _sortBy == "price_low" ? const Icon(Icons.check_circle, color: Color(0xFF059669)) : null,
              onTap: () {
                setState(() => _sortBy = "price_low");
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF059669)),
              title: const Text("Price: High to Low"),
              trailing: _sortBy == "price_high" ? const Icon(Icons.check_circle, color: Color(0xFF059669)) : null,
              onTap: () {
                setState(() => _sortBy = "price_high");
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha_rounded, color: Color(0xFF059669)),
              title: const Text("Name (A to Z)"),
              trailing: _sortBy == "name" ? const Icon(Icons.check_circle, color: Color(0xFF059669)) : null,
              onTap: () {
                setState(() => _sortBy = "name");
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShopCategoryIconsBar() {
    return Container(
      height: 80,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _shopCategoryIcons.length + 1,
        itemBuilder: (context, index) {
          if (index == _shopCategoryIcons.length) {
            return GestureDetector(
              onTap: _showSortModalSheet,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _sortBy != "popular" ? const Color(0xFF059669) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _sortBy != "popular" ? const Color(0xFF059669) : Colors.grey.shade300,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _sortBy != "popular" ? Colors.white.withOpacity(0.2) : Colors.green.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.tune_rounded, size: 18, color: _sortBy != "popular" ? Colors.white : const Color(0xFF059669)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Sort",
                      style: TextStyle(
                        color: _sortBy != "popular" ? Colors.white : const Color(0xFF111827),
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final cat = _shopCategoryIcons[index];
          final isSelected = _selectedCategory == cat["id"];
          final bgColor = Color(int.parse(cat["bg"]!));

          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat["id"]!),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF059669) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? const Color(0xFF059669) : Colors.grey.shade200,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.2) : bgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Text(cat["icon"]!, style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cat["label"]!,
                    style: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF111827),
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLightProductCard(ProductModel product, ProductVariantModel selectedVar, int qty) {
    return GlassCard(
      blur: 12,
      opacity: 0.95,
      borderRadius: 20,
      padding: EdgeInsets.zero,
      borderColor: Colors.grey.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(
                  product.imageUrl,
                  height: 98,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 98,
                    color: Colors.green.shade50,
                    child: const Icon(Icons.eco_rounded, size: 40, color: Color(0xFF059669)),
                  ),
                ),
              ),
              if (product.isSundayOnly)
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _isSundayMode ? Colors.red.shade700 : const Color(0xFF059669),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _isSundayMode ? "SUNDAY LIVE" : "SUNDAY PREORDER",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: GestureDetector(
                  onTap: () {
                    widget.onToggleFavorite?.call(product.id);
                    final isNowFav = !(widget.favoriteProductIds.contains(product.id));
                    LiquidToast.show(
                      context,
                      message: isNowFav ? "Added ${product.name} to Favorites ❤️" : "Removed from Favorites",
                      icon: isNowFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      accentColor: isNowFav ? Colors.redAccent : Colors.grey.shade700,
                    );
                  },
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.white.withOpacity(0.9),
                    child: Icon(
                      widget.favoriteProductIds.contains(product.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 16,
                      color: widget.favoriteProductIds.contains(product.id) ? Colors.redAccent : Colors.black45,
                    ),
                  ),
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 32,
                  child: Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Color(0xFF111827),
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Variant Selector Dropdown
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedVar.id,
                      isDense: true,
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.arrow_drop_down_rounded, size: 16, color: Colors.black87),
                      style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
                      items: product.variants.map((v) {
                        return DropdownMenuItem<String>(
                          value: v.id,
                          child: Text(v.weightLabel, style: const TextStyle(color: Colors.black87)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedVariants[product.id] = product.variants.firstWhere((v) => v.id == val);
                          });
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "₹${selectedVar.price.toStringAsFixed(0)}",
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Color(0xFF059669),
                      ),
                    ),

                    qty == 0
                        ? SizedBox(
                            height: 28,
                            child: ElevatedButton(
                              onPressed: () {
                                widget.onAddToCart(product, selectedVar);
                                LiquidToast.show(
                                  context,
                                  message: "Added ${product.name} to basket ⚡",
                                  icon: Icons.shopping_basket_rounded,
                                  accentColor: const Color(0xFF059669),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                              child: const Text(
                                "ADD",
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
                              ),
                            ),
                          )
                        : Container(
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 12, color: Colors.white),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24),
                                  onPressed: () => _removeFromCart(product, selectedVar),
                                ),
                                Text(
                                  "$qty",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 12, color: Colors.white),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24),
                                  onPressed: () => widget.onAddToCart(product, selectedVar),
                                ),
                              ],
                            ),
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
}
