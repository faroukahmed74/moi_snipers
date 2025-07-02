import 'dart:math';

class SniperType {
  final String name;
  final double bulletWeight; // in grams
  final double muzzleVelocity; // in m/s
  final double ballisticCoefficient;
  final Map<int, double> windageConstants;
  final double moaToClickFactor;
  final Map<String, int> rangeCorrectionClicks; // Range-based correction clicks

  SniperType({
    required this.name,
    required this.bulletWeight,
    required this.muzzleVelocity,
    required this.ballisticCoefficient,
    required this.windageConstants,
    required this.moaToClickFactor,
    required this.rangeCorrectionClicks,
  });

  static List<SniperType> defaultSnipers() => [
    SniperType(
      name: 'Parker Hale',
      bulletWeight: 9.3,
      muzzleVelocity: 850,
      ballisticCoefficient: 0.5,
      windageConstants: {500: 13, 600: 12, 700: 11, 800: 11, 900: 10},
      moaToClickFactor: 4.0,
      rangeCorrectionClicks: {
        '199': 0,
        '299': 6,
        '399': 18,
        '499': 31,
        '599': 47,
        '699': 67,
        '799': 89,
        '899': 116,
        '999': 148,
        '1000': 184,
      },
    ),
    SniperType(
      name: 'SV-98',
      bulletWeight: 9.6,
      muzzleVelocity: 820,
      ballisticCoefficient: 0.48,
      windageConstants: {500: 13, 600: 12, 700: 11, 800: 11, 900: 10},
      moaToClickFactor: 2.857142857,
      rangeCorrectionClicks: {},
    ),
    SniperType(
      name: 'Dragunov',
      bulletWeight: 9.6,
      muzzleVelocity: 830,
      ballisticCoefficient: 0.45,
      windageConstants: {500: 13, 600: 12, 700: 11, 800: 11, 900: 10},
      moaToClickFactor: 0.5714285714,
      rangeCorrectionClicks: {},
    ),
    SniperType(
      name: 'Heckler & Koch',
      bulletWeight: 10.9,
      muzzleVelocity: 900,
      ballisticCoefficient: 0.52,
      windageConstants: {500: 13, 600: 12, 700: 11, 800: 11, 900: 10},
      moaToClickFactor: 2.857142857,
      rangeCorrectionClicks: {},
    ),
    SniperType(
      name: 'OCB96',
      bulletWeight: 8.6,
      muzzleVelocity: 870,
      ballisticCoefficient: 0.47,
      windageConstants: {500: 12, 600: 12, 700: 12, 800: 12, 900: 12},
      moaToClickFactor: 2.857142857,
      rangeCorrectionClicks: {
        '124': 0,
        '149': 1,
        '174': 2,
        '199': 4,
        '224': 6,
        '249': 7,
        '274': 7,
        '299': 8,
        '324': 9,
        '349': 11,
        '374': 12,
        '399': 14,
        '424': 16,
        '449': 18,
        '474': 20,
        '499': 23,
        '524': 25,
        '549': 28,
        '574': 30,
        '599': 33,
        '624': 36,
        '649': 38,
        '674': 40,
        '699': 43,
        '724': 46,
        '749': 49,
        '774': 52,
        '799': 55,
        '824': 58,
        '849': 62,
        '874': 65,
        '899': 68,
        '924': 71,
        '949': 75,
        '974': 79,
        '999': 83,
        '1024': 86,
        '1049': 91,
        '1074': 94,
        '1099': 100,
        '1124': 103,
        '1149': 108,
        '1174': 112,
        '1199': 117,
        '1224': 122,
        '1249': 127,
        '1274': 132,
        '1299': 137,
        '1324': 142,
        '1349': 148,
        '1374': 154,
        '1399': 160,
        '1424': 166,
        '1449': 172,
        '1474': 178,
        '1499': 185,
        '1524': 192,
        '1549': 199,
        '1574': 206,
        '1599': 213,
        '1624': 221,
        '1649': 229,
        '1674': 236,
        '1699': 244,
        '1724': 252,
        '1749': 260,
        '1774': 269,
        '1799': 278,
        '1824': 287,
        '1849': 296,
        '1874': 305,
        '1899': 314,
        '1924': 324,
        '1949': 334,
        '1974': 344,
        '1999': 354,
        '2000': 364,
      },
    ),
  ];

