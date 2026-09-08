// services/fee_provider.dart

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

  // ==================== OTHER FEES ====================
  List<Map<String, dynamic>> otherFees = [];
  double totalOtherFees = 0.0;
  bool isFetchingOtherFees = false;

  /// Calculate discounted fee
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

  // ==================== OTHER FEES METHODS ====================

  /// Fetch other fees for a classroom
  Future<bool> fetchOtherFees({
    required String token,
    required String classroomId,
    bool activeOnly = true,
  }) async {
    isFetchingOtherFees = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _apiService.getOtherFeesByClassroom(
        token: token,
        classroomId: classroomId,
        activeOnly: activeOnly,
      );

      if (result['success']) {
        otherFees = List<Map<String, dynamic>>.from(result['fees']);
        totalOtherFees = result['totalAmount'] ?? 0.0;
        errorMessage = null;

        print('✅ Fetched ${otherFees.length} other fees');
        print('💰 Total amount: ₦$totalOtherFees');

        isFetchingOtherFees = false;
        notifyListeners();
        return true;
      } else {
        errorMessage = result['message'] ?? 'Failed to fetch fees';
        otherFees = [];
        totalOtherFees = 0.0;
        isFetchingOtherFees = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      errorMessage = 'Unexpected error: $e';
      otherFees = [];
      totalOtherFees = 0.0;
      isFetchingOtherFees = false;
      notifyListeners();
      return false;
    }
  }

  /// Get total mandatory fees
  double getTotalMandatoryFees() {
    return otherFees
        .where((fee) => fee['isMandatory'] == true)
        .fold(0.0, (sum, fee) => sum + (fee['amount'] as double));
  }

  /// Get total optional fees
  double getTotalOptionalFees() {
    return otherFees
        .where((fee) => fee['isMandatory'] == false)
        .fold(0.0, (sum, fee) => sum + (fee['amount'] as double));
  }

  /// Get mandatory fees only
  List<Map<String, dynamic>> getMandatoryFees() {
    return otherFees.where((fee) => fee['isMandatory'] == true).toList();
  }

  /// Get optional fees only
  List<Map<String, dynamic>> getOptionalFees() {
    return otherFees.where((fee) => fee['isMandatory'] == false).toList();
  }

  /// Get fee by ID
  Map<String, dynamic>? getFeeById(String feeId) {
    try {
      return otherFees.firstWhere((fee) => fee['id'] == feeId);
    } catch (e) {
      return null;
    }
  }

  /// Check if there are any mandatory fees
  bool get hasMandatoryFees {
    return getMandatoryFees().isNotEmpty;
  }

  /// Check if there are any optional fees
  bool get hasOptionalFees {
    return getOptionalFees().isNotEmpty;
  }

  // ==================== EXISTING METHODS ====================

  /// Mark payment as successful
  void setPaymentSuccess(bool success) {
    paymentSuccess = success;
    notifyListeners();
  }

  /// Reset all state
  void reset() {
    isLoading = false;
    isCalculatingDiscount = false;
    isProcessingPayment = false;
    isFetchingOtherFees = false;
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
    otherFees = [];
    totalOtherFees = 0.0;
    notifyListeners();
  }

  /// Reset only other fees
  void resetOtherFees() {
    otherFees = [];
    totalOtherFees = 0.0;
    isFetchingOtherFees = false;
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

  /// Get formatted total other fees
  String getTotalOtherFeesText() {
    return '₦${totalOtherFees.toStringAsFixed(2)}';
  }

  /// Get summary of other fees
  String getOtherFeesSummary() {
    if (otherFees.isEmpty) return 'No additional fees';
    return '${otherFees.length} fee${otherFees.length > 1 ? 's' : ''} (Total: ₦${totalOtherFees.toStringAsFixed(2)})';
  }
}