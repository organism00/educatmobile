import 'package:flutter/material.dart';
import '../models/loan_application.dart';
import 'api_service.dart';

class LoanProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  List<LoanApplication> _applications = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<LoanApplication> get applications => _applications;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Get active/in-progress applications (status < 8 and not failed/rejected)
  List<LoanApplication> get activeApplications {
    return _applications.where((app) =>
    app.status < 8 && app.status != 9 && app.status != 5
    ).toList();
  }

  // Get completed applications (disbursed or approved)
  List<LoanApplication> get completedApplications {
    return _applications.where((app) =>
    app.status == 8 || app.status == 7
    ).toList();
  }

  // Get failed/rejected applications
  List<LoanApplication> get failedApplications {
    return _applications.where((app) =>
    app.status == 9 || app.status == 5
    ).toList();
  }

  // Get all applications (sorted by updatedAt descending)
  List<LoanApplication> get sortedApplications {
    final sorted = List<LoanApplication>.from(_applications);
    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  Future<bool> fetchApplications({
    required String token,
    required String guardianId,
  }) async {
    _setLoading(true);
    _errorMessage = null;

    try {
      final result = await _apiService.getGuardianApplications(
        token: token,
        guardianId: guardianId,
      );

      if (result['success']) {
        _applications = result['applications'] ?? [];
        _setLoading(false);
        return true;
      } else {
        _errorMessage = result['message'] ?? 'Failed to fetch applications';
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _errorMessage = 'Error: ${e.toString()}';
      _setLoading(false);
      return false;
    }
  }

  // Get a single application by ID
  LoanApplication? getApplicationById(String id) {
    try {
      return _applications.firstWhere((app) => app.id == id);
    } catch (e) {
      return null;
    }
  }

  // Add or update an application
  void upsertApplication(LoanApplication application) {
    final index = _applications.indexWhere((app) => app.id == application.id);
    if (index != -1) {
      _applications[index] = application;
    } else {
      _applications.add(application);
    }
    notifyListeners();
  }

  // Remove an application
  void removeApplication(String id) {
    _applications.removeWhere((app) => app.id == id);
    notifyListeners();
  }

  // Clear all data
  void clear() {
    _applications = [];
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }
}