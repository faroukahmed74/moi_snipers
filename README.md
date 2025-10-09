# MOI Snipers

A Flutter application for sniper calculations with weather integration and compass functionality.

## Features

- **Weather Integration**: Real-time weather data from multiple APIs (Tomorrow.io, AccuWeather, OpenWeatherMap)
- **Compass**: Real-time compass with device orientation
- **Sniper Calculations**: Wind correction calculations with precision control
- **Location Services**: GPS-based location with reverse geocoding
- **Multi-platform**: Android APK and iOS support

## Setup

### API Keys Configuration

Before running the app, you need to configure weather API keys in `lib/weather_service.dart`:

1. **Tomorrow.io API Key**: Get from [Tomorrow.io Weather API](https://www.tomorrow.io/weather-api/)
2. **AccuWeather API Key**: Get from [AccuWeather Developer](https://developer.accuweather.com/)
3. **OpenWeatherMap API Key**: Get from [OpenWeatherMap API](https://openweathermap.org/api)

Replace the placeholder values in `lib/weather_service.dart`:
```dart
static const String tomorrowIoApiKey = 'YOUR_TOMORROW_IO_API_KEY';
static const String accuWeatherApiKey = 'YOUR_ACCUWEATHER_API_KEY';
static const String openWeatherMapApiKey = 'YOUR_OPENWEATHERMAP_API_KEY';
```

### Installation

1. Clone the repository
2. Install dependencies: `flutter pub get`
3. Configure API keys as described above
4. Run the app: `flutter run`

## Building for Release

### Android APK
```bash
flutter build apk --release
```

### iOS
```bash
flutter build ios --release
```

## Version History

- **v1.0.10**: Enhanced compass, wind gust display, location names, and precision improvements
- **v1.0.9**: Initial release with basic sniper calculations and weather integration
