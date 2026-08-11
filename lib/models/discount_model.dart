// Create a new file: models/discount_model.dart
import 'package:flutter/material.dart';

class DiscountModel {
  final String? id;
  final String? studentId;
  final String? schoolId;
  final String? discountType;
  final double? percentage;
  final double? amount;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool? isActive;
  final String? createdBy;
  final DateTime? createdAt;

  DiscountModel({
    this.id,
    this.studentId,
    this.schoolId,
    this.discountType,
    this.percentage,
    this.amount,
    this.description,
    this.startDate,
    this.endDate,
    this.isActive,
    this.createdBy,
    this.createdAt,
  });

  factory DiscountModel.fromJson(Map<String, dynamic> json) {
    return DiscountModel(
      id: json['id']?.toString(),
      studentId: json['studentId']?.toString(),
      schoolId: json['schoolId']?.toString(),
      discountType: json['discountType']?.toString(),
      percentage: (json['percentage'] as num?)?.toDouble(),
      amount: (json['amount'] as num?)?.toDouble(),
      description: json['description']?.toString(),
      startDate: json['startDate'] != null
          ? DateTime.tryParse(json['startDate'].toString())
          : null,
      endDate: json['endDate'] != null
          ? DateTime.tryParse(json['endDate'].toString())
          : null,
      isActive: json['isActive'] as bool?,
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
      'schoolId': schoolId,
      'discountType': discountType,
      'percentage': percentage,
      'amount': amount,
      'description': description,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'isActive': isActive,
      'createdBy': createdBy,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  // Helper getters
  String get formattedPercentage => percentage != null ? '${percentage!.toStringAsFixed(0)}%' : 'N/A';

  String get formattedAmount => amount != null ? '₦${amount!.toStringAsFixed(2)}' : '₦0.00';

  bool get isValid => isActive == true &&
      (endDate == null || endDate!.isAfter(DateTime.now()));

  String get statusText => isValid ? 'Active' : 'Expired';

  Color get statusColor => isValid ? Colors.green : Colors.grey;
}