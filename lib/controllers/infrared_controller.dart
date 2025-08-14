import 'package:flutter/material.dart';

class InfraredController extends ChangeNotifier {
  bool _enabled = false;

  bool get enabled => _enabled;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }
}


