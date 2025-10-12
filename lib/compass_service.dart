import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';

import 'declination_service.dart';
import 'storage.dart';

class CompassOptions {
  final bool useTrueNorth; // if true, apply magnetic declination
  final double calibrationOffsetDeg; // user-set offset to align across devices
  final double? overrideDeclinationDeg; // optional declination override

  const CompassOptions({
    this.useTrueNorth = true,
    this.calibrationOffsetDeg = 0.0,
    this.overrideDeclinationDeg,
  });
}

class CompassService {
  CompassService._();
  static final CompassService instance = CompassService._();

  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<CompassEvent>? _iosCompassSub;
  final _headingController = StreamController<double>.broadcast();
  AccelerometerEvent? _lastAccel;
  double? _declinationDeg;
  bool _running = false;
  DateTime? _lastUpdate;
  Timer? _watchdog;
  int _accCount = 0;
  int _magCount = 0;
  int _iosEventCount = 0;

  Stream<double> get headingStream => _headingController.stream;

  Future<void> _ensureDeclination(CompassOptions options) async {
    if (!options.useTrueNorth) {
      _declinationDeg = 0.0;
      return;
    }
    if (options.overrideDeclinationDeg != null) {
      _declinationDeg = options.overrideDeclinationDeg;
      return;
    }
    if (_declinationDeg != null) return;
    try {
      // Get current position for accurate declination
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        _declinationDeg = 0.0; // fallback when permission is blocked
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
      _declinationDeg = await DeclinationService.getDeclination(
        latitude: pos.latitude,
        longitude: pos.longitude,
        elevationMeters: pos.altitude,
      );
    } catch (_) {
      _declinationDeg = 0.0; // graceful fallback
    }
  }

