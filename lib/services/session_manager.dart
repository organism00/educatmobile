import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/user_model.dart';

class SessionManager {
  static const String _keyToken = 'auth_token';
  static const String _keyUser = 'user_data';
  static const String _keyIsLoggedIn = 'is_logged_in';
  static const String _keySchoolRegNo = 'saved_school_reg_no';
  static const String _keyEmail = 'saved_email';
  static const String _keyPassword = 'saved_password';
  static const String _keyRememberSchool = 'remember_school';
  static const String _keyRememberMe = 'remember_me';

  final SharedPreferences _prefs;

  SessionManager(this._prefs);

  // Save user session
  Future<void> saveSession(String token, UserModel user) async {
    await _prefs.setString(_keyToken, token);
    await _prefs.setString(_keyUser, jsonEncode(user.toJson()));
    await _prefs.setBool(_keyIsLoggedIn, true);
  }

  // Get stored token
  String? getToken() {
    return _prefs.getString(_keyToken);
  }

  // Get stored user
  UserModel? getUser() {
    final userJson = _prefs.getString(_keyUser);
    if (userJson != null) {
      try {
        final userMap = jsonDecode(userJson);
        return UserModel.fromJson(userMap);
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  // Check if user is logged in
  bool isLoggedIn() {
    return _prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  // Clear session (logout)
  Future<void> clearSession() async {
    final rememberSchool = _prefs.getBool(_keyRememberSchool) ?? false;
    final rememberMe = _prefs.getBool(_keyRememberMe) ?? false;

    await _prefs.remove(_keyToken);
    await _prefs.remove(_keyUser);
    await _prefs.setBool(_keyIsLoggedIn, false);

    // If remember me is not checked, clear saved credentials
    if (!rememberMe) {
      await _prefs.remove(_keyEmail);
      await _prefs.remove(_keyPassword);
      await _prefs.setBool(_keyRememberMe, false);
    }

    // If remember school is not checked, clear saved school
    if (!rememberSchool) {
      await _prefs.remove(_keySchoolRegNo);
      await _prefs.setBool(_keyRememberSchool, false);
    }
  }

  // Save School Registration Number
  Future<void> saveSchoolRegNo(String schoolRegNo, {bool remember = true}) async {
    if (remember && schoolRegNo.isNotEmpty) {
      await _prefs.setString(_keySchoolRegNo, schoolRegNo);
      await _prefs.setBool(_keyRememberSchool, true);
    } else {
      await _prefs.remove(_keySchoolRegNo);
      await _prefs.setBool(_keyRememberSchool, false);
    }
  }

  // Get saved School Registration Number
  String? getSavedSchoolRegNo() {
    return _prefs.getString(_keySchoolRegNo);
  }

  // Save Email
  Future<void> saveEmail(String email, {bool remember = true}) async {
    if (remember && email.isNotEmpty) {
      await _prefs.setString(_keyEmail, email);
    } else {
      await _prefs.remove(_keyEmail);
    }
  }

  // Get saved Email
  String? getSavedEmail() {
    return _prefs.getString(_keyEmail);
  }

  // Save Password (Note: In production, consider encrypting this)
  Future<void> savePassword(String password, {bool remember = true}) async {
    if (remember && password.isNotEmpty) {
      // For better security, you can encrypt the password here
      await _prefs.setString(_keyPassword, password);
    } else {
      await _prefs.remove(_keyPassword);
    }
  }

  // Get saved Password
  String? getSavedPassword() {
    return _prefs.getString(_keyPassword);
  }

  // Save Remember Me preference
  Future<void> setRememberMe(bool remember) async {
    await _prefs.setBool(_keyRememberMe, remember);
  }

  // Get Remember Me preference
  bool getRememberMe() {
    return _prefs.getBool(_keyRememberMe) ?? false;
  }

  // Check if school should be remembered
  bool getRememberSchool() {
    return _prefs.getBool(_keyRememberSchool) ?? false;
  }

  // Clear all saved credentials
  Future<void> clearSavedCredentials() async {
    await _prefs.remove(_keySchoolRegNo);
    await _prefs.remove(_keyEmail);
    await _prefs.remove(_keyPassword);
    await _prefs.setBool(_keyRememberSchool, false);
    await _prefs.setBool(_keyRememberMe, false);
  }
}