// services/discount_provider.dart

import 'package:flutter/material.dart';
import '../models/discount_model.dart';
import 'api_service.dart';

class DiscountProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  bool isLoading = false;
  String? errorMessage;

  // Store discounts by student ID
  Map<String, List<DiscountModel>> _studentDiscounts = {};

  // Current selected student
  String? _currentStudentId;

  // Get discounts for a specific student
  List<DiscountModel> getDiscountsForStudent(String studentId) {
    print('🔍 Getting discounts for student: $studentId');
    final discounts = _studentDiscounts[studentId] ?? [];
    print('   Found ${discounts.length} discounts');
    return discounts;
  }

  // Get all discounts (for display in the discount screen)
  List<DiscountModel> get allDiscounts {
    List<DiscountModel> all = [];
    _studentDiscounts.forEach((studentId, discounts) {
      all.addAll(discounts);
    });
    return all;
  }

  bool get hasDiscounts => allDiscounts.isNotEmpty;
  int get discountCount => allDiscounts.length;

  /// Fetch discounts for a student
  Future<bool> fetchStudentDiscounts({
    required String token,
    required String studentId,
  }) async {
    print('🔍 fetchStudentDiscounts called for: $studentId');

    // Skip if already loading
    if (isLoading) {
      print('⚠️ Already loading, skipping');
      return false;
    }

    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      print('📤 Calling API: getStudentDiscounts for $studentId');

      final result = await _apiService.getStudentDiscounts(
        token: token,
        studentId: studentId,
      );

      print('📥 API Response Success: ${result['success']}');
      print('📥 Has Discounts: ${result['hasDiscounts']}');
      print('📥 Discount Count: ${result['discountCount']}');

      if (result['success']) {
        final discountData = result['discounts'] ?? [];
        print('📦 Raw discount data type: ${discountData.runtimeType}');
        print('📦 Raw discount data length: ${discountData.length}');

        // Explicitly cast and parse each discount
        List<DiscountModel> newDiscounts = [];

        for (var data in discountData) {
          print('   Parsing discount: ${data['discountId']} - ₦${data['discountAmount']}');
          try {
            final discount = DiscountModel.fromJson(data as Map<String, dynamic>);
            newDiscounts.add(discount);
          } catch (e) {
            print('   ❌ Error parsing discount: $e');
            print('   Raw data: $data');
          }
        }

        // Store discounts for this student
        _studentDiscounts[studentId] = newDiscounts;
        _currentStudentId = studentId;
        errorMessage = null;

        print('✅ Successfully fetched ${newDiscounts.length} discounts for student $studentId');
        for (var discount in newDiscounts) {
          print('   ${discount.discountType}: ₦${discount.amount} (${discount.isValid ? 'Active' : 'Expired'})');
        }

        isLoading = false;
        notifyListeners();
        return true;
      } else {
        errorMessage = result['message'] ?? 'Failed to fetch discounts';
        _studentDiscounts[studentId] = [];
        isLoading = false;
        notifyListeners();
        print('❌ Error fetching discounts: $errorMessage');
        return false;
      }
    } catch (e) {
      errorMessage = 'Unexpected error: $e';
      _studentDiscounts[studentId] = [];
      isLoading = false;
      notifyListeners();
      print('❌ Exception fetching discounts: $e');
      return false;
    }
  }

  /// Fetch discounts for all pupils
  Future<void> fetchDiscountsForAllPupils({
    required String token,
    required List<Map<String, dynamic>> pupils,
  }) async {
    if (pupils.isEmpty) {
      print('ℹ️ No pupils to fetch discounts for');
      return;
    }

    print('🔍 Fetching discounts for ${pupils.length} pupils');

    List<Future> futures = [];
    for (var pupil in pupils) {
      final studentId = pupil['id']?.toString();
      if (studentId != null && studentId.isNotEmpty) {
        futures.add(
            fetchStudentDiscounts(
              token: token,
              studentId: studentId,
            )
        );
      }
    }

    await Future.wait(futures);
    print('✅ All discounts fetched');
  }

  /// Clear discounts
  void clearDiscounts() {
    print('🧹 Clearing all discounts');
    _studentDiscounts.clear();
    _currentStudentId = null;
    notifyListeners();
  }
}