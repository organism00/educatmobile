// models/discount_model.dart

import 'package:flutter/material.dart';

class DiscountModel {
  final String? id;
  final String? studentId;
  final String? studentName;
  final String? className;
  final String? schoolId;
  final double? amount;
  final String? reason;
  final bool? isActive;
  final String? sessionId;
  final String? termId;
  final String? createdBy;
  final DateTime? createdAt;

  DiscountModel({
    this.id,
    this.studentId,
    this.studentName,
    this.className,
    this.schoolId,
    this.amount,
    this.reason,
    this.isActive,
    this.sessionId,
    this.termId,
    this.createdBy,
    this.createdAt,
  });

  factory DiscountModel.fromJson(Map<String, dynamic> json) {
    return DiscountModel(
      id: json['discountId']?.toString() ?? json['id']?.toString(),
      studentId: json['studentId']?.toString(),
      studentName: json['studentName']?.toString(),
      className: json['className']?.toString(),
      schoolId: json['schoolId']?.toString(),
      amount: (json['discountAmount'] ?? json['amount'] ?? 0).toDouble(),
      reason: json['reason']?.toString() ?? json['description']?.toString(),
      isActive: json['isActive'] ?? json['active'] ?? true,
      sessionId: json['sessionId']?.toString(),
      termId: json['termId']?.toString(),
      createdBy: json['createdBy']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'studentId': studentId,
      'studentName': studentName,
      'className': className,
      'schoolId': schoolId,
      'amount': amount,
      'reason': reason,
      'isActive': isActive,
      'sessionId': sessionId,
      'termId': termId,
      'createdBy': createdBy,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  // Helper getters
  String get formattedAmount => amount != null ? '₦${amount!.toStringAsFixed(2)}' : '₦0.00';

  bool get isValid => isActive == true;

  String get statusText => isValid ? 'Active' : 'Expired';

  Color get statusColor => isValid ? Colors.green : Colors.grey;

  String get discountType => reason ?? 'Discount';
  String get description => reason ?? '';

  // Since there's no percentage, we calculate it if we have the original fee
  // This will be set separately when we have the original fee context
  double? getPercentage(double? originalFee) {
    if (originalFee == null || originalFee <= 0 || amount == null) return null;
    return (amount! / originalFee) * 100;
  }
}