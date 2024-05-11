import '../../models/entities/user.dart';
import '../../services/index.dart';

class ScannerModel {
  final _services = Services();
  final User? _user;

  ScannerModel(this._user);

  Future<dynamic> getDataFromScanner(
    String data,
  ) async {
    var result;
    try {
      print("dassdasdsa$data");
      result =
          await _services.api.fetchProductsByCategory(categoryId: -1,page: 1,search: data);

      print("dfdsfdsfdsf$result");
      ////
      // result =
      //     await _services.api.getDataFromScanner(data, cookie: _user?.cookie);
    } catch (e) {
      return e;
    }
    return   result.length>0?      result.first:null;
  }
}

