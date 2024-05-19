import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../common/constants.dart';
import '../../common/tools.dart';
import '../../generated/l10n.dart';
import '../../models/index.dart' show Product;
import '../../services/service_config.dart';
import '../../services/services.dart';
import '../../widgets/product/dialog_add_to_cart.dart';
import '../../widgets/product/widgets/pricing.dart';

class EmptyWishlist extends StatelessWidget {
  final VoidCallback onShowHome;
  final VoidCallback onSearchForItem;

  const EmptyWishlist({
    required this.onShowHome,
    required this.onSearchForItem,
  });

  @override
  Widget build(BuildContext context) {
    return  SizedBox(
      width: MediaQuery.of(context).size.width,
      // height:  MediaQuery.of(context).size.height,
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width:
          MediaQuery.of(context).size.width / (2 / (MediaQuery.of(context).size.height / MediaQuery.of(context).size.width)),

          child: Stack(
            children: <Widget>[
              // Center(
              //   child: Image.asset(
              //     'assets/images/empty_search.png',
              //     width: 120,
              //     height: 120,
              //   ),
              // ),
              Positioned(
                top: 80,
                bottom: 20,
                left: 1,
                right: 1,
                child:  SvgPicture.asset(
//////

                    color: Theme.of(context).colorScheme.primary,
                    // width: 300,
                    // height: 300,
                    'assets/images/whishlist.svg'),),

              Column(
                children: <Widget>[

                  const SizedBox(height: 320),
                  Center(child:  Text(              S.of(context).noFavoritesYet,
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center),)
                  ,


                  const SizedBox(height: 20),
                  // Padding(
                  //   padding: const EdgeInsets.symmetric(horizontal: 30),
                  //   child: Text(S.of(context).emptyCartSubtitle,
                  //       style: Theme.of(context).textTheme.bodyMedium,
                  //       textAlign: TextAlign.center),
                  // ),
                  const SizedBox(height: 50),
                  SizedBox(width: MediaQuery.of(context).size.width,),


                  // Padding(
                  //   padding: const EdgeInsets.only(
                  //     top: 16.0,
                  //     right: 16,
                  //     left: 16,
                  //   ),
                  //   child: SizedBox(
                  //     height: 45,
                  //     child: ElevatedButton(
                  //       onPressed: () => _openShopping(context),
                  //       style: ElevatedButton.styleFrom(
                  //         minimumSize: const Size.fromHeight(50),
                  //         backgroundColor: Theme.of(context).primaryColor,
                  //         foregroundColor: Colors.white,
                  //
                  //         // textStyle: const TextStyle(
                  //         //   letterSpacing: 0.8,
                  //         //   // fontSize: 11,
                  //         //   // fontWeight: FontWeight.w600,
                  //         // ),
                  //         elevation: 0,
                  //       ),
                  //       child: Row(
                  //         mainAxisSize: MainAxisSize.min,
                  //         children: [
                  //           Text(S.of(context).startShopping.toUpperCase(),style: Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.white )
                  //     ),
                  //           const Icon(Icons.navigate_next, size: 16),
                  //         ],
                  //       ),
                  //     ),
                  //   ),
                  // ),
                  // Padding(
                  //   padding: const EdgeInsets.all(16.0),
                  //   child: SizedBox(
                  //     height: 45,
                  //     child: ButtonTheme(
                  //       height: 44,
                  //       child: ElevatedButton(
                  //         style: ElevatedButton.styleFrom(
                  //           elevation: 0,
                  //           minimumSize: const Size.fromHeight(50),
                  //           // foregroundColor: kGrey400,
                  //           backgroundColor: Theme.of(context).brightness == Brightness.dark?Color(0xff292d39):Colors.white,
                  //         ),
                  //         onPressed: () {
                  //           NavigateTools.navigateToRootTab(
                  //             context,
                  //             RouteList.search,
                  //           );
                  //         },
                  //         child:
                  //             Text(S.of(context).searchForItems.toUpperCase(),style: Theme.of(context).textTheme.bodySmall?.copyWith(color:
                  //             Theme.of(context).brightness == Brightness.dark?Colors.white:Colors.teal[900],)
                  //             ),
                  //       ),
                  //     ),
                  //   ),
                  // ),
                ],
              )
            ],
          ),
        ),
      ),
    );


      Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: <Widget>[
          const SizedBox(height: 80),
          SvgPicture.asset(
//////

              color: Theme.of(context).colorScheme.primary,
              width: 300,
              height: 300,
              'assets/images/whishlist.svg'),
          // Image.asset(
          //   'assets/images/empty_search.png',
          //   width: 120,
          //   height: 120,
          // ),
          // const SizedBox(height: 20),
          Text(
            S.of(context).noFavoritesYet,
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 15),
          // Text(S.of(context).emptyWishlistSubtitle,
          //     style: const TextStyle(fontSize: 14),
          //     textAlign: TextAlign.center),
          // const SizedBox(height: 30),
          // Row(
          //   children: [
          //     Expanded(
          //       child: ButtonTheme(
          //         height: 45,
          //         child: ElevatedButton(
          //           //
          //           style: ElevatedButton.styleFrom(
          //             foregroundColor: Colors.white,
          //             backgroundColor: Theme.of(context).primaryColor,
          //           ),
          //           onPressed: onShowHome,
          //           child: Text(
          //             S.of(context).startShopping.toUpperCase(),
          //             style: Theme.of(context).textTheme.bodySmall,
          //           ),
          //         ),
          //       ),
          //     )
          //   ],
          // ),
          // const SizedBox(height: 10),
          // Row(
          //   children: [
          //     Expanded(
          //       child: ButtonTheme(
          //         height: 44,
          //         child: ElevatedButton(
          //
          //           style: ElevatedButton.styleFrom(
          //             // foregroundColor: kGrey400,
          //             backgroundColor: Theme.of(context).brightness == Brightness.dark?Color(0xff292d39):Colors.white,
          //           ),
          //           onPressed: onSearchForItem,
          //           child: Text(S.of(context).searchForItems.toUpperCase(),style: Theme.of(context).textTheme.bodySmall,),
          //         ),
          //       ),
          //     )
          //   ],
          // )
        ],
      ),
    );
  }
}

