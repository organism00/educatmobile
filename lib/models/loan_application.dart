import 'package:flutter/material.dart';

import '../utils/app_colors.dart';

class LoanApplication {
  final String id;
  final String guardianId;
  final String? studentId;
  final String? creditAssessmentId;
  final String? edubanclLoanId;
  final double? requestedAmount;
  final double? eligibleAmount;
  final int status;
  final String statusLabel;
  final String? edubanclStatusMessage;
  final String? mandateAuthorizationUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  LoanApplication({
    required this.id,
    required this.guardianId,
    this.studentId,
    this.creditAssessmentId,
    this.edubanclLoanId,
    this.requestedAmount,
    this.eligibleAmount,
    required this.status,
    required this.statusLabel,
    this.edubanclStatusMessage,
    this.mandateAuthorizationUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LoanApplication.fromJson(Map<String, dynamic> json) {
    return LoanApplication(
      id: json['id'] ?? '',
      guardianId: json['guardianId'] ?? '',
      studentId: json['studentId'],
      creditAssessmentId: json['creditAssessmentId'],
      edubanclLoanId: json['edubanclLoanId'],
      requestedAmount: (json['requestedAmount'] as num?)?.toDouble(),
      eligibleAmount: (json['eligibleAmount'] as num?)?.toDouble(),
      status: json['status'] ?? 0,
      statusLabel: json['statusLabel'] ?? 'Initiated',
      edubanclStatusMessage: json['edubanclStatusMessage'],
      mandateAuthorizationUrl: json['mandateAuthorizationUrl'],
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updatedAt'] ?? DateTime.now().toIso8601String()),
    );
  }

  // Status helper methods
  bool get isComplete => status == 8; // Disbursed
  bool get isPending => status < 8 && status != 9 && status != 5;
  bool get isRejected => status == 9;
  bool get isFailed => status == 5;
  bool get needsCreditAssessment => status < 4;
  bool get needsLoanApplication => status == 4;
  bool get needsTermsAcceptance => status == 6;
  bool get needsMandateSetup => status == 11;
  bool get isProcessing => status == 12;
  bool get isApproved => status == 7;
  bool get isDisbursed => status == 8;

  String get statusDisplay {
    switch (status) {
      case 0: return 'Initiated';
      case 1: return 'BVN Validated';
      case 2: return 'Statement Uploaded';
      case 3: return 'Assessment Pending';
      case 4: return 'Assessment Complete ✅';
      case 5: return 'Assessment Failed ❌';
      case 6: return 'Submitted';
      case 7: return 'Approved ✅';
      case 8: return 'Disbursed 🎉';
      case 9: return 'Rejected ❌';
      case 10: return 'Pending Approval';
      case 11: return 'Terms Accepted';
      case 12: return 'Mandate Setup';
      default: return 'Unknown';
    }
  }

  Color get statusColor {
    switch (status) {
      case 4:
      case 7:
      case 8:
        return AppColors.success;
      case 5:
      case 9:
        return AppColors.error;
      case 2:
      case 3:
      case 6:
      case 10:
      case 11:
      case 12:
        return AppColors.warning;
      default:
        return AppColors.info;
    }
  }

  IconData get statusIcon {
    switch (status) {
      case 4:
      case 7:
      case 8:
        return Icons.check_circle;
      case 5:
      case 9:
        return Icons.error;
      case 2:
      case 3:
      case 6:
      case 10:
      case 11:
      case 12:
        return Icons.hourglass_empty;
      default:
        return Icons.info;
    }
  }
}