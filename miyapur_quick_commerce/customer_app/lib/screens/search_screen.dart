import 'package:flutter/material.dart';
import '../models/models.dart';
import '../widgets/glass_card.dart';

class SearchScreen extends StatefulWidget {
  final List<ProductModel> products;
  final Function(ProductModel p, ProductVariantModel v) onAddToCart;

  const SearchScreen({
    super.key,
    required this.products,
    required this.onAddToCart,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = "";

  final List<String> _trendingTags = [
    "Farm Tomatoes",
    "Kurnool Onions",
    "Sunday Tender Chicken",
    "Godavari Rohu Fish",
    "Hydroponic Palak",
    "Fresh Carrots"
  ];

  List<ProductModel> get _searchResults {
    if (_query.trim().isEmpty) return [];
    final q = _query.toLowerCase().trim();
    return widget.products.where((p) =>
      p.name.toLowerCase().contains(q) || p.description.toLowerCase().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Container(
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                )
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(color: Color(0xFF111827), fontSize: 14),
              onChanged: (val) => setState(() => _query = val),
              decoration: InputDecoration(
                hintText: "Search vegetables, chicken, river fish...",
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF059669)),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.black54),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = "");
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        body: _query.isEmpty
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Trending Searches",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _trendingTags.map((tag) {
                        return GestureDetector(
                          onTap: () {
                            _searchCtrl.text = tag;
                            setState(() => _query = tag);
                          },
                          child: GlassCard(
                            blur: 12,
                            opacity: 0.9,
                            borderRadius: 16,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            borderColor: Colors.grey.shade200,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.trending_up_rounded, size: 14, color: Color(0xFF059669)),
                                const SizedBox(width: 6),
                                Text(tag, style: const TextStyle(fontSize: 12, color: Color(0xFF111827), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              )
            : _searchResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text("No items found for '$_query'", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _searchResults.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final product = _searchResults[index];
                      final firstVariant = product.variants.first;

                      return GlassCard(
                        blur: 16,
                        opacity: 0.9,
                        borderRadius: 20,
                        padding: const EdgeInsets.all(12),
                        borderColor: Colors.grey.shade200,
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                product.imageUrl,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.green.shade50,
                                  child: const Icon(Icons.eco_rounded, color: Color(0xFF059669)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF111827)),
                                  ),
                                  Text(
                                    firstVariant.weightLabel,
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                                  ),
                                  Text(
                                    "₹${firstVariant.price.toStringAsFixed(0)}",
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF059669)),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                widget.onAddToCart(product, firstVariant);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text("Added ${product.name} to basket"),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              child: const Text("ADD", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
