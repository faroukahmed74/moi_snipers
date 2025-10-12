import 'dart:convert';
import 'package:http/http.dart' as http;

class DeclinationService {
  // Simple in-memory cache keyed by rounded lat/lon
  static final Map<String, _DeclinationCacheEntry> _cache = {};

  static Future<double?> getDeclination({
    required double latitude,
    required double longitude,
    double? elevationMeters,
    DateTime? date,
  }) async {
    final key = _cacheKey(latitude, longitude);
    final now = DateTime.now();
    final cached = _cache[key];
    if (cached != null && now.difference(cached.timestamp) < const Duration(hours: 12)) {
      return cached.declinationDeg;
    }

    try {
      final d = date ?? DateTime.now();
      final dateStr = "${d.year}-${_two(d.month)}-${_two(d.day)}";
      final elev = (elevationMeters ?? 0).toStringAsFixed(0);
      // NOAA Geomag Web Calculator (WMM)
      final uri = Uri.parse(
        'https://www.ngdc.noaa.gov/geomag-web/calculators/calculateDeclination?lat1=$latitude&lon1=$longitude&startYear=${d.year}&startMonth=${d.month}&startDay=${d.day}&elevation=$elev&resultFormat=json',
      );

      final resp = await http.get(uri, headers: {
        'User-Agent': 'MOI_Snipers_App/1.0',
        'Accept': 'application/json',
      });

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        // Try multiple common shapes
        double? decl;
        if (data is Map && data['result'] is List && data['result'].isNotEmpty) {
          final r = data['result'][0];
          decl = _parseDeclinationField(r);
        } else if (data is Map) {
          decl = _parseDeclinationField(data);
        }

        if (decl != null) {
          _cache[key] = _DeclinationCacheEntry(declinationDeg: decl, timestamp: now);
          return decl;
        }
      }
    } catch (_) {
      // Ignore and fall through to null
    }
    return null; // Caller should fall back to approximate value
  }

  static String _cacheKey(double lat, double lon) =>
      '${lat.toStringAsFixed(2)},${lon.toStringAsFixed(2)}';

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  static double? _parseDeclinationField(Map m) {
    // Try common keys
    final candidates = ['declination', 'declinationAngle', 'declination_deg'];
    for (final k in candidates) {
      final v = m[k];
      if (v == null) continue;
      if (v is num) return v.toDouble();
      if (v is String) {
        // May be like "3.5" or "3.5 E" / "-2.1 W"
        final numMatch = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(v);
        if (numMatch != null) {
          final n = double.tryParse(numMatch.group(0)!);
          if (n != null) {
            // Direction letter overrides sign if present
            if (v.toUpperCase().contains('E')) return n.abs();
            if (v.toUpperCase().contains('W')) return -n.abs();
            return n;
          }
        }
      }
    }
    return null;
  }
}

class _DeclinationCacheEntry {
  final double declinationDeg;
  final DateTime timestamp;
  _DeclinationCacheEntry({required this.declinationDeg, required this.timestamp});
}