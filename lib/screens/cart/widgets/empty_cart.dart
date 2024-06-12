import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../common/constants.dart';
import '../../../common/tools/navigate_tools.dart';
import '../../../generated/l10n.dart';
import '../../../menu/maintab_delegate.dart';
import '../../../widgets/product/product_bottom_sheet.dart';

class EmptyCart extends StatelessWidget {
  const EmptyCart({this.isModal});
  final bool? isModal;

  void _openShopping(BuildContext context) {
    if (isModal == true) {
      try {
        ExpandingBottomSheet.of(context)!.close();
      } catch (e) {
        Navigator.of(context).pushNamed(RouteList.dashboard);
      }
    } else {
      final modalRoute = ModalRoute.of(context);
      if (modalRoute?.canPop ?? false) {
        Navigator.of(context).pop();
      }
      MainTabControlDelegate.getInstance().changeTab(RouteList.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SvgPicture.asset(
////
            color: Theme.of(context).colorScheme.primary,
            width: 400,
            height: 400,
            'assets/images/Cart.svg')
      ],);
  }
}
