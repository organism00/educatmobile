// Create a new file: services/student_discount_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/discount_model.dart'; // You'll need to create this model

class DiscountProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  bool isLoading = false;
  String? errorMessage;
  List<DiscountModel> discounts = [];
  bool hasDiscounts = false;
  int discountCount = 0;

  /// Fetch discounts for a student
  Future<void> fetchStudentDiscounts({
    required String token,
    required String studentId,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _apiService.getStudentDiscounts(
        token: token,
        studentId: studentId,
      );

      if (result['success']) {
        // Parse discounts if available
        final discountData = result['discounts'] ?? [];
        discounts = discountData.map((data) {
          return DiscountModel.fromJson(data);
        }).toList();

        hasDiscounts = result['hasDiscounts'] ?? false;
        discountCount = result['discountCount'] ?? 0;
        errorMessage = null;

        print('✅ Successfully fetched ${discounts.length} discounts');
      } else {
        errorMessage = result['message'] ?? 'Failed to fetch discounts';
        discounts = [];
        hasDiscounts = false;
        discountCount = 0;
        print('❌ Error fetching discounts: $errorMessage');
      }
    } catch (e) {
      errorMessage = 'Unexpected error: $e';
      discounts = [];
      hasDiscounts = false;
      discountCount = 0;
      print('❌ Exception fetching discounts: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Check if a specific type of discount exists
  bool hasDiscountType(String discountType) {
    return discounts.any((discount) =>
    discount.discountType?.toLowerCase() == discountType.toLowerCase()
    );
  }

  /// Get total discount amount
  double getTotalDiscountAmount() {
    return discounts.fold(
        0.0,
            (total, discount) => total + (discount.amount ?? 0.0)
    );
  }

  /// Get discount by type
  List<DiscountModel> getDiscountsByType(String discountType) {
    return discounts.where((discount) =>
    discount.discountType?.toLowerCase() == discountType.toLowerCase()
    ).toList();
  }
}