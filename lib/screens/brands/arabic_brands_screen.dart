import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../../common/constants.dart';
import '../../generated/l10n.dart';
import '../../routes/flux_navigate.dart';
import '../../services/service_config.dart';
import '../brand/model/brand_model.dart';

class ArabicBrandsScreen extends StatefulWidget {
  const ArabicBrandsScreen({super.key});

  @override
  State<ArabicBrandsScreen> createState() => _ArabicBrandsScreenState();
}

class _ArabicBrandsScreenState extends State<ArabicBrandsScreen> {
  List<String> allBrandsList = [];
  List<String> brandsList = [];
  bool _isLoading = false;
  bool _isAZ = false;

  final TextEditingController filterController = TextEditingController();

  // ── Brand style generator ──────────────────────────────────────────────────
  static const List<_BrandStyle> _styles = [
    _BrandStyle(bg: Color(0xFF1a1a2e), fg: Color(0xFFe0e0ff), font: 'serif',  letterSpacing: 1.5,  weight: FontWeight.w700),
    _BrandStyle(bg: Color(0xFFfff8e1), fg: Color(0xFFf57f17), font: 'sans',   letterSpacing: -0.5, weight: FontWeight.w800),
    _BrandStyle(bg: Color(0xFFe8f5e9), fg: Color(0xFF2e7d32), font: 'mono',   letterSpacing: 2.0,  weight: FontWeight.w700),
    _BrandStyle(bg: Color(0xFFfce4ec), fg: Color(0xFFc62828), font: 'serif',  letterSpacing: 1.0,  weight: FontWeight.w900),
    _BrandStyle(bg: Color(0xFFe3f2fd), fg: Color(0xFF0d47a1), font: 'sans',   letterSpacing: 0.5,  weight: FontWeight.w700),
    _BrandStyle(bg: Color(0xFFf3e5f5), fg: Color(0xFF6a1b9a), font: 'serif',  letterSpacing: 1.0,  weight: FontWeight.w800),
    _BrandStyle(bg: Color(0xFFe0f2f1), fg: Color(0xFF00695c), font: 'mono',   letterSpacing: 1.5,  weight: FontWeight.w700),
    _BrandStyle(bg: Color(0xFFfff3e0), fg: Color(0xFFe65100), font: 'sans',   letterSpacing: 0.0,  weight: FontWeight.w900),
    _BrandStyle(bg: Color(0xFF212121), fg: Color(0xFFf5f5f5), font: 'serif',  letterSpacing: 3.0,  weight: FontWeight.w300),
    _BrandStyle(bg: Color(0xFFe8eaf6), fg: Color(0xFF283593), font: 'sans',   letterSpacing: 0.5,  weight: FontWeight.w800),
    _BrandStyle(bg: Color(0xFFfafafa), fg: Color(0xFF212121), font: 'mono',   letterSpacing: 1.0,  weight: FontWeight.w700),
    _BrandStyle(bg: Color(0xFF004d40), fg: Color(0xFFb2dfdb), font: 'serif',  letterSpacing: 2.0,  weight: FontWeight.w600),
  ];

  _BrandStyle _styleFor(String name) {
    final index = name.codeUnits.fold(0, (a, b) => a + b) % _styles.length;
    return _styles[index];
  }

  TextStyle _textStyleFor(_BrandStyle style, double fontSize) {
    switch (style.font) {
      case 'serif':
        return TextStyle(
          color: style.fg,
          fontSize: fontSize,
          fontWeight: style.weight,
          letterSpacing: style.letterSpacing,
          fontFamily: 'Georgia',
        );
      case 'mono':
        return TextStyle(
          color: style.fg,
          fontSize: fontSize,
          fontWeight: style.weight,
          letterSpacing: style.letterSpacing,
          fontFamily: 'Courier',
        );
      default:
        return GoogleFonts.cairo(
          color: style.fg,
          fontSize: fontSize,
          fontWeight: style.weight,
          letterSpacing: style.letterSpacing,
        );
    }
  }
  // ──────────────────────────────────────────────────────────────────────────

  void _sortList() {
    if (_isAZ) {
      brandsList.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else {
      brandsList.sort((a, b) => b.toLowerCase().compareTo(a.toLowerCase()));
    }
  }

  void onFilter(String? value) {
    if (value != null) {
      brandsList = allBrandsList
          .where((e) => e.toLowerCase().contains(value.toLowerCase()))
          .toList();
      _sortList();
      setState(() {});
    }
  }

  Future<void> getAllBrands() async {
    if (!mounted) return;
    try {
      setState(() {
        _isLoading = true;
        brandsList.clear();
      });

      final url = '${ServerConfig().url}/pages/vendors'.toUri()!;
      final response = await http.get(url);
      final List data = jsonDecode(response.body);

      for (var e in data) {
        final name = e.toString();
        brandsList.add(name);
        MyBrandModel.fromShopifyJson(e);
      }

      allBrandsList = List.from(brandsList);
      _sortList();
    } catch (e) {
      debugPrint('getAllBrands error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void gotoSearch(String keyword) {
    FluxNavigate.pushNamed(RouteList.search, arguments: {
      'keyword': keyword,
      'isFromBrands': true,
    });
  }

  @override
  void initState() {
    super.initState();
    getAllBrands();
  }

  @override
  void dispose() {
    filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Center(
          child: Text(
            S.of(context).allBrands,
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
            child: Row(
              children: [
                // ── A-Z Toggle ───────────────────────────────────────────
                Row(
                  children: [
                    Switch(
                      value: _isAZ,
                      onChanged: (v) {
                        setState(() {
                          _isAZ = v;
                          if (filterController.text.isEmpty) {
                            brandsList = List.from(allBrandsList);
                          } else {
                            brandsList = allBrandsList
                                .where((e) => e.toLowerCase().contains(
                                filterController.text.toLowerCase()))
                                .toList();
                          }
                          _sortList();
                        });
                      },
                    ),
                    Text(
                      _isAZ ? 'أ-ي' : 'ي-أ',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                // ── Search ───────────────────────────────────────────────
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Colors.grey, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: filterController,
                            onChanged: onFilter,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: 'بحث',
                              hintStyle:
                              GoogleFonts.cairo(color: Colors.grey),
                              isDense: true,
                            ),
                          ),
                        ),
                        if (filterController.text.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              filterController.clear();
                              onFilter('');
                            },
                            child: const Icon(Icons.close,
                                color: Colors.grey, size: 18),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: getAllBrands,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : brandsList.isEmpty
            ? Center(
          child: Text(
            'لا توجد نتائج',
            style: GoogleFonts.cairo(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        )
            : GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 1,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: brandsList.length,
          itemBuilder: (context, index) {
            final brand = brandsList[index];
            final style = _styleFor(brand);
            return GestureDetector(
              onTap: () => gotoSearch(brand),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Circle logo ──────────────────────────────
                  Container(
                    width: 75,
                    height: 75,
                    decoration: BoxDecoration(
                      color: style.bg,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Center(
                      child: Text(
                        brand,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _textStyleFor(style, 9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // ── Brand name below ─────────────────────────
                  Text(
                    brand,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color,
                    ),
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

class _BrandStyle {
  final Color bg;
  final Color fg;
  final String font;
  final double letterSpacing;
  final FontWeight weight;

  const _BrandStyle({
    required this.bg,
    required this.fg,
    required this.font,
    required this.letterSpacing,
    required this.weight,
  });
}