  Future<void> start(CompassOptions options) async {
    if (_running) return;
    _running = true;
    print('[CompassService] start(useTrueNorth=${options.useTrueNorth})');

    // Load calibration offset from storage if not provided explicitly
    double calibrationOffset = options.calibrationOffsetDeg;
    if (calibrationOffset == 0.0) {
      try {
        final settings = await Storage.loadSettings();
        calibrationOffset = (settings['compassCalibrationOffsetDeg'] ?? 0.0).toDouble();
      } catch (_) {}
    }

    // iOS-only fixed bias to align with Apple Compass (default -6°)
    double iosHeadingOffsetDeg = 0.0;
    if (Platform.isIOS) {
      try {
        final settings = await Storage.loadSettings();
        iosHeadingOffsetDeg = ((settings['iosHeadingOffsetDeg'] ?? -6.0) as num).toDouble();
      } catch (_) {
        iosHeadingOffsetDeg = -6.0;
      }
    }

    await _ensureDeclination(options);

    final iosExtra = Platform.isIOS ? ', iosOffset=${iosHeadingOffsetDeg.toStringAsFixed(2)}°' : '';
    print('[CompassService] declinationDeg=${(_declinationDeg ?? 0.0).toStringAsFixed(2)}°, calibrationOffset=${calibrationOffset.toStringAsFixed(2)}°$iosExtra');

    double smoothedHeading = 0.0;
    bool first = true;

    // iOS: use native heading via FlutterCompass to match Apple Compass
    if (Platform.isIOS) {
      _iosCompassSub = FlutterCompass.events?.listen((CompassEvent event) {
        final h = event.heading;
        if (h == null) return;
        _iosEventCount++;
        _lastUpdate = DateTime.now();
        double heading = (h + 360) % 360;

        // Apply declination for True North if requested
        final decl = (_declinationDeg ?? 0.0);
        if (options.useTrueNorth) {
          heading = (heading + decl) % 360;
        }

        // Apply calibration offset and iOS platform bias
        heading = (heading + calibrationOffset) % 360;
        heading = (heading + iosHeadingOffsetDeg) % 360;

        if (first) {
          smoothedHeading = heading;
          first = false;
          print('[CompassService] iOS first heading: ${smoothedHeading.toStringAsFixed(1)}°');
        }

        double alpha = 0.15;
        double diff = heading - smoothedHeading;
        if (diff > 180) diff -= 360; else if (diff < -180) diff += 360;
        smoothedHeading = smoothedHeading + diff * alpha;
        if (smoothedHeading < 0) smoothedHeading += 360; else if (smoothedHeading >= 360) smoothedHeading -= 360;

        if (!_headingController.isClosed) {
          _headingController.add(smoothedHeading);
          if ((_iosEventCount % 30) == 0) {
            print('[CompassService] iOS heading tick: ${smoothedHeading.toStringAsFixed(1)}°');
          }
        }
      });

      // If FlutterCompass produces no events shortly after start, fall back to raw sensors
      Timer(const Duration(seconds: 3), () {
        if (!_running) return;
        if (_iosEventCount == 0) {
          print('[CompassService] iOS: no FlutterCompass events; falling back to magnetometer');
          _iosCompassSub?.cancel();
          _iosCompassSub = null;

          // Set up accelerometer for tilt compensation
          _accSub = accelerometerEvents.listen((a) {
            _lastAccel = a;
            _lastUpdate = DateTime.now();
            _accCount++;
            if (_accCount <= 3) {
              print('[CompassService] accel: x=${a.x.toStringAsFixed(2)}, y=${a.y.toStringAsFixed(2)}, z=${a.z.toStringAsFixed(2)}');
            }
          });

          // Magnetometer-based heading (same as Android path)
          _magSub = magnetometerEvents.listen((m) {
            _lastUpdate = DateTime.now();
            _magCount++;
            if (_magCount <= 3) {
              print('[CompassService] mag: x=${m.x.toStringAsFixed(2)}, y=${m.y.toStringAsFixed(2)}, z=${m.z.toStringAsFixed(2)}');
            }

            double mx = m.x, my = m.y, mz = m.z;
            double heading;

            if (_lastAccel != null) {
              double ax = _lastAccel!.x, ay = _lastAccel!.y, az = _lastAccel!.z;
              // Normalize
              double gNorm = math.sqrt(ax*ax + ay*ay + az*az);
              if (gNorm > 0) { ax /= gNorm; ay /= gNorm; az /= gNorm; }
              double mNorm = math.sqrt(mx*mx + my*my + mz*mz);
              if (mNorm > 0) { mx /= mNorm; my /= mNorm; mz /= mNorm; }

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

              // Prefer azimuth from North vector projection
              final azimuth = math.atan2(Nx, Ny) * (180 / math.pi);
              if ((Ex.abs() + Ey.abs() + Nx.abs() + Ny.abs()) < 1e-6) {
                print('[CompassService] Degenerate tilt-comp vectors; using raw magnetometer');
                heading = math.atan2(my, mx) * (180 / math.pi);
              } else {
                heading = azimuth;
              }
            } else {
              heading = math.atan2(my, mx) * (180 / math.pi);
            }

            // Normalize and apply options
            heading = (heading + 360) % 360;
            final decl = (_declinationDeg ?? 0.0);
            if (options.useTrueNorth) {
              heading = (heading + decl) % 360;
            }
            heading = (heading + calibrationOffset) % 360;

            if (first) {
              smoothedHeading = heading;
              first = false;
              print('[CompassService] First heading: ${smoothedHeading.toStringAsFixed(1)}°');
            }

            double alpha = 0.15;
            double diff = heading - smoothedHeading;
            if (diff > 180) diff -= 360; else if (diff < -180) diff += 360;
            smoothedHeading = smoothedHeading + diff * alpha;
            if (smoothedHeading < 0) smoothedHeading += 360; else if (smoothedHeading >= 360) smoothedHeading -= 360;

            if (!_headingController.isClosed) {
              _headingController.add(smoothedHeading);
              if ((_magCount % 30) == 0) {
                print('[CompassService] heading tick: ${smoothedHeading.toStringAsFixed(1)}° (events mag=$_magCount acc=$_accCount)');
              }
            }
          });

          // Watchdog for stalled streams
          _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
            if (!_running) return;
            final last = _lastUpdate;
            if (last == null) {
              print('[CompassService] No sensor updates yet…');
              return;
            }
            final gap = DateTime.now().difference(last).inSeconds;
            if (gap > 4) {
              print('[CompassService] Warning: no sensor updates for ${gap}s');
            }
          });
        }
      });

