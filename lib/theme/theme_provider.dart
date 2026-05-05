import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ambient_theme.dart';
import 'mike_special_theme.dart';
import 'theatrical_theme.dart';

enum PulseStyle {
  mikeSpecial,
  theatrical,
  ambient;

  String get displayName => switch (this) {
        PulseStyle.mikeSpecial => 'Mike Special',
        PulseStyle.theatrical  => 'Theatrical',
        PulseStyle.ambient     => 'Ambient',
      };

  String get subtitle => switch (this) {
        PulseStyle.mikeSpecial => 'Carbon + ember — high density',
        PulseStyle.theatrical  => 'Velvet + gold — dramatic',
        PulseStyle.ambient     => 'Midnight blues — calm',
      };
}

class ThemeProvider extends ChangeNotifier {
  static const _kStyleKey = 'pulse_style';

  PulseStyle _style = PulseStyle.mikeSpecial;

  PulseStyle get style => _style;

  ThemeData get themeData => switch (_style) {
        PulseStyle.mikeSpecial => mikeSpecialTheme,
        PulseStyle.theatrical  => theatricalTheme,
        PulseStyle.ambient     => ambientTheme,
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kStyleKey);
    if (saved != null) {
      _style = PulseStyle.values.firstWhere(
        (s) => s.name == saved,
        orElse: () => PulseStyle.mikeSpecial,
      );
    }
    notifyListeners();
  }

  Future<void> setStyle(PulseStyle style) async {
    if (_style == style) return;
    _style = style;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStyleKey, style.name);
  }
}
