import 'package:flutter/foundation.dart';

class ScreenModel with ChangeNotifier {
  final Map<String, String> _formData = {};

  String getValue(String key) => _formData[key] ?? '';

  void updateValue(String key, String value) {
    _formData[key] = value;
    notifyListeners();
  }
}
