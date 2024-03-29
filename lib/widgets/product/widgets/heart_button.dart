import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/index.dart' show Product, ProductWishListModel;

class HeartButton extends StatelessWidget {
  final Product product;
  final double? size;
  final Color? color;

  const HeartButton({Key? key, required this.product, this.size, this.color})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: Provider.of<ProductWishListModel>(context, listen: false),
      child: Consumer<ProductWishListModel>(
        builder: (BuildContext context, ProductWishListModel model, _) {
          final isExist =
              model.products.indexWhere((item) => item.id == product.id) != -1;
          if (!isExist) {
            return IconButton(
              onPressed: () {
                Provider.of<ProductWishListModel>(context, listen: false)
                    .addToWishlist(product);
              },
              icon: CircleAvatar(
                backgroundColor:
                    Theme.of(context).primaryColorLight.withOpacity(0.7),
                child: Icon(
                  CupertinoIcons.heart,
                  color: Theme.of(context).primaryColor,
                  size: size ?? 16.0,
                ),
              ),
            );
          }

          return IconButton(
            onPressed: () {
              Provider.of<ProductWishListModel>(context, listen: false)
                  .removeToWishlist(product);
            },
            icon: CircleAvatar(
              backgroundColor:
                  Theme.of(context).primaryColorLight.withOpacity(0.7),
              child: Icon(CupertinoIcons.heart_fill,
                  color: Theme.of(context).primaryColor),
            ),
          );
        },
      ),
    );
  }
}
