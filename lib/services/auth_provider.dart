import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../utils/jwt_decoder.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();
  late SessionManager _sessionManager;

  UserModel? _currentUser;
  String? _token;
  bool _isLoading = false;
  String? _errorMessage;

  UserModel? get currentUser => _currentUser;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _currentUser != null && _token != null;

  AuthProvider() {
    _initSession();
  }

  Future<void> _initSession() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionManager = SessionManager(prefs);

    if (_sessionManager.isLoggedIn()) {
      _token = _sessionManager.getToken();
      _currentUser = _sessionManager.getUser();

      if (_token != null && JwtDecoder.isTokenExpired(_token!)) {
        await logout();
      } else if (_currentUser != null && _currentUser!.isGuardian) {
        // Fetch updated guardian details
        await _fetchGuardianDetails();
      }
    }
    notifyListeners();
  }

  Future<void> _fetchGuardianDetails() async {
    if (_token == null || _currentUser == null) return;

    final result = await _apiService.getGuardianById(
      token: _token!,
      guardianId: _currentUser!.id,
    );

    if (result['success'] && result['data'] != null) {
      final updatedUser = UserModel.fromGuardianData(result['data'], _currentUser!);
      _currentUser = updatedUser;
      await _sessionManager.saveSession(_token!, _currentUser!);
      notifyListeners();
    }
  }

  Future<bool> login({
    required String schoolRegistrationNumber,
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _apiService.login(
      schoolRegistrationNumber: schoolRegistrationNumber,
      email: email,
      password: password,
    );

    if (result['success']) {
      _token = result['token'];
      _currentUser = result['user'];

      // If user is guardian, fetch additional details
      if (_currentUser!.isGuardian) {
        final guardianResult = await _apiService.getGuardianById(
          token: _token!,
          guardianId: _currentUser!.id,
        );

        if (guardianResult['success'] && guardianResult['data'] != null) {
          _currentUser = UserModel.fromGuardianData(guardianResult['data'], _currentUser!);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      _sessionManager = SessionManager(prefs);
      await _sessionManager.saveSession(_token!, _currentUser!);
      _isLoading = false;
      notifyListeners();
      return true;
    } else {
      _errorMessage = result['message'];
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionManager = SessionManager(prefs);
    await _sessionManager.clearSession();
    _token = null;
    _currentUser = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}