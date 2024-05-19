import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/svg.dart';
import 'package:provider/provider.dart';

import '../../../../common/constants.dart';
import '../../../../generated/l10n.dart';
import '../../../../models/search_model.dart';
import 'recent_products_custom.dart';

class RecentSearchesCustom extends StatelessWidget {
  final Function? onTap;

  const RecentSearchesCustom({this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final widthContent = (screenSize.width / 2) - 4;

    return Consumer<SearchModel>(
      builder: (context, model, child) {
        return (model.keywords.isEmpty)
            ? renderEmpty(context)
            : renderKeywords(model, widthContent, context);
      },
    );
  }

  Widget renderEmpty(context) {
    return SizedBox(
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
                    'assets/images/searchproducts.svg'),),

              Column(
                children: <Widget>[

                  const SizedBox(height: 320),
                  Center(child:  Text(              S.of(context).emptySearch,
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


      SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Stack(
        fit: StackFit.loose,
        // mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[


          Positioned(
            top: 1,
            bottom: 1,
            left: 1,
            right: 1,

            child:  SvgPicture.asset(
//////
                color: Theme.of(context).colorScheme.primary,
                width: 100,
                height: 100,
                'assets/images/searchproducts.svg'),),


          // Image.asset(
          //   kEmptySearch,
          //   width: 120,
          //   height: 120,
          // ),
          // const SizedBox(height: 10),
          SizedBox(
            width: 250,
            child: Text(
              S.of(context).emptySearch,
              style: const TextStyle(color: kGrey400),
              textAlign: TextAlign.center,
            ),
          )
        ],
      ) ,
    )


     ;
  }

  Widget renderKeywords(
      SearchModel model, double widthContent, BuildContext context) {
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        Container(
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                S.of(context).history,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (model.keywords.isNotEmpty)
                InkWell(
                  onTap: model.clearKeywords,
                  child: Text(
                    S.of(context).clear,
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 13,
                    ),
                  ),
                )
            ],
          ),
        ),
        Card(
          elevation: 0,
          color: Theme.of(context).primaryColorLight,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: model.keywords
                .take(5)
                .map((e) => ListTile(
                      title: Text(e),
                      onTap: () {
                        onTap?.call(e);
                      },
                    ))
                .toList(),
          ),
        ),
        RecentProductsCustom(),
      ],
    );
  }
}
