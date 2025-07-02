import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class Storage {
  static const String snipersKey = 'sniper_types';
  static const String settingsKey = 'user_settings';

  // Sniper Types
  static Future<List<SniperType>> loadSniperTypes() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(snipersKey);
    if (jsonStr == null) {
      return SniperType.defaultSnipers();
    }
    final List<dynamic> jsonList = json.decode(jsonStr);
    return jsonList.map((e) => SniperType.fromMap(e)).toList();
  }

  static Future<void> saveSniperTypes(List<SniperType> snipers) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(snipers.map((e) => e.toMap()).toList());
    await prefs.setString(snipersKey, jsonStr);
  }

  // User Settings
  static Future<Map<String, dynamic>> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(settingsKey);
    if (jsonStr == null) {
      return {
        'language': 'en',
        'distanceUnit': 'meters',
        'windUnit': 'm/s',
        'themeMode': 'system',
      };
    }
    return json.decode(jsonStr);
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(settings);
    await prefs.setString(settingsKey, jsonStr);
  }

  // Theme Mode
  static Future<String> loadThemeMode() async {
    final settings = await loadSettings();
    return settings['themeMode'] ?? 'system';
  }

  static Future<void> saveThemeMode(String themeMode) async {
    final settings = await loadSettings();
    settings['themeMode'] = themeMode;
    await saveSettings(settings);
  }
} 