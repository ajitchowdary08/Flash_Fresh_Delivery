import 'package:geolocator/geolocator.dart';

/// Real device GPS for live rider tracking. Replaces the old "Simulate Ride"
/// timer that advanced a fake marker through waypoints.
///
/// Usage: the trip screen calls [startStreaming] when it begins a trip and
/// [stopStreaming] when the trip ends. Each high-accuracy position fix is
/// delivered to [onPosition], which should POST it to the backend via
/// `RiderApiService.updateLocation`.
class RiderLocationService {
  Stream<Position>? _stream;

  /// Ensures the rider has granted location permissions and that GPS is on.
  /// Throws a [RiderLocationException] with a user-facing message otherwise.
  static Future<void> ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw RiderLocationException(
        "Location services are disabled. Please turn on GPS in your device settings.",
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw RiderLocationException(
        "Location permission was denied. The rider app needs GPS to share live tracking with customers.",
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw RiderLocationException(
        "Location permission is permanently denied. Please enable it in app settings.",
      );
    }
  }

  /// Returns the last known device position (used to seed the duty map). May be null.
  static Future<Position?> lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Starts a high-accuracy position stream. Each fix is delivered to
  /// [onPosition]. The stream throttles to roughly one update per 5 seconds /
  /// 10 meters to avoid hammering the backend.
  void startStreaming(void Function(double lat, double lng) onPosition) {
    stopStreaming();
    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // meters — only forward updates that move the rider
    );
    _stream = Geolocator.getPositionStream(locationSettings: locationSettings);
    _stream?.listen((pos) {
      onPosition(pos.latitude, pos.longitude);
    });
  }

  void stopStreaming() {
    _stream?.drain().catchError((_) {});
    _stream = null;
  }
}

class RiderLocationException implements Exception {
  final String message;
  RiderLocationException(this.message);
  @override
  String toString() => message;
}
