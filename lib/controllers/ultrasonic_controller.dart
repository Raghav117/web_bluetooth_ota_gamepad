import 'package:flutter/material.dart';

class UltrasonicController extends ChangeNotifier {
  bool _enabled = false;
  int _range = 40; // default range

  bool get enabled => _enabled;
  int get range => _range;

  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
  }

  void setRange(int value) {
    final int clamped = value.clamp(10, 100);
    if (_range == clamped) return;
    _range = clamped;
    notifyListeners();
  }
}


