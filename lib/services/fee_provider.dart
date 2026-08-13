// Update your fee_provider.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import '../models/user_model.dart';

class FeeProvider extends ChangeNotifier {
  final ApiService _apiService = ApiService();

  bool isLoading = false;
  bool isCalculatingDiscount = false;
  bool isProcessingPayment = false;
  String? errorMessage;

  // Discount calculation results
  double originalFee = 0;
  double discountedFee = 0;
  double discountAmount = 0;
  bool hasDiscount = false;
  Map<String, dynamic>? discountDetails;

  // Payment results
  String? checkoutUrl;
  String? paymentReference;
  String? paymentGateway;
  bool paymentSuccess = false;

  /// Calculate discounted fee
  // In fee_provider.dart

  /// Calculate discounted fee
  // In fee_provider.dart, make sure you're also fetching the discount

  Future<bool> calculateDiscountedFee({
    required String token,
    required String studentId,
    required double originalFee,
  }) async {
    isCalculatingDiscount = true;
    errorMessage = null;
    notifyListeners();

    try {
      print('🔍 Calculating discount for student: $studentId');
      print('💰 Original Fee: $originalFee');

      // First, fetch the student's discount
      final discountResult = await _apiService.getStudentDiscounts(
        token: token,
        studentId: studentId,
      );

      String sessionId = '';
      String termId = '';
      bool hasActiveDiscount = false;
      double discountAmount = 0;

      if (discountResult['success'] && discountResult['hasDiscounts']) {
        final discounts = discountResult['discounts'] as List;

        for (var discount in discounts) {
          final isActive = discount['isActive'] == true;
          if (isActive) {
            sessionId = discount['sessionId']?.toString() ?? '';
            termId = discount['termId']?.toString() ?? '';
            discountAmount = (discount['discountAmount'] ?? 0).toDouble();
            hasActiveDiscount = true;

            print('✅ Found active discount:');
            print('   Discount Amount: ₦$discountAmount');
            print('   SessionId: $sessionId');
            print('   TermId: $termId');
            break;
          }
        }
      }

      if (!hasActiveDiscount || sessionId.isEmpty || termId.isEmpty) {
        print('ℹ️ No active discount found for student');
        this.originalFee = originalFee;
        this.discountedFee = originalFee;
        this.discountAmount = 0;
        this.hasDiscount = false;
        isCalculatingDiscount = false;
        notifyListeners();
        return true;
      }

      // Calculate the discounted fee
      final result = await _apiService.getDiscountedFee(
        token: token,
        studentId: studentId,
        originalFee: originalFee,
        sessionId: sessionId,
        termId: termId,
      );

      if (result['success']) {
        this.originalFee = result['originalFee'] ?? originalFee;
        this.discountedFee = result['discountedFee'] ?? originalFee;
        this.discountAmount = result['discountAmount'] ?? 0;
        this.hasDiscount = result['hasDiscount'] ?? false;

        print('✅ Discount calculated:');
        print('   Original: ₦$originalFee');
        print('   Discounted: ₦${this.discountedFee}');
        print('   Saved: ₦${this.discountAmount}');

        isCalculatingDiscount = false;
        notifyListeners();
        return true;
      } else {
        this.originalFee = originalFee;
        this.discountedFee = originalFee;
        this.discountAmount = 0;
        this.hasDiscount = false;
        errorMessage = result['message'] ?? 'Failed to calculate discount';
        isCalculatingDiscount = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      print('❌ Error calculating discount: $e');
      this.originalFee = originalFee;
      this.discountedFee = originalFee;
      this.discountAmount = 0;
      this.hasDiscount = false;
      errorMessage = 'Error calculating discount: $e';
      isCalculatingDiscount = false;
      notifyListeners();
      return false;
    }
  }
  /// Initiate payment
  Future<bool> initiatePayment({
    required String token,
    required String studentId,
    required String schoolId,
    required String guardianId,
    required double amount,
    required String customerEmail,
    required String gateway,
    required String redirectUrl,
    required String callbackUrl,
    required String classroomId,
  }) async {
    isProcessingPayment = true;
    errorMessage = null;
    paymentSuccess = false;
    notifyListeners();

    try {
      final result = await _apiService.initiateSchoolFeePayment(
        token: token,
        studentId: studentId,
        schoolId: schoolId,
        guardianId: guardianId,
        amount: amount,
        customerEmail: customerEmail,
        gateway: gateway,
        redirectUrl: redirectUrl,
        callbackUrl: callbackUrl,
        classroomId: classroomId,
      );

      if (result['success']) {
        checkoutUrl = result['checkoutUrl'];
        paymentReference = result['reference'];
        paymentGateway = result['gateway'];
        errorMessage = null;

        print('✅ Payment initiated: $paymentReference');
        isProcessingPayment = false;
        notifyListeners();
        return true;
      } else {
        errorMessage = result['message'] ?? 'Failed to initiate payment';
        isProcessingPayment = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Error initiating payment: $e';
      isProcessingPayment = false;
      notifyListeners();
      return false;
    }
  }

  /// Mark payment as successful
  void setPaymentSuccess(bool success) {
    paymentSuccess = success;
    notifyListeners();
  }

  /// Reset state
  void reset() {
    isLoading = false;
    isCalculatingDiscount = false;
    isProcessingPayment = false;
    errorMessage = null;
    originalFee = 0;
    discountedFee = 0;
    discountAmount = 0;
    hasDiscount = false;
    discountDetails = null;
    checkoutUrl = null;
    paymentReference = null;
    paymentGateway = null;
    paymentSuccess = false;
    notifyListeners();
  }

  /// Get formatted discount text
  String getDiscountText() {
    if (!hasDiscount) return 'No discount available';
    return 'You save ₦${discountAmount.toStringAsFixed(2)}';
  }

  /// Get formatted original fee
  String getOriginalFeeText() {
    return '₦${originalFee.toStringAsFixed(2)}';
  }

  /// Get formatted discounted fee
  String getDiscountedFeeText() {
    return '₦${discountedFee.toStringAsFixed(2)}';
  }
}