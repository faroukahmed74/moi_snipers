import 'package:flutter/material.dart';
import '../models.dart';
import 'dart:math' as math;
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

import '../l10n/app_localizations.dart';
import '../storage.dart';
import '../weather_service.dart';
import 'package:flutter/services.dart';
import '../update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver, TickerProviderStateMixin {
  late FocusNode _focusNode;
  late TextEditingController _windAngleController;
  List<SniperType> snipers = [];
  SniperType? selectedSniper;
  bool isLoading = true;
  String distanceUnit = 'meters';
  String windUnit = 'm/s';
  double distance = 100.0;
  double windSpeed = 0.0;
  String windSpeedUnit = 'mph';
  double windAngle = 90.0;
  String windDirection = 'E'; // E, W, N, S, NE, NW, SE, SW
  String result = '';
  String details = '';
  
  // Weather data
  Map<String, dynamic>? weatherData;
  bool isLoadingWeather = false;
  
  // Compass data
  double compassHeading = 0.0;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;

  String? latestVersion;
  String? appVersion;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _windAngleController = TextEditingController(text: windAngle.toStringAsFixed(0));
    _loadSnipersAndSettings();
    _loadWeatherData();
    _checkForUpdate();
    _loadAppVersion();
    _startCompass();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
    _windAngleController.dispose();
    _magnetometerSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForUpdate();
      _loadSnipersAndSettings(); // Refresh settings when app resumes
    }
  }



  Future<void> _loadSnipersAndSettings() async {
    final loadedSnipers = await Storage.loadSniperTypes();
    final settings = await Storage.loadSettings();
    
    // Debug: Print loaded snipers info
    print('=== SNIPER LOADING DEBUG ===');
    print('Loaded ${loadedSnipers.length} snipers:');
    for (var sniper in loadedSnipers) {
      print('  - ${sniper.name}:');
      print('    Windage Constants: ${sniper.windageConstants}');
      print('    Range Correction Clicks: ${sniper.rangeCorrectionClicks.length} entries');
      print('    MOA Factor: ${sniper.moaToClickFactor}');
    }
    
    // Check if settings have changed
    bool settingsChanged = false;
    if (distanceUnit != (settings['distanceUnit'] ?? 'meters') ||
        windSpeedUnit != (settings['windSpeedUnit'] ?? 'mph')) {
      settingsChanged = true;
    }
    
    setState(() {
      snipers = loadedSnipers;
      selectedSniper = null; // No default selection
      distanceUnit = settings['distanceUnit'] ?? 'meters';
      windSpeedUnit = settings['windSpeedUnit'] ?? 'mph';
      isLoading = false;
    });
    
    // Show feedback if settings changed
    if (settingsChanged && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settings updated: Distance: $distanceUnit, Wind: $windSpeedUnit'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    
    print('=== END SNIPER LOADING DEBUG ===');
  }

  Future<void> _loadWeatherData() async {
    print('=== HOME SCREEN WEATHER DEBUG ===');
    print('Starting to load weather data...');
    
    setState(() {
      isLoadingWeather = true;
    });
    
    final weather = await WeatherService.getCurrentWeather();
    print('Weather service returned: $weather');
    
    setState(() {
      weatherData = weather;
      isLoadingWeather = false;
    });
    
    print('Weather data set in state: $weatherData');
    print('=== END HOME SCREEN WEATHER DEBUG ===');
  }

  Future<void> _checkForUpdate() async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      await UpdateService.checkForUpdate(context);
      final v = await UpdateService.getLatestVersion();
      setState(() {
        latestVersion = v;
      });
    }
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      appVersion = 'V ${info.version}';
    });
  }

  void _startCompass() {
    double smoothedHeading = 0.0;
    
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      // Calculate heading from magnetometer data
      double heading = math.atan2(event.y, event.x) * (180 / math.pi);
      heading = (heading + 360) % 360; // Normalize to 0-360 degrees
      
      // Smooth the heading for more responsive movement
      double alpha = 0.1; // Smoothing factor (0.1 = very smooth, 0.5 = more responsive)
      smoothedHeading = alpha * heading + (1 - alpha) * smoothedHeading;
      
      // Handle the 0/360 degree boundary smoothly
      double diff = smoothedHeading - compassHeading;
      if (diff > 180) {
        diff -= 360;
      } else if (diff < -180) {
        diff += 360;
      }
      
      setState(() {
        compassHeading = compassHeading + diff;
        if (compassHeading < 0) compassHeading += 360;
        if (compassHeading >= 360) compassHeading -= 360;
      });
    });
  }

  // Convert wind direction to angle
  double _getWindAngleFromDirection(String direction) {
    switch (direction) {
      case 'N': return 0.0;
      case 'NE': return 45.0;
      case 'E': return 90.0;
      case 'SE': return 135.0;
      case 'S': return 180.0;
      case 'SW': return 225.0;
      case 'W': return 270.0;
      case 'NW': return 315.0;
      default: return 90.0;
    }
  }

  // Get wind direction instruction (Left/Right)
  String _getWindDirectionInstruction(String direction) {
    switch (direction) {
      case 'N': return 'No windage adjustment';
      case 'NE': return 'Right';
      case 'E': return 'Right';
      case 'SE': return 'Right';
      case 'S': return 'No windage adjustment';
      case 'SW': return 'Left';
      case 'W': return 'Left';
      case 'NW': return 'Left';
      default: return 'Right';
    }
  }

  void calculateClicks() {
    if (selectedSniper == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a sniper type first.')),
      );
      return;
    }
    
    // Debug: Print selected sniper info
    print('=== CALCULATION DEBUG ===');
    print('Selected Sniper: ${selectedSniper!.name}');
    print('Windage Constants: ${selectedSniper!.windageConstants}');
    print('Range Correction Clicks: ${selectedSniper!.rangeCorrectionClicks}');
    print('MOA to Clicks Factor: ${selectedSniper!.moaToClickFactor}');
    print('Distance: $distance $distanceUnit');
    print('Wind Speed: $windSpeed $windSpeedUnit');
    print('Wind Direction: $windDirection');
    
    // Use the wind angle from slider/text field (don't override it)
    print('Wind Angle (from slider): $windAngle');
    
    if (distance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid distance.')),
      );
      return;
    }
    if (windSpeed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid wind speed.')),
      );
      return;
    }
    if (windAngle < 0 || windAngle > 180) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a wind angle between 0 and 180.')),
      );
      return;
    }
    
    // Convert wind speed to mph if needed for calculations
    double windSpeedMph = windSpeed;
    if (windSpeedUnit == 'km/h') {
      windSpeedMph = windSpeed / 1.60934;
    }
    
    print('Wind Speed (mph): $windSpeedMph');
    
    final output = BallisticsCalculator.calculateMOAAndClicksMilitary(
      sniper: selectedSniper!,
      distance: distance,
      windSpeed: windSpeedMph,
      windAngle: windAngle,
      distanceUnit: distanceUnit,
    );
    
    print('Ballistics Output: $output');
    
    // Calculate range correction clicks
    double distanceMeters = distanceUnit == 'meters' ? distance : distance * 0.9144;
    int rangeCorrectionClicks = selectedSniper!.getRangeCorrectionClicks(distanceMeters);
    
    print('Distance (meters): $distanceMeters');
    print('Range Correction Clicks: $rangeCorrectionClicks');
    
    setState(() {
      String resultText = '';
      String directionInstruction = _getWindDirectionInstruction(windDirection);
      
      // 1. Clicks Up (range correction clicks) - FIRST (always show)
      resultText += 'Clicks Up: $rangeCorrectionClicks\n';
      
      // 2. Clicks (windage clicks) - SECOND
      resultText += '${AppLocalizations.of(context)!.clicks}: ${output['clicks']!.toStringAsFixed(1)}\n';
      
      // 3. MOA (windage MOA) - THIRD
      resultText += 'MOA: ${output['moa']!.toStringAsFixed(1)}';
      
      result = resultText;
      
      // Get the actual constant used from the calculation
      double constantUsed = 13.0; // Default fallback
      
      // Find the appropriate windage constant for this distance
      if (selectedSniper!.windageConstants.isNotEmpty) {
        List<int> distances = selectedSniper!.windageConstants.keys.toList()..sort();
        for (int dist in distances) {
          if (distanceMeters <= dist) {
            constantUsed = selectedSniper!.windageConstants[dist]!;
            break;
          }
        }
        if (distanceMeters > distances.last) {
          constantUsed = selectedSniper!.windageConstants[distances.last]!;
        }
      }
      
      print('Constant Used: $constantUsed');
      
      String formulaString;
      if (windAngle == 90) {
        formulaString = 'MOA = (Wind Speed (mph) × 0.01 × Range (yards)) / CONSTANT';
      } else {
        formulaString = 'MOA = ((Wind Speed (mph) × 0.01 × Range (yards)) / CONSTANT) × (Angle / 90)';
      }
      
      details =
        'Sniper: ${selectedSniper!.name}\n'
        'Distance: $distance $distanceUnit (${distanceMeters.toStringAsFixed(0)}m)\n'
        'Wind: $windSpeed $windSpeedUnit\n'
        'Wind Direction: $windDirection (${windAngle.toStringAsFixed(0)}°)\n'
        'Direction Instruction: $directionInstruction\n'
        'Constant Used: $constantUsed (from sniper data)\n'
        'MOA→Clicks Factor: ${selectedSniper!.moaToClickFactor}\n'
        'Muzzle Velocity: ${selectedSniper!.muzzleVelocity} m/s\n'
        'Ballistic Coefficient: ${selectedSniper!.ballisticCoefficient}\n'
        'Range Correction Available: ${selectedSniper!.rangeCorrectionClicks.isNotEmpty ? "Yes" : "No"}\n'
        'Military Formula:\n'
        '$formulaString\n'
        'Clicks = MOA × MOA→Clicks Factor\n'
        'MOA: ${output['moa']!.toStringAsFixed(1)}\nClicks: ${output['clicks']!.toStringAsFixed(1)}';
      
      print('=== END CALCULATION DEBUG ===');
    });
  }

  Widget _buildAnimatedCompass() {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: Colors.black,
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: Colors.black,
                width: 2,
              ),
            ),
          ),
          
          // Rotating compass face
          Transform.rotate(
            angle: -compassHeading * (math.pi / 180),
            child: Container(
              width: 160,
              height: 160,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Compass background
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: Colors.black,
                        width: 1,
                      ),
                    ),
                  ),
                  
                  // North arrow (black) - enhanced
                  Positioned(
                    top: 2,
                    child: Column(
                      children: [
                        // Arrow tip
                        Container(
                          width: 0,
                          height: 0,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Colors.transparent, width: 8),
                              right: BorderSide(color: Colors.transparent, width: 8),
                              bottom: BorderSide(color: Colors.black, width: 12),
                            ),
                          ),
                        ),
                        // Arrow shaft
                        Container(
                          width: 6,
                          height: 35,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // South arrow (grey) - enhanced
                  Positioned(
                    bottom: 2,
                    child: Column(
                      children: [
                        // Arrow shaft
                        Container(
                          width: 6,
                          height: 35,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade600,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        // Arrow tip
                        Container(
                          width: 0,
                          height: 0,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: Colors.transparent, width: 8),
                              right: BorderSide(color: Colors.transparent, width: 8),
                              top: BorderSide(color: Colors.grey.shade600, width: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Simple direction letters
                  ..._buildSimpleCompassLetters(),
                  
                  // Simple degree markers
                  ..._buildSimpleDegreeMarkers(),
                ],
              ),
            ),
          ),
          
          // Center point
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black,
              border: Border.all(
                color: Colors.white,
                width: 2,
              ),
            ),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          
          // Heading display
          Positioned(
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                '${compassHeading.toStringAsFixed(0)}°',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSimpleCompassLetters() {
    List<Widget> letters = [];
    List<String> directions = ['N', 'E', 'S', 'W'];
    
    for (int i = 0; i < directions.length; i++) {
      double angle = (i * 90) * (math.pi / 180);
      double radius = 50;
      double x = radius * math.sin(angle);
      double y = -radius * math.cos(angle);
      
      letters.add(
        Positioned(
          left: 80 + x - 8,
          top: 80 + y - 8,
          child: Text(
            directions[i],
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
      );
    }
    
    return letters;
  }

  List<Widget> _buildSimpleDegreeMarkers() {
    List<Widget> markers = [];
    
    for (int i = 0; i < 72; i++) {
      double angle = (i * 5) * (math.pi / 180);
      double radius = 62;
      double x = radius * math.sin(angle);
      double y = -radius * math.cos(angle);
      
      bool isMainMarker = i % 18 == 0; // Every 90 degrees (18 * 5 = 90)
      bool isSubMarker = i % 6 == 0; // Every 30 degrees (6 * 5 = 30)
      
      double markerWidth = isMainMarker ? 4 : (isSubMarker ? 3 : 2);
      double markerHeight = isMainMarker ? 20 : (isSubMarker ? 12 : 6);
      
      markers.add(
        Positioned(
          left: 80 + x - (markerWidth / 2),
          top: 80 + y - (markerHeight / 2),
          child: Container(
            width: markerWidth,
            height: markerHeight,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(markerWidth / 2),
            ),
          ),
        ),
      );
    }
    
    return markers;
  }


  void showDetailsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.calculationDetails),
        content: Text(details),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.close),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Eagles')),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Eagles'),
            if (appVersion != null) ...[
              const SizedBox(width: 8),
              Text(appVersion!, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey)),
            ],
          ],
        ),
        actions: [
          if (Theme.of(context).platform == TargetPlatform.android)
            IconButton(
              icon: const Icon(Icons.system_update_alt),
              tooltip: 'Check for Update',
              onPressed: () async {
                await UpdateService.checkForUpdate(context);
              },
            ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            DrawerHeader(child: Text(AppLocalizations.of(context)!.menu)),
            ListTile(
              title: Text(AppLocalizations.of(context)!.sniperManagement),
              onTap: () async {
                await Navigator.pushNamed(context, '/snipers');
                // Refresh snipers when returning from sniper management screen
                _loadSnipersAndSettings();
              },
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.settings),
              onTap: () async {
                await Navigator.pushNamed(context, '/settings');
                // Refresh settings when returning from settings screen
                _loadSnipersAndSettings();
              },
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.references),
              onTap: () async {
                await Navigator.pushNamed(context, '/references');
                // Refresh settings when returning from references screen
                _loadSnipersAndSettings();
              },
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside
          FocusScope.of(context).unfocus();
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 2,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context)!.selectSniperType, style: Theme.of(context).textTheme.titleMedium),
                      DropdownButton<SniperType?>(
                        value: selectedSniper,
                        isExpanded: true,
                        hint: Text('Please select a sniper type', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey)),
                        items: [
                          DropdownMenuItem<SniperType?>(
                            value: null,
                            child: Text('Please select a sniper type', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey)),
                          ),
                          ...snipers.map((sniper) {
                            return DropdownMenuItem<SniperType?>(
                              value: sniper,
                              child: Text(sniper.name, style: Theme.of(context).textTheme.bodyLarge),
                            );
                          }).toList(),
                        ],
                        onChanged: (value) {
                          setState(() {
                            selectedSniper = value;
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      if (selectedSniper != null)
                        Text(
                          '${AppLocalizations.of(context)!.bulletWeight}: ${selectedSniper!.bulletWeight}g, '
                          '${AppLocalizations.of(context)!.muzzleVelocity}: ${selectedSniper!.muzzleVelocity}m/s, '
                          'BC: ${selectedSniper!.ballisticCoefficient}, '
                          'MOA→Clicks: ${selectedSniper!.moaToClickFactor}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Weather Widget - Recreated
              Card(
                elevation: 2,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.wb_sunny, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(AppLocalizations.of(context)!.liveWeatherData, style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _loadWeatherData,
                            tooltip: AppLocalizations.of(context)!.currentWeather,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (isLoadingWeather)
                        Center(
                          child: Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 8),
                              Text(AppLocalizations.of(context)!.loadingWeatherData),
                            ],
                          ),
                        )
                      else if (weatherData != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Location and temperature
                            Row(
                              children: [
                                Icon(Icons.location_on, size: 16, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    weatherData!['location'] ?? AppLocalizations.of(context)!.unknownLocation,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.thermostat, size: 16, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '${weatherData!['temperature']?.toStringAsFixed(1) ?? 'N/A'}°C',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  weatherData!['description'] ?? AppLocalizations.of(context)!.unknownConditions,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Wind information
                            Row(
                              children: [
                                Icon(Icons.air, size: 16, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${AppLocalizations.of(context)!.wind}: ${WeatherService.msToMph(weatherData!['windSpeed'] ?? 0).toStringAsFixed(1)} mph',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                      Text(
                                        '${AppLocalizations.of(context)!.windGust}: ${weatherData!['windGust'] != null ? WeatherService.msToMph(weatherData!['windGust']).toStringAsFixed(1) + ' mph' : 'N/A'}',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.orange),
                                      ),
                                      if (weatherData!['windGust'] != null)
                                        Text(
                                          'Wind Gust: ${WeatherService.msToKmh(weatherData!['windGust']).toStringAsFixed(1)} km/h',
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.orange),
                                        ),
                                      Text(
                                        '${AppLocalizations.of(context)!.direction}: ${WeatherService.getWindDirection(weatherData!['windDirection'] ?? 0)} (${weatherData!['windDirection']?.toStringAsFixed(0) ?? 'N/A'}°)',
                                        style: Theme.of(context).textTheme.bodyMedium,
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    if (weatherData!['windSpeed'] != null) {
                                      final windSpeedMph = WeatherService.msToMph(weatherData!['windSpeed']);
                                      setState(() {
                                        windSpeed = windSpeedMph;
                                        windSpeedUnit = 'mph';
                                      });
                                      await Clipboard.setData(ClipboardData(text: '${windSpeedMph.toStringAsFixed(1)}'));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('${AppLocalizations.of(context)!.wind} ${windSpeedMph.toStringAsFixed(1)} mph\n${AppLocalizations.of(context)!.wind} copied to clipboard'),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.speed, size: 16),
                                  label: Text(AppLocalizations.of(context)!.useWind),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // API Source indicator
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.api,
                                    size: 14,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Data from: ${weatherData!['apiSource'] ?? 'Unknown'}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.orange, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context)!.weatherDataNotAvailable,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.orange),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)!.tapRefreshToTryAgain,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Wind Direction Compass
              Card(
                elevation: 2,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.explore, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Wind Direction', style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Animated Compass
                      Container(
                        width: double.infinity,
                        height: 200,
                        child: _buildAnimatedCompass(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Compass Heading: ${compassHeading.toStringAsFixed(0)}°',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 2,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                labelText: AppLocalizations.of(context)!.distance,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: Theme.of(context).textTheme.bodyLarge,
                              onChanged: (val) {
                                setState(() {
                                  distance = double.tryParse(val) ?? 0.0;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: distanceUnit,
                            items: [AppLocalizations.of(context)!.meters, AppLocalizations.of(context)!.yards].map((unit) {
                              return DropdownMenuItem(
                                value: unit == AppLocalizations.of(context)!.meters ? 'meters' : 'yards',
                                child: Text(unit, style: Theme.of(context).textTheme.bodyLarge),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  distanceUnit = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                labelText: AppLocalizations.of(context)!.windSpeed,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: Theme.of(context).textTheme.bodyLarge,
                              onChanged: (val) {
                                setState(() {
                                  windSpeed = double.tryParse(val) ?? 0.0;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: windSpeedUnit,
                            items: ['mph', 'km/h'].map((unit) {
                              return DropdownMenuItem(
                                value: unit,
                                child: Text(unit, style: Theme.of(context).textTheme.bodyLarge),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  windSpeedUnit = val;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Display current wind speed values
                      if (windSpeed > 0)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Current Wind: ${windSpeed.toStringAsFixed(1)} $windSpeedUnit',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Wind Angle (${windAngle.toStringAsFixed(0)}°)', style: Theme.of(context).textTheme.bodyLarge),
                                Slider(
                                  value: windAngle,
                                  min: 0,
                                  max: 180,
                                  divisions: 180,
                                  label: windAngle.toStringAsFixed(0),
                                  onChanged: (val) {
                                    setState(() {
                                      windAngle = val;
                                      _windAngleController.text = windAngle.toStringAsFixed(0);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 80,
                            child: TextField(
                              decoration: InputDecoration(
                                labelText: 'Angle',
                                hintText: '0-180',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                              ),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyLarge,
                              controller: _windAngleController,
                              onChanged: (val) {
                                final angle = double.tryParse(val);
                                if (angle != null && angle >= 0 && angle <= 180) {
                                  setState(() {
                                    windAngle = angle;
                                  });
                                }
                              },
                              onSubmitted: (val) {
                                final angle = double.tryParse(val);
                                if (angle != null && angle >= 0 && angle <= 180) {
                                  setState(() {
                                    windAngle = angle;
                                    _windAngleController.text = windAngle.toStringAsFixed(0);
                                  });
                                } else {
                                  // Reset to current value if invalid
                                  _windAngleController.text = windAngle.toStringAsFixed(0);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: selectedSniper != null ? calculateClicks : null,
                icon: const Icon(Icons.calculate),
                label: Text(AppLocalizations.of(context)!.calculate),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(MediaQuery.of(context).size.width * 0.7, 48),
                  backgroundColor: selectedSniper != null 
                      ? Theme.of(context).colorScheme.primary 
                      : Theme.of(context).colorScheme.surface,
                  foregroundColor: selectedSniper != null 
                      ? Theme.of(context).colorScheme.onPrimary 
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: result.isNotEmpty
                    ? Card(
                        key: ValueKey(result),
                        color: Theme.of(context).colorScheme.primaryContainer,
                        elevation: 4,
                        child: InkWell(
                          onTap: showDetailsDialog,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: MediaQuery.of(context).size.height * 0.03,
                              horizontal: MediaQuery.of(context).size.width * 0.05,
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.stacked_line_chart, size: 40, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(height: 8),
                                Text(
                                  result,
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppLocalizations.of(context)!.calculationDetails,
                                  style: TextStyle(color: Theme.of(context).colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 