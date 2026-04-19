import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../common/config.dart';
import '../../common/constants.dart';
import '../../models/app_model.dart';
import '../../models/category/category_model.dart';
import '../../models/entities/back_drop_arguments.dart';
import '../../modules/dynamic_layout/background/background.dart';
import '../../modules/dynamic_layout/config/app_config.dart';
import '../../routes/flux_navigate.dart';
import '../../widgets/common/flux_image.dart';
import '../base_screen.dart';
import '../common/app_bar_mixin.dart';

class DynamicScreen extends StatefulWidget {
  final String? previewKey;
  final configs;

  const DynamicScreen({this.configs, this.previewKey});

  @override
  State<StatefulWidget> createState() => DynamicScreenState();
}

class DynamicScreenState extends BaseScreen<DynamicScreen>
    with AutomaticKeepAliveClientMixin<DynamicScreen>, AppBarMixin {
  static BuildContext? homeContext;
  static late BuildContext loadingContext;

  // ── Config helpers ────────────────────────────────────────────────────────

  Map get _resolvedConfigs {
    final configs = widget.configs;
    if (configs == null) return {};
    if (configs['HorizonLayout'] != null) return configs as Map;
    if (configs['configs'] != null) return configs['configs'] as Map;
    return configs as Map;
  }

  List get _horizonLayout =>
      (_resolvedConfigs['HorizonLayout'] as List?) ?? [];

  bool get emptyHorizontal => _horizonLayout.isEmpty;

  bool get _isCollectionTab =>
      _horizonLayout.any((e) => e['layout'] == 'category') &&
          !_horizonLayout.any((e) => e['layout'] == 'threeColumn');

  // ── Collection screen state ───────────────────────────────────────────────

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _sortAZ = false;

  // ── Parse HorizonLayout ───────────────────────────────────────────────────

  List<Map> get _rawItems {
    final items = <Map>[];
    for (final block in _horizonLayout) {
      if (block['layout'] == 'category') {
        items.addAll(List<Map>.from(block['items'] ?? []));
      }
    }
    return items;
  }

  String get _title {
    for (final block in _horizonLayout) {
      if (block['layout'] == 'header_text') {
        return block['title'] ?? '';
      }
    }
    return '';
  }

  List<_CollectionItem> _buildItems(Map categoryList) {
    return _rawItems.map((item) {
      final catId = item['category'] as String? ?? '';
      final shortId = catId.replaceAll('gid://shopify/Collection/', '');
      final base64Id = base64Encode(utf8.encode(catId));

      final cat = categoryList[catId] ??
          categoryList[shortId] ??
          categoryList[base64Id];

      final image = (item['image'] as String?)?.isNotEmpty == true
          ? item['image'] as String
          : cat?.image ?? '';

      final name = (item['title'] as String?)?.isNotEmpty == true
          ? item['title'] as String
          : (item['name'] as String?)?.isNotEmpty == true
          ? item['name'] as String
          : cat?.name ?? shortId;

      return _CollectionItem(
        id: catId,
        name: name,
        image: image,
        configJson: item,
      );
    }).toList();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  bool get wantKeepAlive => true;

  StreamSubscription? _sub;

  @override
  void dispose() {
    printLog('[Home] dispose');
    _searchController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Future<void> afterFirstLayout(BuildContext context) async {
    homeContext = context;
  }

  // ── Loading dialog ────────────────────────────────────────────────────────

  static void showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        loadingContext = context;
        return Center(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(5.0),
            ),
            padding: const EdgeInsets.all(50.0),
            child: kLoadingWidget(context),
          ),
        );
      },
    );
  }

  static void hideLoading() {
    Navigator.of(loadingContext).pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    printLog('[Dynamic Screen] build');

    final configs = _resolvedConfigs;
    if (configs.isEmpty) return const SizedBox();

    if (_isCollectionTab) {
      return _buildCollectionScreen(context);
    }

    return Selector<AppModel, AppConfig?>(
      selector: (_, model) => model.appConfig,
      builder: (__, appConfig, child) {
        if (appConfig == null) return kLoadingWidget(context);

        final pageConfig = AppConfig.fromJson(configs);
        final isStickyHeader = appConfig.settings.stickyHeader;

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.background,
          body: Stack(
            children: [
              if (configs['Background'] != null)
                isStickyHeader
                    ? SafeArea(
                  child: HomeBackground(config: pageConfig.background),
                )
                    : HomeBackground(config: pageConfig.background),
            ],
          ),
        );
      },
    );
  }

  // ── Collection screen ─────────────────────────────────────────────────────

  Widget _buildCollectionScreen(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final categoryList = Provider.of<CategoryModel>(context).categoryList;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    var items = _buildItems(categoryList);

    // Filter
    if (_searchQuery.isNotEmpty) {
      items = items
          .where((e) =>
          e.name.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    // Sort
    if (_sortAZ) {
      items.sort((a, b) => a.name.compareTo(b.name));
    }

    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final textDir = isRtl ? TextDirection.rtl : TextDirection.ltr;
    final titleAlign = isRtl
        ? AlignmentDirectional.centerStart
        : AlignmentDirectional.centerEnd;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false, // handled manually via bottomInset
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Title ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: titleAlign,
                child: Text(
                  _title,
                  textDirection: textDir,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // ── Search + Sort ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                textDirection: textDir,
                children: [

                  // Sort toggle FIRST in widget tree →
                  // Flutter places it on the leading side for the given textDirection
                  // so it appears LEFT in RTL and RIGHT in LTR
                  GestureDetector(
                    onTap: () => setState(() => _sortAZ = !_sortAZ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: _sortAZ
                            ? primary.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _sortAZ ? primary : theme.dividerColor,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sort_by_alpha_rounded,
                            size: 18,
                            color: _sortAZ ? primary : theme.hintColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isRtl ? 'أ-ي' : 'A-Z',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _sortAZ ? primary : theme.hintColor,
                              fontWeight: _sortAZ
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Search field SECOND in widget tree →
                  // appears RIGHT in RTL and LEFT in LTR
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      textDirection: textDir,
                      textAlign: isRtl ? TextAlign.right : TextAlign.left,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        hintText: isRtl ? 'بحث' : 'Search',
                        hintTextDirection: textDir,
                        prefixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                          icon: const Icon(
                              Icons.close_rounded,
                              size: 18),
                          onPressed: () => setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          }),
                        )
                            : const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor:
                        theme.colorScheme.surfaceVariant.withOpacity(0.5),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ],
              ),
            ),

            // ── Result count ────────────────────────────────────
            if (_searchQuery.isNotEmpty)
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: Align(
                  alignment: titleAlign,
                  child: Text(
                    isRtl
                        ? '${items.length} نتيجة'
                        : '${items.length} results',
                    textDirection: textDir,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

            // ── Grid ───────────────────────────────────────────
            Expanded(
              child: items.isEmpty
                  ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 48, color: theme.hintColor),
                    const SizedBox(height: 12),
                    Text(
                      isRtl ? 'لا توجد نتائج' : 'No results found',
                      textDirection: textDir,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              )
                  : GridView.builder(
                // bottom padding = fixed 8 + system nav bar height
                padding:
                EdgeInsets.fromLTRB(16, 4, 16, 8 + bottomInset),
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.92,
                ),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _CollectionCard(
                    item: item,
                    isRtl: isRtl,
                    onTap: () => FluxNavigate.pushNamed(
                      RouteList.backdrop,
                      arguments: BackDropArguments(
                        config: item.configJson,
                        cateName: item.name,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _CollectionItem {
  final String id;
  final String name;
  final String image;
  final Map configJson;

  const _CollectionItem({
    required this.id,
    required this.name,
    required this.image,
    required this.configJson,
  });
}

// ── Card widget ───────────────────────────────────────────────────────────────

class _CollectionCard extends StatelessWidget {
  final _CollectionItem item;
  final bool isRtl;
  final VoidCallback onTap;

  const _CollectionCard({
    required this.item,
    required this.isRtl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          // ── Circle Image ───────────────────────────────────
      // AFTER
      Expanded(
      child: Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipOval(
            child: item.image.isNotEmpty
                ? FluxImage(
              imageUrl: item.image,
              fit: BoxFit.cover,
            )
                : Container(
              color: theme.colorScheme.surfaceVariant,
              child: Icon(
                Icons.category_outlined,
                color: theme.hintColor.withOpacity(0.4),
              ),
            ),
          ),
        ),
      ),
    ),
    ),

          // ── Name ──────────────────────────────────────────
          const SizedBox(height: 6),
          Text(
            item.name,
            textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}