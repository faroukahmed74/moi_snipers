import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../declination_service.dart';
import '../storage.dart';
import '../l10n/app_localizations.dart';
import '../weather_service.dart';
import '../compass_service.dart';

class CompassScreen extends StatefulWidget {
  const CompassScreen({super.key});

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> with WidgetsBindingObserver {
  // Compass data
  double compassHeading = 0.0;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  AccelerometerEvent? _lastAccel;
  double calibrationOffsetDeg = 0.0; // user-set offset
  StreamSubscription<double>? _headingSub;
  bool useTrueNorth = true;
  
  // Location data
  Position? currentPosition;
  String locationName = 'Loading...';
  double elevation = 0.0;
  bool isLoadingLocation = true;
  double? magneticDeclinationDeg; // dynamic declination per location

  // Weather data (for wind direction display)
  Map<String, dynamic>? weatherData;
  bool isLoadingWeather = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCalibrationOffset();
    _getCurrentLocation();
    _loadWeatherData();
    // Start shared CompassService using settings for True/Magnetic North
    _startCompassServiceFromSettings();
    _headingSub = CompassService.instance.headingStream.listen((h) {
      if (!mounted) return;
      setState(() { compassHeading = h; });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Ensure the shared compass service is running when returning to this screen
      _startCompassServiceFromSettings();
    }
  }

  Future<void> _startCompassServiceFromSettings() async {
    final settings = await Storage.loadSettings();
    useTrueNorth = (settings['useTrueNorth'] ?? true) == true;
    await CompassService.instance.stop();
    await CompassService.instance.start(CompassOptions(useTrueNorth: useTrueNorth));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _magnetometerSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _headingSub?.cancel();
    super.dispose();
  }

  // Load current weather for wind direction
  Future<void> _loadWeatherData() async {
    Timer? timeout;
    try {
      setState(() { isLoadingWeather = true; });
      // Hard-stop the spinner if weather fetch takes too long
      timeout = Timer(const Duration(seconds: 15), () {
        if (!mounted) return;
        if (isLoadingWeather) {
          setState(() { isLoadingWeather = false; });
        }
      });

      final data = await WeatherService.getCurrentWeather();
      if (!mounted) return;
      timeout?.cancel();
      // Guard: don't overwrite with fallback zeros
      final isFallback = data != null && data['apiSource'] == 'Fallback Data';
      setState(() {
        if (!isFallback) {
          weatherData = data;
        }
        isLoadingWeather = false;
      });
    } catch (_) {
      timeout?.cancel();
      if (!mounted) return;
      setState(() { isLoadingWeather = false; });
    }
  }

  Future<void> _loadCalibrationOffset() async {
    final settings = await Storage.loadSettings();
    if (!mounted) return;
    setState(() {
      calibrationOffsetDeg = (settings['compassCalibrationOffsetDeg'] ?? 0.0).toDouble();
    });
  }

  // Get current location and elevation
  Future<void> _getCurrentLocation() async {
    Timer? timeout;
    try {
      setState(() {
        isLoadingLocation = true;
      });

      // Ensure the loading spinner doesn't persist on iOS if location stalls
      timeout = Timer(const Duration(seconds: 12), () {
        if (!mounted) return;
        if (isLoadingLocation) {
          setState(() {
            isLoadingLocation = false;
            locationName = 'Location not available';
          });
        }
      });

      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          setState(() {
            locationName = 'Location permission denied';
            isLoadingLocation = false;
          });
          return;
        }
      }

      // Get current position
      currentPosition = await Geolocator
          .getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
          .timeout(const Duration(seconds: 10));

      // Get location name using reverse geocoding
      try {
        await _getLocationName(currentPosition!.latitude, currentPosition!.longitude)
            .timeout(const Duration(seconds: 8));
      } on TimeoutException {
        // If reverse geocoding stalls, keep coordinates and show generic name
        if (!mounted) return;
        setState(() {
          locationName = 'Unknown Location';
        });
      }

      // Get magnetic declination for precise True North
      try {
        final decl = await DeclinationService.getDeclination(
          latitude: currentPosition!.latitude,
          longitude: currentPosition!.longitude,
          elevationMeters: currentPosition!.altitude,
        );
        if (!mounted) return;
        setState(() {
          magneticDeclinationDeg = decl; // may be null if API fails
        });
      } catch (_) {}

      if (!mounted) return;
      timeout?.cancel();
      setState(() {
        elevation = currentPosition!.altitude;
        isLoadingLocation = false;
      });
    } catch (e) {
      timeout?.cancel();
      if (!mounted) return;
      setState(() {
        locationName = 'Unable to get location';
        isLoadingLocation = false;
      });
    }
  }

  // Get location name from coordinates
  Future<void> _getLocationName(double lat, double lon) async {
    try {
      final response = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&addressdetails=1'),
        headers: {'User-Agent': 'MOI_Snipers_App'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final address = data['address'];
        
        String city = address['city'] ?? 
                     address['town'] ?? 
                     address['village'] ?? 
                     address['municipality'] ?? 
                     'Unknown';
        String country = address['country'] ?? '';
        
        if (!mounted) return;
        setState(() {
          locationName = '$city, $country';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        locationName = 'Unknown Location';
      });
    }
  }

  // Start compass with improved accuracy
  void _startCompass() {
    double smoothedHeading = 0.0;
    bool isFirstReading = true;
    // Listen to accelerometer for tilt compensation
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent a) {
      _lastAccel = a;
    });
    
    _magnetometerSubscription = magnetometerEvents.listen((MagnetometerEvent event) {
      // Robust tilt compensation via cross-product method
      // Device coordinates (x: right, y: up, z: out of screen)
      double mx = event.x, my = event.y, mz = event.z;

      double heading;
      if (_lastAccel != null) {
        double ax = _lastAccel!.x, ay = _lastAccel!.y, az = _lastAccel!.z;
        // Normalize vectors
        double gNorm = math.sqrt(ax*ax + ay*ay + az*az);
        if (gNorm > 0) { ax /= gNorm; ay /= gNorm; az /= gNorm; }
        double mNorm = math.sqrt(mx*mx + my*my + mz*mz);
        if (mNorm > 0) { mx /= mNorm; my /= mNorm; mz /= mNorm; }

        // Horizontal axes
        // East = m × g
        double Ex = my*az - mz*ay;
        double Ey = mz*ax - mx*az;
        double Ez = mx*ay - my*ax;
        double eNorm = math.sqrt(Ex*Ex + Ey*Ey + Ez*Ez);
        if (eNorm > 0) { Ex /= eNorm; Ey /= eNorm; Ez /= eNorm; }

        // North = g × E
        double Nx = ay*Ez - az*Ey;
        double Ny = az*Ex - ax*Ez;
        double Nz = ax*Ey - ay*Ex;

        // Heading: use Y-axis-based calculation; fallback to raw magnetometer if degenerate
        final yawY = math.atan2(Ey, Ny) * (180 / math.pi);
        final yawX = math.atan2(Ex, Nx) * (180 / math.pi);
        if ((Ex.abs() + Ey.abs() + Nx.abs() + Ny.abs()) < 1e-6) {
          heading = math.atan2(my, mx) * (180 / math.pi);
        } else {
          heading = yawY;
        }
      } else {
        // Fallback for level device
        heading = math.atan2(my, mx) * (180 / math.pi);
      }

      // Convert to compass heading (0° = North, clockwise) and normalize
      heading = (heading + 360) % 360;
      
      // Apply magnetic declination correction if available
      if (currentPosition != null) {
        final declination = magneticDeclinationDeg ?? 3.5; // fallback approx
        heading = (heading + declination) % 360;
      }

      // Apply calibration offset to minimize cross-device variance
      heading = (heading + calibrationOffsetDeg) % 360;
      
      // Initialize on first reading
      if (isFirstReading) {
        smoothedHeading = heading;
        compassHeading = heading;
        isFirstReading = false;
      }
      
      // Apply enhanced smoothing for stability and accuracy
      double alpha = 0.15; // Balanced smoothing for responsiveness and stability
      double diff = heading - smoothedHeading;
      
      // Handle 0/360 degree boundary smoothly
      if (diff > 180) {
        diff -= 360;
      } else if (diff < -180) {
        diff += 360;
      }
      
      // Apply exponential smoothing with boundary handling
      smoothedHeading = smoothedHeading + diff * alpha;
      
      // Normalize the smoothed heading
      if (smoothedHeading < 0) {
        smoothedHeading += 360;
      } else if (smoothedHeading >= 360) {
        smoothedHeading -= 360;
      }
      
      // Additional accuracy enhancement: filter out extreme jumps
      if (diff.abs() > 45) {
        // If the change is too large, reduce the smoothing factor
        alpha = 0.05;
        smoothedHeading = smoothedHeading + diff * alpha;
      }

      setState(() {
        compassHeading = smoothedHeading;
      });
      
    });
  }

  // Calibrate compass
  void _calibrateCompass() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Calibrate Compass'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('To calibrate your compass for better accuracy:'),
              SizedBox(height: 12),
              Text('1. Hold your device flat and level'),
              Text('2. Move it in a figure-8 motion'),
              Text('3. Rotate it 360° horizontally'),
              Text('4. Repeat until compass stabilizes'),
              SizedBox(height: 12),
              Text('Make sure you\'re away from:'),
              Text('• Metal objects'),
              Text('• Electronic devices'),
              Text('• Magnetic interference'),
              SizedBox(height: 8),
              Text('This will improve compass accuracy and responsiveness.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Get cardinal direction from heading
  String _getCardinalDirection(double heading) {
    List<String> directions = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    int index = ((heading + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  // Format coordinates
  String _formatCoordinates(double lat, double lon) {
    String latDir = lat >= 0 ? 'N' : 'S';
    String lonDir = lon >= 0 ? 'E' : 'W';
    
    int latDeg = lat.abs().floor();
    int latMin = ((lat.abs() - latDeg) * 60).floor();
    int latSec = (((lat.abs() - latDeg) * 60 - latMin) * 60).floor();
    
    int lonDeg = lon.abs().floor();
    int lonMin = ((lon.abs() - lonDeg) * 60).floor();
    int lonSec = (((lon.abs() - lonDeg) * 60 - lonMin) * 60).floor();
    
    return '${latDeg}°${latMin}′${latSec}″ $latDir ${lonDeg}°${lonMin}′${lonSec}″ $lonDir';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        title: Text(Localizations.localeOf(context).languageCode == 'ar' ? 'البوصلة' : 'Compass'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: SafeArea(
        child: Column(
          children: [
            
            // Compass
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Compass dial (copied design from Home screen)
                    Container(
                      width: 290,
                      height: 290,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                            blurRadius: 15,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Rotating compass face
                          Transform.rotate(
                            angle: -compassHeading * (math.pi / 180),
                            child: Container(
                              width: 280,
                              height: 280,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).colorScheme.background,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.outline,
                                  width: 1,
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Degree markings
                                  ..._buildDegreeMarkings(),
                                  // Cardinal directions
                                  ..._buildCardinalDirections(),

                                  // Cross lines: N–S and W–E connected to cardinal letters
                                  Positioned.fill(
                                    child: Center(
                                      child: Container(
                                        width: 2,
                                        height: 160,
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: Center(
                                      child: Container(
                                        width: 160,
                                        height: 2,
                                        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ),

                                  // Wind direction arrow (green) from weather API
                                  if (weatherData?['windDirection'] != null)
                                    SizedBox(
                                      width: 280,
                                      height: 280,
                                      child: Transform.rotate(
                                        angle: (weatherData!['windDirection'] as double) * (math.pi / 180),
                                        child: Align(
                                          alignment: Alignment.topCenter,
                                          child: Padding(
                                            padding: const EdgeInsets.only(top: 18),
                                            child: Container(
                                              width: 0,
                                              height: 0,
                                              decoration: const BoxDecoration(
                                                border: Border(
                                                  left: BorderSide(color: Colors.transparent, width: 8),
                                                  right: BorderSide(color: Colors.transparent, width: 8),
                                                  bottom: BorderSide(color: Colors.green, width: 12),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // Fixed North indicator (red triangle) at top, like Home
                          Positioned(
                            top: 20,
                            child: Container(
                              width: 0,
                              height: 0,
                              decoration: const BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: Colors.transparent, width: 8),
                                  right: BorderSide(color: Colors.transparent, width: 8),
                                  bottom: BorderSide(color: Colors.red, width: 12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 40),
                    
                    // Heading display
                    Text(
                      '${compassHeading.toStringAsFixed(0)}° ${_getCardinalDirection(compassHeading)}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onBackground,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    
                    const SizedBox(height: 20),

                    // Calibration button
                    ElevatedButton.icon(
                      onPressed: _calibrateCompass,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Calibrate Compass'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),

                    const SizedBox(height: 12),
                    // Wind direction value (from Home screen logic)
                    if (isLoadingWeather)
                      CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)
                    else if (weatherData != null) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.rotate(
                            angle: (weatherData!['windDirection'] ?? 0) * (math.pi / 180),
                            child: const Icon(Icons.navigation, size: 20, color: Colors.green),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Wind: ${WeatherService.getWindDirection(weatherData!['windDirection'] ?? 0)} (${(weatherData!['windDirection'] ?? 0).toStringAsFixed(0)}°)',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onBackground,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        AppLocalizations.of(context)!.weatherDataNotAvailable,
                        style: TextStyle(color: Colors.orange),
                      ),
                    ],

                    const SizedBox(height: 20),
                    
                    // Location information
                    if (isLoadingLocation)
                      CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)
                    else ...[
                      // Coordinates
                      if (currentPosition != null)
                        Text(
                          _formatCoordinates(currentPosition!.latitude, currentPosition!.longitude),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onBackground,
                            fontSize: 14,
                          ),
                        ),
                      
                      const SizedBox(height: 8),
                      
                      // Location name
                      Text(
                        locationName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onBackground,
                          fontSize: 16,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Elevation
                      if (currentPosition != null)
                        Text(
                          '${elevation.toStringAsFixed(0)} m Elevation',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onBackground,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build degree markings
  List<Widget> _buildDegreeMarkings() {
    List<Widget> markings = [];
    
    // Add degree numbers (0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330)
    List<int> degreeNumbers = [0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330];
    
    for (int degree in degreeNumbers) {
      double angle = degree * (math.pi / 180);
      double radius = 120; // Outer radius for numbers
      double x = radius * math.sin(angle);
      double y = -radius * math.cos(angle);
      
      markings.add(
        Positioned(
          left: 140 + x - 12,
          top: 140 + y - 8,
          child: Transform.rotate(
            // Counter-rotate so labels stay upright when dial rotates
            angle: compassHeading * (math.pi / 180),
            child: Text(
              degree.toString(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }
    
    // Add tick marks for every 5 degrees
    for (int i = 0; i < 72; i++) {
      double angle = (i * 5) * (math.pi / 180);
      double radius = 130;
      double x = radius * math.sin(angle);
      double y = -radius * math.cos(angle);
      
      bool isMainMarker = i % 18 == 0; // Every 90 degrees
      bool isSubMarker = i % 6 == 0; // Every 30 degrees
      
      double markerWidth = isMainMarker ? 3 : (isSubMarker ? 2 : 1);
      double markerHeight = isMainMarker ? 15 : (isSubMarker ? 10 : 5);
      
      markings.add(
        Positioned(
          left: 140 + x - (markerWidth / 2),
          top: 140 + y - (markerHeight / 2),
          child: Container(
            width: markerWidth,
            height: markerHeight,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onBackground,
              borderRadius: BorderRadius.circular(markerWidth / 2),
            ),
          ),
        ),
      );
    }
    
    return markings;
  }

  // Build cardinal directions
  List<Widget> _buildCardinalDirections() {
    List<Widget> directions = [];
    List<String> directionLabels = ['N', 'E', 'S', 'W'];
    
    for (int i = 0; i < directionLabels.length; i++) {
      double angle = (i * 90) * (math.pi / 180);
      double radius = 80; // Inner radius for cardinal directions
      double x = radius * math.sin(angle);
      double y = -radius * math.cos(angle);
      
      directions.add(
        Positioned(
          left: 140 + x - 12,
          top: 140 + y - 12,
          child: Transform.rotate(
            // Keep N/E/S/W upright relative to screen
            angle: compassHeading * (math.pi / 180),
            child: Text(
              directionLabels[i],
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ),
      );
    }
    
    return directions;
  }
}
