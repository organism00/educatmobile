import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/loan_application.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../utils/app_colors.dart';
import 'loan_application_screen.dart';

class AssessmentStatusScreen extends StatefulWidget {
  final String applicationId;
  final LoanApplication? application; // Add optional existing application

  const AssessmentStatusScreen({
    super.key,
    required this.applicationId,
    this.application, // Optional: pass existing application data
  });

  @override
  State<AssessmentStatusScreen> createState() => _AssessmentStatusScreenState();
}

class _AssessmentStatusScreenState extends State<AssessmentStatusScreen> {
  final ApiService _apiService = ApiService();

  bool _isPolling = true;
  bool _isComplete = false;
  bool _hasFailed = false;
  String? _statusLabel;
  double? _eligibleAmount;
  String? _creditAssessmentId;
  String? _errorMessage;
  int _attempts = 0;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();

    // If we have existing application data, use it
    if (widget.application != null) {
      final app = widget.application!;
      _statusLabel = app.statusLabel;
      _eligibleAmount = app.eligibleAmount;
      _creditAssessmentId = app.creditAssessmentId;

      // If already complete or failed, don't poll
      if (app.status == 4) {
        _isComplete = true;
        _isPolling = false;
      } else if (app.status == 5 || app.status == 9) {
        _hasFailed = true;
        _isPolling = false;
        _errorMessage = app.edubanclStatusMessage ?? 'Assessment failed.';
      } else {
        _startPolling();
      }
    } else {
      _startPolling();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollStatus();
  }

  Future<void> _pollStatus() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token == null) {
      setState(() {
        _errorMessage = 'Authentication error. Please login again.';
        _isPolling = false;
      });
      return;
    }

    // Poll every 5 seconds
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      _attempts++;

      // Stop after 60 attempts (5 minutes)
      if (_attempts > 60) {
        timer.cancel();
        setState(() {
          _isPolling = false;
          _errorMessage = 'Assessment taking longer than expected. Please check back later.';
        });
        return;
      }

      try {
        final result = await _apiService.getCreditAssessment(
          token: token,
          applicationId: widget.applicationId,
        );

        print('📊 Poll attempt $_attempts: ${result['statusLabel']}');

        if (result['success']) {
          final bool isPending = result['isPending'] ?? false;
          final int status = result['status'] ?? 0;
          final String statusLabel = result['statusLabel'] ?? '';
          final double? eligibleAmount = result['eligibleAmount'] as double?;

          setState(() {
            _statusLabel = statusLabel;
            _eligibleAmount = eligibleAmount;
          });

          if (!isPending) {
            timer.cancel();
            setState(() {
              _isPolling = false;
            });

            if (status == 4) {
              // Complete
              setState(() {
                _isComplete = true;
                _creditAssessmentId = result['creditAssessmentId'];
              });

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ Assessment complete! Eligible: ₦${eligibleAmount?.toStringAsFixed(2) ?? '0.00'}'),
                  backgroundColor: AppColors.success,
                ),
              );
              return;
            } else if (status == 5) {
              // Failed
              setState(() {
                _hasFailed = true;
                _errorMessage = result['message'] ?? 'Credit assessment failed. Please try again.';
              });
              return;
            }
          }
        }
      } catch (e) {
        print('Polling error: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assessment Status'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildStatusIcon(),
                const SizedBox(height: 24),
                _buildStatusMessage(),
                const SizedBox(height: 16),
                _buildStatusDetails(),
                const SizedBox(height: 24),
                if (_errorMessage != null)
                  _buildErrorWidget(),
                if (_isComplete)
                  _buildApplyButton(),
                if (_hasFailed)
                  _buildRetryButton(),
                if (_errorMessage != null && !_isComplete && !_hasFailed)
                  _buildRetryButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    IconData icon;
    Color color;

    if (_isComplete) {
      icon = Icons.check_circle;
      color = AppColors.success;
    } else if (_hasFailed) {
      icon = Icons.error;
      color = AppColors.error;
    } else if (_isPolling) {
      icon = Icons.hourglass_empty;
      color = AppColors.warning;
    } else {
      icon = Icons.info;
      color = AppColors.info;
    }

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.1),
        border: Border.all(color: color, width: 3),
      ),
      child: Icon(
        icon,
        size: 48,
        color: color,
      ),
    );
  }

  Widget _buildStatusMessage() {
    String title;
    String subtitle;
    Color color;

    if (_isComplete) {
      title = 'Assessment Complete!';
      subtitle = 'You are eligible for a loan up to ₦${_eligibleAmount?.toStringAsFixed(2) ?? '0.00'}';
      color = AppColors.success;
    } else if (_hasFailed) {
      title = 'Assessment Failed';
      subtitle = 'Please try again or contact support.';
      color = AppColors.error;
    } else if (_isPolling) {
      title = 'Processing Assessment';
      subtitle = _statusLabel ?? 'Please wait...';
      color = AppColors.warning;
    } else {
      title = 'Status Unknown';
      subtitle = 'Please check your application status.';
      color = AppColors.info;
    }

    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatusDetails() {
    if (_isPolling) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.info.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a few minutes...',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyLight),
      ),
      child: Column(
        children: [
          _buildInfoRow('Application ID', widget.applicationId),
          _buildInfoRow('Status', _statusLabel ?? 'N/A'),
          if (_eligibleAmount != null)
            _buildInfoRow('Eligible Amount', '₦${_eligibleAmount!.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplyButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => LoanApplicationScreen(
                creditAssessmentId: _creditAssessmentId!,
                eligibleAmount: _eligibleAmount ?? 0,
              ),
            ),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'Apply for Loan',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildRetryButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          Navigator.pop(context);
        },
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.primary),
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: const Text(
          'Go Back',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}