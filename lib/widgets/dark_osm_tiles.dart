import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../config/api_config.dart';

/// Post-login default: natural light OpenStreetMap tiles — **no invert / dark filter**.
class LightOsmTileLayer extends StatelessWidget {
  const LightOsmTileLayer({super.key});

  static const background = Color(TileUrls.mapBackgroundArgb);
  static const accent = Color(TileUrls.aoiAccentArgb);

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: TileUrls.osm,
      userAgentPackageName: 'com.climateeye.climateeye',
      maxNativeZoom: 19,
      maxZoom: 19,
      // Default network tile provider; browser/OS caching applies.
      // Explicit 7-day policy cannot be forced without a custom cache store.
      tileProvider: NetworkTileProvider(),
    );
  }
}

/// Back-compat alias used by older call sites / tests.
@Deprecated('Use LightOsmTileLayer')
typedef DarkOsmTileLayer = LightOsmTileLayer;

/// Visible © OpenStreetMap attribution (light theme).
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black12),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            '© OpenStreetMap contributors',
            style: TextStyle(fontSize: 9.5, color: Color(0xFF475569)),
          ),
        ),
      ),
    );
  }
}
