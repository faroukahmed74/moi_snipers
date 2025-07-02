import 'package:flutter/material.dart';
import '../models.dart';
import '../main.dart';
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<SniperType> snipers = [];
  SniperType? selectedSniper;
  bool isLoading = true;
  String distanceUnit = 'meters';
  String windUnit = 'm/s';
  double distance = 100.0;
  double windSpeed = 0.0;
  double windAngle = 90.0;
  String result = '';
  String details = '';
  
  // Weather data
  Map<String, dynamic>? weatherData;
  bool isLoadingWeather = false;

  String? latestVersion;
  String? appVersion;

  @override
  void initState() {
    super.initState();
    _loadSnipersAndSettings();
    _loadWeatherData();
    _checkForUpdate();
    _loadAppVersion();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForUpdate();
    }
  }

  Future<void> _loadSnipersAndSettings() async {
    final loadedSnipers = await Storage.loadSniperTypes();
    final settings = await Storage.loadSettings();
    setState(() {
      snipers = loadedSnipers;
      selectedSniper = null; // No default selection
      distanceUnit = settings['distanceUnit'] ?? 'meters';
      windUnit = settings['windUnit'] ?? 'm/s';
      isLoading = false;
    });
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

  void calculateClicks() {
    if (selectedSniper == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a sniper type first.')),
      );
      return;
    }
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
    final output = BallisticsCalculator.calculateMOAAndClicksMilitary(
      sniper: selectedSniper!,
      distance: distance,
      windSpeed: windSpeed,
      windAngle: windAngle,
      distanceUnit: distanceUnit,
    );
    
    // Calculate range correction clicks
    double distanceMeters = distanceUnit == 'meters' ? distance : distance * 0.9144;
    int rangeCorrectionClicks = selectedSniper!.getRangeCorrectionClicks(distanceMeters);
    
    setState(() {
      String resultText = '';
      
      // 1. Clicks Up (range correction clicks) - FIRST (always show)
      resultText += 'Clicks Up: $rangeCorrectionClicks\n';
      
      // 2. Clicks (windage clicks) - SECOND
      resultText += '${AppLocalizations.of(context)!.clicks}: ${output['clicks']!.toStringAsFixed(2)}\n';
      
      // 3. MOA (windage MOA) - THIRD
      resultText += 'MOA: ${output['moa']!.toStringAsFixed(2)}';
      
      result = resultText;
      
      // Find the constant used for display
      double constantUsed = 13.0;
      if (distanceMeters >= 1 && distanceMeters <= 599) {
        constantUsed = 13.0;
      } else if (distanceMeters >= 600 && distanceMeters <= 699) {
        constantUsed = 12.0;
      } else if (distanceMeters >= 700 && distanceMeters <= 799) {
        constantUsed = 11.0;
      } else if (distanceMeters >= 800 && distanceMeters <= 899) {
        constantUsed = 10.0;
      } else if (distanceMeters >= 900 && distanceMeters <= 999) {
        constantUsed = 9.0;
      }
      String formulaString;
      if (windAngle == 90) {
        formulaString = 'MOA = (Wind Speed (mph) × 0.01 × Range (yards)) / CONSTANT';
      } else {
        formulaString = 'MOA = ((Wind Speed (mph) × 0.01 × Range (yards)) / CONSTANT) × (Angle / 90)';
      }
      details =
        'Sniper: ${selectedSniper!.name}\n'
        'Distance: $distance $distanceUnit (${distanceMeters.toStringAsFixed(0)}m)\n'
        'Wind: $windSpeed mph\n'
        'Angle: $windAngle°\n'
        'Constant Used: $constantUsed\n'
        'MOA→Clicks Factor: ${selectedSniper!.moaToClickFactor}\n'
        'Muzzle Velocity: ${selectedSniper!.muzzleVelocity} m/s\n'
        'Range Correction Available: ${selectedSniper!.rangeCorrectionClicks.isNotEmpty ? "Yes" : "No"}\n'
        'Military Formula:\n'
        '$formulaString\n'
        'Clicks = MOA × MOA→Clicks Factor\n'
        'MOA: ${output['moa']!.toStringAsFixed(2)}\nClicks: ${output['clicks']!.toStringAsFixed(1)}';
      
      // Add range correction information to details
      if (rangeCorrectionClicks > 0) {
        details += '\n\nRange Correction:\nClicks Up: $rangeCorrectionClicks (for ${distanceMeters.toStringAsFixed(0)}m range)';
      } else {
        details += '\n\nRange Correction:\nClicks Up: 0 (no correction needed or not available for this sniper/distance)';
      }
    });
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
              onTap: () => Navigator.pushNamed(context, '/snipers'),
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.settings),
              onTap: () => Navigator.pushNamed(context, '/settings'),
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.references),
              onTap: () => Navigator.pushNamed(context, '/references'),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
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
                                      '${AppLocalizations.of(context)!.windGust}: ${weatherData!['windGust'] != null ? WeatherService.msToMph(weatherData!['windGust']).toStringAsFixed(1) + ' mph (gust)' : 'N/A'}',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.orange),
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
                                    });
                                    await Clipboard.setData(ClipboardData(text: windSpeedMph.toStringAsFixed(1)));
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
                            keyboardType: TextInputType.number,
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
                            keyboardType: TextInputType.number,
                            style: Theme.of(context).textTheme.bodyLarge,
                            onChanged: (val) {
                              setState(() {
                                windSpeed = double.tryParse(val) ?? 0.0;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('mph', style: Theme.of(context).textTheme.bodyLarge),
                      ],
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
                                divisions: 36,
                                label: windAngle.toStringAsFixed(0),
                                onChanged: (val) {
                                  setState(() {
                                    windAngle = val;
                                  });
                                },
                              ),
                            ],
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
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
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
    );
  }
} 