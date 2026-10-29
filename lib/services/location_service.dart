import 'dart:async';

import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Outcome of a one-shot location request. Exactly one of [position] or
/// [error] is non-null.
class LocationResult {
  const LocationResult.success(LatLng this.position) : error = null;
  const LocationResult.failure(String this.error) : position = null;

  final LatLng? position;
  final String? error;
}

/// One-shot foreground location lookup (no tracking, no background updates).
class LocationService {
  LocationService._();

  static LocationService instance = LocationService._();

  static const timeout = Duration(seconds: 15);

  Future<LocationResult> currentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failure(
            'Location services are turned off or unavailable on this device.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failure('Location permission was denied.');
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failure(
            'Location access is blocked. Enable it in your browser or device '
            'settings to centre the map on your position.');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return LocationResult.success(LatLng(pos.latitude, pos.longitude));
    } on TimeoutException {
      return const LocationResult.failure('Timed out while getting your location.');
    } on LocationServiceDisabledException {
      return const LocationResult.failure(
          'Location services are turned off or unavailable on this device.');
    } on PermissionDeniedException {
      return const LocationResult.failure('Location permission was denied.');
    } on PermissionRequestInProgressException {
      return const LocationResult.failure(
          'A location permission request is already in progress.');
    } on MissingPluginException {
      return const LocationResult.failure(
          'Location is not supported on this platform.');
    } on UnsupportedError {
      return const LocationResult.failure(
          'Location is not supported on this platform.');
    } catch (_) {
      return const LocationResult.failure('Could not get your location.');
    }
  }
}
