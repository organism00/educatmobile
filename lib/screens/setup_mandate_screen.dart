import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../utils/app_colors.dart';

class SetupMandateScreen extends StatefulWidget {
  final String applicationId;

  const SetupMandateScreen({
    super.key,
    required this.applicationId,
  });

  @override
  State<SetupMandateScreen> createState() => _SetupMandateScreenState();
}

class _SetupMandateScreenState extends State<SetupMandateScreen> {
  final ApiService _apiService = ApiService();

  // Controllers
  final TextEditingController _accountNumberController = TextEditingController();
  final TextEditingController _bankCodeController = TextEditingController();
  final TextEditingController _accountNameController = TextEditingController();

  bool _isSubmitting = false;
  bool _isPolling = false;
  bool _mandateSetupComplete = false;
  String? _authorizationUrl;
  String? _errorMessage;
  String? _statusLabel;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    // Auto-fill with test data
    _accountNumberController.text = '0123456789';
    _bankCodeController.text = '044';
    _accountNameController.text = 'John Doe';
  }

  @override
  void dispose() {
    _accountNumberController.dispose();
    _bankCodeController.dispose();
    _accountNameController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _setupMandate() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token == null) {
      setState(() {
        _errorMessage = 'Authentication error. Please login again.';
      });
      return;
    }

    if (_accountNumberController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your bank account number');
      return;
    }

    if (_bankCodeController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter the bank code');
      return;
    }

    if (_accountNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter the account name');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await _apiService.setupMandate(
        token: token,
        applicationId: widget.applicationId,
        accountNumber: _accountNumberController.text.trim(),
        bankCode: _bankCodeController.text.trim(),
        accountName: _accountNameController.text.trim(),
      );

      setState(() {
        _isSubmitting = false;
      });

      if (result['success']) {
        final String? authorizationUrl = result['authorizationUrl'];
        setState(() {
          _authorizationUrl = authorizationUrl;
          _mandateSetupComplete = true;
        });

        if (authorizationUrl != null && authorizationUrl.isNotEmpty) {
          // Open authorization URL
          await _openAuthorizationUrl(authorizationUrl);
          // Start polling loan status
          _startPolling();
        }
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to setup mandate';
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _openAuthorizationUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        setState(() {
          _errorMessage = 'Could not open authorization page';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error opening authorization: ${e.toString()}';
      });
    }
  }

  void _startPolling() {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    setState(() {
      _isPolling = true;
    });

    int attempts = 0;
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      attempts++;

      if (attempts > 60) {
        timer.cancel();
        setState(() {
          _isPolling = false;
        });
        return;
      }

      try {
        final result = await _apiService.pollLoanStatus(
          token: token,
          applicationId: widget.applicationId,
        );

        if (result['success']) {
          final bool isPending = result['isPending'] ?? false;
          final int status = result['status'] ?? 0;
          final String statusLabel = result['statusLabel'] ?? '';

          setState(() {
            _statusLabel = statusLabel;
          });

          if (!isPending) {
            timer.cancel();
            setState(() {
              _isPolling = false;
            });

            if (status == 7) {
              // Approved
              _showTerminalStatusDialog(
                'Loan Approved! 🎉',
                'Your loan has been approved and is pending disbursement.',
                AppColors.success,
              );
            } else if (status == 8) {
              // Disbursed
              _showTerminalStatusDialog(
                'Loan Disbursed! 🎉',
                'Funds have been sent to the school. Journey complete!',
                AppColors.success,
              );
            } else if (status == 9) {
              // Rejected
              _showTerminalStatusDialog(
                'Loan Rejected',
                result['message'] ?? 'Your loan application was declined.',
                AppColors.error,
              );
            }
          }
        }
      } catch (e) {
        print('Polling error: $e');
      }
    });
  }

  void _showTerminalStatusDialog(String title, String message, Color color) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: TextStyle(color: color)),
        content: Text(message),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup Repayment'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(isSmallScreen),
                const SizedBox(height: 24),
                if (_mandateSetupComplete)
                  _buildMandateStatusCard()
                else
                  _buildMandateForm(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorWidget(),
                ],
                if (_isPolling) ...[
                  const SizedBox(height: 16),
                  _buildPollingWidget(),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isSmallScreen) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_balance,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Setup Repayment Mandate',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Provide your bank account for automatic repayments',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMandateForm() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bank Account Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _accountNumberController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Account Number',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_balance),
              hintText: 'e.g., 0123456789',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bankCodeController,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'Bank Code',
              hintText: 'e.g., 044 (Access Bank)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.code),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _accountNameController,
            decoration: const InputDecoration(
              labelText: 'Account Name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.info, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You will be redirected to your bank to authorize the direct debit mandate.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _setupMandate,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isSubmitting
                  ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Setting up...'),
                ],
              )
                  : const Text(
                'Setup Mandate',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMandateStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: AppColors.success,
              size: 40,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Mandate Setup Initiated',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please complete the authorization in your bank app or web browser.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          if (_authorizationUrl != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openAuthorizationUrl(_authorizationUrl!),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open Bank Authorization'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPollingWidget() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Checking Loan Status...',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  _statusLabel ?? 'Waiting for bank authorization...',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
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
}