class WishlistItem extends StatelessWidget {
  const WishlistItem({required this.product, this.onAddToCart, this.onRemove});

  final Product product;
  final VoidCallback? onAddToCart;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final localTheme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(children: [
          InkWell(
            onTap: () {
              Navigator.of(context).pushNamed(
                RouteList.productDetail,
                arguments: product,
              );
            },
            child: Row(
              key: ValueKey(product.id),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            SizedBox(
                              width: constraints.maxWidth * 0.25,
                              height: constraints.maxWidth * 0.3,
                              child: ImageResize(
                                  url: product.imageFeature,
                                  size: kSize.medium),
                            ),
                            const SizedBox(width: 16.0),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name ?? '',
                                    style: localTheme.textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 7),
                                  ProductPricing(
                                    product: product,
                                    hide: false,
                                  ),
                                  const SizedBox(height: 10),
                                  if (Services()
                                          .widget
                                          .enableShoppingCart(product) &&
                                      !ServerConfig().isListingType)
                                    SizedBox(
                                      height: 28,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          backgroundColor:
                                              localTheme.primaryColor,
                                        ),
                                        onPressed: () => DialogAddToCart.show(
                                            context,
                                            product: product),
                                        child: (product.isPurchased &&
                                                product.isDownloadable!)
                                            ? Text(S
                                                .of(context)
                                                .download
                                                .toUpperCase())
                                            : Text(

                                            S
                                                .of(context)
                                                .addToCart
                                                .toUpperCase(),
                                        style: TextStyle(

                                          fontFamily: GoogleFonts.cairo().fontFamily,
                                        ),),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.grey,
                  ),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10.0),
          const Divider(color: kGrey200, height: 1),
          const SizedBox(height: 10.0),
        ]);
      },
    );
  }
}