  Map<String, dynamic> toMap() => {
    'name': name,
    'bulletWeight': bulletWeight,
    'muzzleVelocity': muzzleVelocity,
    'ballisticCoefficient': ballisticCoefficient,
    'windageConstants': windageConstants.map((k, v) => MapEntry(k.toString(), v)),
    'moaToClickFactor': moaToClickFactor,
    'rangeCorrectionClicks': rangeCorrectionClicks,
  };

  factory SniperType.fromMap(Map<String, dynamic> map) => SniperType(
    name: map['name'],
    bulletWeight: map['bulletWeight'],
    muzzleVelocity: map['muzzleVelocity'],
    ballisticCoefficient: map['ballisticCoefficient'],
    windageConstants: (map['windageConstants'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(int.parse(k), v.toDouble())) ?? {500: 13, 600: 12, 700: 11, 800: 11, 900: 10},
    moaToClickFactor: (map['moaToClickFactor'] ?? 4.0).toDouble(),
    rangeCorrectionClicks: (map['rangeCorrectionClicks'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v as int)) ?? {},
  );

  /// Returns the range correction clicks for a given distance in meters
  int getRangeCorrectionClicks(double distanceMeters) {
    if (rangeCorrectionClicks.isEmpty) return 0;
    
    // Find the appropriate range bracket
    for (String rangeStr in rangeCorrectionClicks.keys) {
      int range = int.parse(rangeStr);
      if (distanceMeters <= range) {
        return rangeCorrectionClicks[rangeStr]!;
      }
    }
    
    // If distance exceeds all ranges, return the highest correction
    return rangeCorrectionClicks.values.last;
  }
}

class BallisticsCalculator {
  /// Returns a map with 'moa' and 'clicks' for windage adjustment.
  /// Inputs: distance (meters/yards), wind speed (mph), wind angle (degrees)
  static Map<String, double> calculateMOAAndClicks({
    required double distance, // in meters or yards
    required double windSpeed, // in mph
    required double windAngle, // in degrees
    String distanceUnit = 'meters',
  }) {
    // Convert distance to yards if needed
    double distYards = distanceUnit == 'meters' ? distance * 1.09361 : distance;
    // Wind angle in radians
    double angleRad = windAngle * 3.141592653589793 / 180.0;
    // Standard formula for wind drift MOA (simplified):
    // MOA = (Wind Speed (mph) * Distance (yards) * sin(angle)) / 15
    double moa = (windSpeed * distYards * sin(angleRad)) / 15.0;
    double clicks = moa * 4.0;
    return {'moa': moa, 'clicks': clicks};
  }

  static Map<String, double> calculateMOAAndClicksMilitary({
    required SniperType sniper,
    required double distance, // in meters or yards
    required double windSpeed, // in mph
    required double windAngle, // in degrees
    String distanceUnit = 'meters',
  }) {
    // Convert distance to yards
    double distYards = distanceUnit == 'meters' ? distance * 1.09361 : distance;
    // Use wind angle in calculation
    double angleRad = 0.0;
    if (windAngle != null) {
      angleRad = windAngle * pi / 180.0;
    }
    // Muzzle velocity in fps
    double v0fps = sniper.muzzleVelocity * 3.28084; // m/s to ft/s
    
    // Select windage constant based on sniper type and distance
    double constant;
    if (sniper.name == 'OCB96') {
      // OCB96 always uses constant 12 regardless of distance
      constant = 12.0;
    } else {
      // All other sniper types use distance-based constants
      if (distance >= 1 && distance <= 599) {
        constant = 13.0;
      } else if (distance >= 600 && distance <= 699) {
        constant = 12.0;
      } else if (distance >= 700 && distance <= 799) {
        constant = 11.0;
      } else if (distance >= 800 && distance <= 899) {
        constant = 10.0;
      } else if (distance >= 900 && distance <= 999) {
        constant = 9.0;
      } else {
        constant = 13.0;
      }
    }
    
    // MOA base calculation
    double baseMoa = (windSpeed * 0.01 * distYards) / constant;
    double moa = baseMoa;
    if (windAngle != null && windAngle != 90) {
      moa = baseMoa * (windAngle / 90.0);
    }
    double clicks = moa * sniper.moaToClickFactor;
    return {'moa': moa, 'clicks': clicks};
  }
} 