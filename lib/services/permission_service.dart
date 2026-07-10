// services/permission_service.dart
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

class PermissionService {
  // Request all required permissions
  static Future<bool> requestAllPermissions() async {
    final permissions = await [
      Permission.camera,
      Permission.location,
    ].request();

    final cameraGranted = permissions[Permission.camera] == PermissionStatus.granted;
    final locationGranted = permissions[Permission.location] == PermissionStatus.granted;

    return cameraGranted && locationGranted;
  }

  // Request camera permission
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  // Request location permission
  static Future<bool> requestLocationPermission() async {
    final status = await Permission.location.request();
    return status.isGranted;
  }

  // Check if all permissions are granted
  static Future<bool> checkAllPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final locationStatus = await Permission.location.status;
    return cameraStatus.isGranted && locationStatus.isGranted;
  }

  // Check if camera permission is granted
  static Future<bool> hasCameraPermission() async {
    final status = await Permission.camera.status;
    return status.isGranted;
  }

  // Check if location permission is granted
  static Future<bool> hasLocationPermission() async {
    final status = await Permission.location.status;
    return status.isGranted;
  }

  // Open app settings (if permission denied forever)
  static Future<void> openAppSettings() async {
    await openAppSettings();
  }
}