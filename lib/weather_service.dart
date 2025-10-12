import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class WeatherService {
  // API Keys - Configured with your actual keys
  // Tomorrow.io: https://www.tomorrow.io/weather-api/
  // AccuWeather: https://developer.accuweather.com/
  // OpenWeatherMap: https://openweathermap.org/api
  static const String tomorrowIoApiKey = 'YeG99E0MIHalLUAfWxIuAKAvztNbEHpj';
  static const String accuWeatherApiKey = 'zpka_f646dd3584894fd0a85c6374192b0292_7f21e210';
  static const String openWeatherMapApiKey = '700667676a71e72a9b31ff7be65b5ca7';
  
  // API URLs
  static const String tomorrowIoBaseUrl = 'https://api.tomorrow.io/v4/weather/realtime';
  static const String accuWeatherBaseUrl = 'https://dataservice.accuweather.com/currentconditions/v1';
  static const String openWeatherMapBaseUrl = 'https://api.openweathermap.org/data/2.5/weather';

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

      // Get current position with robust fallback to last known location
      print('Getting current position...');
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
      } catch (e) {
        print('getCurrentPosition failed: $e');
      }

      if (position == null) {
        print('Attempting getLastKnownPosition fallback...');
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        print('No position available (current or last-known). Using fallback data.');
        return _getFallbackWeatherData();
      }

      print('Position: ${position.latitude}, ${position.longitude}');

      // Try APIs in order: Tomorrow.io -> AccuWeather -> OpenWeatherMap
      Map<String, dynamic>? result;
      
      // 1. Try Tomorrow.io (Primary)
      print('=== TRYING TOMORROW.IO (PRIMARY) ===');
      result = await _fetchFromTomorrowIo(position);
      if (result != null) {
        print('=== TOMORROW.IO SUCCESS ===');
        return result;
      }
      
      // 2. Try AccuWeather (Secondary)
      print('=== TRYING ACCUWEATHER (SECONDARY) ===');
      result = await _fetchFromAccuWeather(position);
      if (result != null) {
        print('=== ACCUWEATHER SUCCESS ===');
        return result;
      }
      
      // 3. Try OpenWeatherMap (Tertiary)
      print('=== TRYING OPENWEATHERMAP (TERTIARY) ===');
      result = await _fetchFromOpenWeatherMap(position);
      if (result != null) {
        print('=== OPENWEATHERMAP SUCCESS ===');
        return result;
      }
      
      // All APIs failed
      print('=== ALL WEATHER APIS FAILED ===');
      return _getFallbackWeatherData();
      
    } catch (e) {
      print('Exception: $e');
      print('=== WEATHER SERVICE EXCEPTION ===');
      return _getFallbackWeatherData();
    }
  }

  // Tomorrow.io API fetch
  static Future<Map<String, dynamic>?> _fetchFromTomorrowIo(Position position) async {
    try {
      final url = '$tomorrowIoBaseUrl?location=${position.latitude},${position.longitude}&apikey=$tomorrowIoApiKey&units=metric';
      print('Tomorrow.io URL: $url');
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );
      
      print('Tomorrow.io Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Tomorrow.io data parsed successfully');
        
        // Extract data from Tomorrow.io response
        final values = data['data']['values'];
        
        // Get location name using reverse geocoding
        final locationName = await _getLocationName(position);
        
        final result = {
          'windSpeed': (values['windSpeed'] as num).toDouble(),
          'windDirection': (values['windDirection'] as num).toDouble(),
          'windGust': values['windGust'] != null ? (values['windGust'] as num).toDouble() : null,
          'temperature': (values['temperature'] as num).toDouble(),
          'description': values['weatherCode'] != null ? _getWeatherDescription(values['weatherCode']) : 'Clear',
          'location': locationName,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'apiSource': 'Tomorrow.io',
        };
        
        print('Tomorrow.io result: $result');
        return result;
      } else {
        print('Tomorrow.io API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Tomorrow.io exception: $e');
      return null;
    }
  }

  // Get location name using reverse geocoding
  static Future<String> _getLocationName(Position position) async {
    try {
      // Use OpenStreetMap Nominatim for reverse geocoding (free)
      final url = 'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1';
      print('Reverse geocoding URL: $url');
      
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'MOI_Snipers_App/1.0'},
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Reverse geocoding response: $data');
        
        final address = data['address'];
        if (address != null) {
          // Try to get city name in order of preference
          return address['city'] ?? 
                 address['town'] ?? 
                 address['village'] ?? 
                 address['municipality'] ?? 
                 address['county'] ?? 
                 address['state'] ?? 
                 'Current Location';
        }
      }
    } catch (e) {
      print('Reverse geocoding exception: $e');
    }
    return 'Current Location';
  }

  // AccuWeather API fetch
  static Future<Map<String, dynamic>?> _fetchFromAccuWeather(Position position) async {
    try {
      // First, get location key
      final locationUrl = 'https://dataservice.accuweather.com/locations/v1/cities/geoposition/search?apikey=$accuWeatherApiKey&q=${position.latitude},${position.longitude}';
      print('AccuWeather location URL: $locationUrl');
      
      final locationResponse = await http.get(Uri.parse(locationUrl)).timeout(
        const Duration(seconds: 10),
      );
      
      if (locationResponse.statusCode != 200) {
        print('AccuWeather location error: ${locationResponse.statusCode}');
        return null;
      }
      
      final locationData = json.decode(locationResponse.body);
      final locationKey = locationData['Key'];
      final locationName = locationData['LocalizedName'];
      
      // Get current conditions
      final conditionsUrl = '$accuWeatherBaseUrl/$locationKey?apikey=$accuWeatherApiKey&details=true';
      print('AccuWeather conditions URL: $conditionsUrl');
      
      final response = await http.get(Uri.parse(conditionsUrl)).timeout(
        const Duration(seconds: 10),
      );
      
      print('AccuWeather Response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('AccuWeather data parsed successfully');
        
        // Extract data from AccuWeather response
        final current = data[0];
        final result = {
          'windSpeed': (current['Wind']['Speed']['Metric']['Value'] as num).toDouble() / 3.6, // Convert km/h to m/s
          'windDirection': (current['Wind']['Direction']['Degrees'] as num).toDouble(),
          'windGust': current['WindGust'] != null ? (current['WindGust']['Speed']['Metric']['Value'] as num).toDouble() / 3.6 : null,
          'temperature': (current['Temperature']['Metric']['Value'] as num).toDouble(),
          'description': current['WeatherText'],
          'location': locationName,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'apiSource': 'AccuWeather',
        };
        
        print('AccuWeather result: $result');
        return result;
      } else {
        print('AccuWeather API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('AccuWeather exception: $e');
      return null;
    }
  }

  // OpenWeatherMap API fetch (existing implementation)
  static Future<Map<String, dynamic>?> _fetchFromOpenWeatherMap(Position position) async {
    try {
      final url = '$openWeatherMapBaseUrl?lat=${position.latitude}&lon=${position.longitude}&appid=$openWeatherMapApiKey&units=metric';
      print('OpenWeatherMap URL: $url');
      
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );

      print('OpenWeatherMap Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('OpenWeatherMap data parsed successfully');
        
        final result = {
          'windSpeed': (data['wind']['speed'] as num).toDouble(),
          'windDirection': (data['wind']['deg'] as num).toDouble(),
          'windGust': data['wind']['gust'] != null ? (data['wind']['gust'] as num).toDouble() : null,
          'temperature': (data['main']['temp'] as num).toDouble(),
          'description': data['weather'][0]['description'],
          'location': data['name'],
          'latitude': position.latitude,
          'longitude': position.longitude,
          'apiSource': 'OpenWeatherMap',
        };
        
        print('OpenWeatherMap result: $result');
        return result;
      } else {
        print('OpenWeatherMap API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('OpenWeatherMap exception: $e');
      return null;
    }
  }

  // Convert Tomorrow.io weather code to description
  static String _getWeatherDescription(int weatherCode) {
    // Tomorrow.io weather codes mapping
    switch (weatherCode) {
      case 1000: return 'Clear';
      case 1100: return 'Mostly Clear';
      case 1101: return 'Partly Cloudy';
      case 1102: return 'Mostly Cloudy';
      case 1001: return 'Cloudy';
      case 2000: return 'Fog';
      case 2100: return 'Light Fog';
      case 4000: return 'Drizzle';
      case 4001: return 'Rain';
      case 4200: return 'Light Rain';
      case 4201: return 'Heavy Rain';
      case 5000: return 'Snow';
      case 5001: return 'Flurries';
      case 5100: return 'Light Snow';
      case 5101: return 'Heavy Snow';
      case 6000: return 'Freezing Drizzle';
      case 6001: return 'Freezing Rain';
      case 6200: return 'Light Freezing Rain';
      case 6201: return 'Heavy Freezing Rain';
      case 7000: return 'Ice Pellets';
      case 7101: return 'Heavy Ice Pellets';
      case 7102: return 'Light Ice Pellets';
      case 8000: return 'Thunderstorm';
      default: return 'Unknown';
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
      'apiSource': 'Fallback Data',
    };
  }

  // Convert m/s to mph
  static double msToMph(double ms) {
    return ms * 2.237;
  }

  // Convert m/s to km/h
  static double msToKmh(double ms) {
    return ms * 3.6;
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