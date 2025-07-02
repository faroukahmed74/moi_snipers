import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class WeatherService {
  // TODO: Get your free API key from https://openweathermap.org/api
  // 1. Sign up for free account
  // 2. Go to "My API Keys" 
  // 3. Copy your API key and replace 'YOUR_API_KEY_HERE' below
  static const String apiKey = '700667676a71e72a9b31ff7be65b5ca7';
  static const String baseUrl = 'https://api.openweathermap.org/data/2.5/weather';

  static Future<Map<String, dynamic>?> getCurrentWeather() async {
    try {
      print('=== WEATHER SERVICE START ===');
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('Location services are disabled');
        return _getFallbackWeatherData();
      }
      
      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      print('Location permission: $permission');
      
      if (permission == LocationPermission.denied) {
        print('Requesting location permission...');
        permission = await Geolocator.requestPermission();
        print('Requested permission result: $permission');
        
        if (permission == LocationPermission.denied) {
          print('Location permission denied by user');
          return _getFallbackWeatherData();
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permission denied forever - user needs to enable in settings');
        return _getFallbackWeatherData();
      }

      // Get current position
      print('Getting current position...');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      print('Position: ${position.latitude}, ${position.longitude}');

      // Fetch weather data
      final url = '$baseUrl?lat=${position.latitude}&lon=${position.longitude}&appid=$apiKey&units=metric';
      print('Fetching from: $url');
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Weather data parsed successfully');
        
        final result = {
          'windSpeed': (data['wind']['speed'] as num).toDouble(),
          'windDirection': (data['wind']['deg'] as num).toDouble(),
          'windGust': data['wind']['gust'] != null ? (data['wind']['gust'] as num).toDouble() : null,
          'temperature': (data['main']['temp'] as num).toDouble(),
          'description': data['weather'][0]['description'],
          'location': data['name'],
          'latitude': position.latitude,
          'longitude': position.longitude,
        };
        
        print('Returning: $result');
        print('=== WEATHER SERVICE SUCCESS ===');
        return result;
      } else if (response.statusCode == 401) {
        print('API key is invalid. Please check your OpenWeatherMap API key.');
        print('=== WEATHER SERVICE API KEY ERROR ===');
        return _getFallbackWeatherData();
      } else {
        print('API error: ${response.statusCode} - ${response.body}');
        print('=== WEATHER SERVICE ERROR ===');
        return _getFallbackWeatherData();
      }
    } catch (e) {
      print('Exception: $e');
      print('=== WEATHER SERVICE EXCEPTION ===');
      return _getFallbackWeatherData();
    }
  }

  // Fallback weather data when location is not available
  static Map<String, dynamic> _getFallbackWeatherData() {
    print('Using fallback weather data');
    return {
      'windSpeed': 0.0,
      'windDirection': 0.0,
      'windGust': null,
      'temperature': 20.0,
      'description': 'Location access required',
      'location': 'Location not available',
      'latitude': 0.0,
      'longitude': 0.0,
    };
  }

  // Convert m/s to mph
  static double msToMph(double ms) {
    return ms * 2.237;
  }

  // Get wind direction as text
  static String getWindDirection(double degrees) {
    if (degrees >= 337.5 || degrees < 22.5) return 'N';
    if (degrees >= 22.5 && degrees < 67.5) return 'NE';
    if (degrees >= 67.5 && degrees < 112.5) return 'E';
    if (degrees >= 112.5 && degrees < 157.5) return 'SE';
    if (degrees >= 157.5 && degrees < 202.5) return 'S';
    if (degrees >= 202.5 && degrees < 247.5) return 'SW';
    if (degrees >= 247.5 && degrees < 292.5) return 'W';
    if (degrees >= 292.5 && degrees < 337.5) return 'NW';
    return 'N';
  }
} 