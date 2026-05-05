// Design tokens extracted by Drew from HTML mockups v1/v2/v3.
import 'package:flutter/material.dart';

// ── V3 Mike Special (The Forge) ──────────────────────────────────────
class MikeSpecialColors {
  MikeSpecialColors._();
  static const background      = Color(0xFF050506);
  static const scaffold        = Color(0xFF0A0A0C); // forge-black
  static const carbon          = Color(0xFF141416);
  static const graphite        = Color(0xFF1A1A1E);
  static const graphiteLight   = Color(0xFF252528);
  static const graphiteLighter = Color(0xFF2E2E32);
  static const ember           = Color(0xFFFF6B35);
  static const emberDeep       = Color(0xFFD4522A);
  static const molten          = Color(0xFFFFB347);
  static const steel           = Color(0xFFE8E4E0);
  static const electric        = Color(0xFF4ECDC4);
  static const danger          = Color(0xFFFF4444);
  // opacity-baked variants
  static const emberGlow    = Color(0x1FFF6B35); // 12%
  static const emberHot     = Color(0x0FFF6B35); // 6%
  static const steelDim     = Color(0xA6E8E4E0); // 65%
  static const steelGhost   = Color(0x59E8E4E0); // 35%
}

class MikeSpecialRadius {
  MikeSpecialRadius._();
  static const lg = 16.0;
  static const md = 10.0;
  static const sm = 6.0;
}

// ── V1 Theatrical ────────────────────────────────────────────────────
class TheatricalColors {
  TheatricalColors._();
  static const background   = Color(0xFF0D0510); // velvet-deep
  static const velvet       = Color(0xFF1A0A1E);
  static const curtain      = Color(0xFF2D1233);
  static const footlight    = Color(0xFFE8A838);
  static const footlightDim = Color(0xFFC4862A);
  static const gold         = Color(0xFFD4A853);
  static const ivory        = Color(0xFFF5EDE0);
  static const rose         = Color(0xFF8B3A4A);
  static const danger       = Color(0xFF8B3A3A);
  static const success      = Color(0xFF4A8B5C);
  static const goldSoft     = Color(0x26D4A853); // 15%
  static const ivoryMuted   = Color(0xB2F5EDE0); // 70%
  static const ivoryGhost   = Color(0x66F5EDE0); // 40%
}

class TheatricalRadius {
  TheatricalRadius._();
  static const lg = 16.0;
  static const md = 10.0;
}

// ── V2 Ambient ───────────────────────────────────────────────────────
class AmbientColors {
  AmbientColors._();
  static const background = Color(0xFF060810);
  static const midnight   = Color(0xFF0B0E1A);
  static const deepSea    = Color(0xFF0F1628);
  static const twilight   = Color(0xFF1A1F3A);
  static const dusk       = Color(0xFF252B4A);
  static const dawnPink   = Color(0xFFE8A0B4);
  static const dawnPeach  = Color(0xFFF0C4A8);
  static const moon       = Color(0xFFC8D0E8);
  static const danger     = Color(0xFFD47070);
  static const success    = Color(0xFF6BAF7C);
  static const moonDim    = Color(0x99C8D0E8); // 60%
  static const moonGhost  = Color(0x59C8D0E8); // 35%
  static const dawnRose   = Color(0x1FE8A0B4); // 12%
}

class AmbientRadius {
  AmbientRadius._();
  static const lg = 20.0;
  static const md = 12.0;
}