      // Watchdog: detect stalled FlutterCompass stream and auto-restart service
      _watchdog ??= Timer.periodic(const Duration(seconds: 5), (_) async {
        if (!_running) return;
        final last = _lastUpdate;
        if (last == null) return; // let initial fallback handle startup
        final gap = DateTime.now().difference(last).inSeconds;
        if (gap > 4) {
          print('[CompassService] iOS stall detected (no compass events for ${gap}s); restarting service');
          // Restart the service to reinitialize streams cleanly
          await stop();
          await start(options);
        }
      });
      return;
    }

    _accSub = accelerometerEvents.listen((a) {
      _lastAccel = a;
      _lastUpdate = DateTime.now();
      _accCount++;
      if (_accCount <= 3) {
        print('[CompassService] accel: x=${a.x.toStringAsFixed(2)}, y=${a.y.toStringAsFixed(2)}, z=${a.z.toStringAsFixed(2)}');
      }
    });

    _magSub = magnetometerEvents.listen((m) {
      _lastUpdate = DateTime.now();
      _magCount++;
      if (_magCount <= 3) {
        print('[CompassService] mag: x=${m.x.toStringAsFixed(2)}, y=${m.y.toStringAsFixed(2)}, z=${m.z.toStringAsFixed(2)}');
      }
      double mx = m.x, my = m.y, mz = m.z;
      double heading;

      if (_lastAccel != null) {
        double ax = _lastAccel!.x, ay = _lastAccel!.y, az = _lastAccel!.z;
        // Normalize
        double gNorm = math.sqrt(ax*ax + ay*ay + az*az);
        if (gNorm > 0) { ax /= gNorm; ay /= gNorm; az /= gNorm; }
        double mNorm = math.sqrt(mx*mx + my*my + mz*mz);
        if (mNorm > 0) { mx /= mNorm; my /= mNorm; mz /= mNorm; }

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

        // Compute headings referenced to device axes.
        // Alternative formulations:
        //  - yawY = atan2(Ey, Ny)
        //  - yawX = atan2(Ex, Nx)
        //  - azimuth = atan2(Nx, Ny)  // projects North onto device x/y
        final yawY = math.atan2(Ey, Ny) * (180 / math.pi);
        final yawX = math.atan2(Ex, Nx) * (180 / math.pi);
        final azimuth = math.atan2(Nx, Ny) * (180 / math.pi);

        // Prefer Y-axis heading; if degenerate (no sensor signal), fallback to raw magnetometer
        if ((Ex.abs() + Ey.abs() + Nx.abs() + Ny.abs()) < 1e-6) {
          // Degenerate tilt-comp vectors; fallback to raw 2D heading
          print('[CompassService] Degenerate tilt-comp vectors; using raw magnetometer');
          heading = math.atan2(my, mx) * (180 / math.pi);
        } else {
          // Use Y-axis based heading for Android (consistent with previous behavior)
          final yawY = math.atan2(Ey, Ny) * (180 / math.pi);
          heading = yawY;
        }
      } else {
        heading = math.atan2(my, mx) * (180 / math.pi);
      }

      // Normalize 0..360 (clockwise, 0 = North)
      heading = (heading + 360) % 360;

      // Apply declination for True North if requested
      final decl = (_declinationDeg ?? 0.0);
      if (options.useTrueNorth) {
        heading = (heading + decl) % 360;
      }

      // Apply calibration offset
      heading = (heading + calibrationOffset) % 360;

      if (first) {
        smoothedHeading = heading;
        first = false;
      }

      // Wrap-aware exponential smoothing
      double alpha = 0.15;
      double diff = heading - smoothedHeading;
      if (diff > 180) diff -= 360; else if (diff < -180) diff += 360;
      smoothedHeading = smoothedHeading + diff * alpha;
      if (smoothedHeading < 0) smoothedHeading += 360; else if (smoothedHeading >= 360) smoothedHeading -= 360;

      if (!_headingController.isClosed) {
        _headingController.add(smoothedHeading);
        // Lightweight debug to confirm stream activity
        if (first) {
          print('[CompassService] First heading: ${smoothedHeading.toStringAsFixed(1)}°');
        }
        if ((_magCount % 30) == 0) {
          print('[CompassService] heading tick: ${smoothedHeading.toStringAsFixed(1)}° (events mag=$_magCount acc=$_accCount)');
        }
      }
    });

    // Watchdog: detect stalled streams (iOS permission or sensor issues)
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_running) return;
      final last = _lastUpdate;
      if (last == null) {
        print('[CompassService] No sensor updates yet…');
        return;
      }
      final gap = DateTime.now().difference(last).inSeconds;
      if (gap > 4) {
        print('[CompassService] Warning: no sensor updates for ${gap}s');
      }
    });
  }

  Future<void> stop() async {
    _running = false;
    await _magSub?.cancel();
    await _accSub?.cancel();
    await _iosCompassSub?.cancel();
    _magSub = null;
    _accSub = null;
    _iosCompassSub = null;
    _watchdog?.cancel();
    _watchdog = null;
  }
}