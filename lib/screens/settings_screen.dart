import 'package:flutter/material.dart';
import '../main.dart';
import '../l10n/app_localizations.dart';
import '../storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String selectedLanguage = 'en';
  String defaultDistanceUnit = 'meters';
  String defaultWindUnit = 'm/s';
  String selectedThemeMode = 'system';
  String? latestVersion;
  String? currentVersion;
  double calibrationOffsetDeg = 0.0;
  bool useTrueNorth = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersions();
  }

  Future<void> _loadSettings() async {
    final settings = await Storage.loadSettings();
    setState(() {
      selectedLanguage = settings['language'] ?? 'en';
      defaultDistanceUnit = settings['distanceUnit'] ?? 'meters';
      defaultWindUnit = settings['windUnit'] ?? 'm/s';
      selectedThemeMode = settings['themeMode'] ?? 'system';
      calibrationOffsetDeg = (settings['compassCalibrationOffsetDeg'] ?? 0.0).toDouble();
      useTrueNorth = (settings['useTrueNorth'] ?? true) == true;
    });
  }

  Future<void> _saveSettings() async {
    await Storage.saveSettings({
      'language': selectedLanguage,
      'distanceUnit': defaultDistanceUnit,
      'windUnit': defaultWindUnit,
      'themeMode': selectedThemeMode,
      'compassCalibrationOffsetDeg': calibrationOffsetDeg,
      'useTrueNorth': useTrueNorth,
    });
  }

  Future<void> _loadVersions() async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      final v = await UpdateService.getLatestVersion();
      setState(() {
        latestVersion = v;
      });
    }
    final info = await PackageInfo.fromPlatform();
    setState(() {
      currentVersion = '${info.version}+${info.buildNumber}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.settings)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 700;

          List<Widget> tiles = [
            _SettingsTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.language),
                  DropdownButton<String>(
                    value: selectedLanguage,
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'ar', child: Text('العربية')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() { selectedLanguage = val; });
                        _saveSettings();
                        if (val == 'ar') {
                          MyApp.of(context)?.setLocale(const Locale('ar'));
                        } else {
                          MyApp.of(context)?.setLocale(const Locale('en'));
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
            _SettingsTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.defaultDistanceUnit),
                  DropdownButton<String>(
                    value: defaultDistanceUnit,
                    items: [
                      DropdownMenuItem(value: 'meters', child: Text(AppLocalizations.of(context)!.meters)),
                      DropdownMenuItem(value: 'yards', child: Text(AppLocalizations.of(context)!.yards)),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() { defaultDistanceUnit = val; });
                        _saveSettings();
                      }
                    },
                  ),
                ],
              ),
            ),
            _SettingsTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.defaultWindUnit),
                  DropdownButton<String>(
                    value: defaultWindUnit,
                    items: [
                      DropdownMenuItem(value: 'm/s', child: Text(AppLocalizations.of(context)!.ms)),
                      DropdownMenuItem(value: 'km/h', child: Text(AppLocalizations.of(context)!.kmh)),
                      DropdownMenuItem(value: 'mph', child: Text(AppLocalizations.of(context)!.mph)),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() { defaultWindUnit = val; });
                        _saveSettings();
                      }
                    },
                  ),
                ],
              ),
            ),
            _SettingsTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.themeMode),
                  DropdownButton<String>(
                    value: selectedThemeMode,
                    items: [
                      DropdownMenuItem(value: 'system', child: Text(AppLocalizations.of(context)!.system)),
                      DropdownMenuItem(value: 'light', child: Text(AppLocalizations.of(context)!.light)),
                      DropdownMenuItem(value: 'dark', child: Text(AppLocalizations.of(context)!.dark)),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() { selectedThemeMode = val; });
                        _saveSettings();
                        ThemeMode themeMode;
                        switch (val) {
                          case 'light':
                            themeMode = ThemeMode.light;
                            break;
                          case 'dark':
                            themeMode = ThemeMode.dark;
                            break;
                          default:
                            themeMode = ThemeMode.system;
                        }
                        MyApp.of(context)?.setThemeMode(themeMode);
                      }
                    },
                  ),
                ],
              ),
            ),
            _SettingsTile(
              child: SwitchListTile(
                title: const Text('Use True North'),
                subtitle: const Text('Apply magnetic declination to show True North'),
                value: useTrueNorth,
                onChanged: (v) {
                  setState(() { useTrueNorth = v; });
                  _saveSettings();
                },
              ),
            ),
            _SettingsTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Compass offset (°)'),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: calibrationOffsetDeg,
                          min: -90.0,
                          max: 90.0,
                          divisions: 360,
                          label: calibrationOffsetDeg.toStringAsFixed(1),
                          onChanged: (v) {
                            setState(() { calibrationOffsetDeg = double.parse(v.toStringAsFixed(1)); });
                            _saveSettings();
                          },
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${calibrationOffsetDeg.toStringAsFixed(1)}°',
                          textAlign: TextAlign.right,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() { calibrationOffsetDeg = 0.0; });
                          _saveSettings();
                        },
                        child: const Text('Reset'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _SettingsTile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppLocalizations.of(context)!.about),
                  Text(AppLocalizations.of(context)!.aboutText),
                  if (Theme.of(context).platform == TargetPlatform.android && latestVersion != null)
                    Text('Latest version: $latestVersion'),
                  if (currentVersion != null)
                    Text('Current version: $currentVersion'),
                ],
              ),
            ),
          ];

          final content = Padding(
            padding: const EdgeInsets.all(16.0),
            child: isWide
                ? SingleChildScrollView(
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: tiles
                          .map((t) => SizedBox(
                                width: (constraints.maxWidth - 48) / 2,
                                child: t,
                              ))
                          .toList(),
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...tiles,
                      ],
                    ),
                  ),
          );

          return content;
        },
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final Widget child;
  const _SettingsTile({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: child,
      ),
    );
  }
}