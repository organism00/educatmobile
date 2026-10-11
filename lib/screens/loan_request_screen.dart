import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../utils/app_colors.dart';

class LoanRequestScreen extends StatefulWidget {
  const LoanRequestScreen({super.key});

  @override
  State<LoanRequestScreen> createState() => _LoanRequestScreenState();
}

class _LoanRequestScreenState extends State<LoanRequestScreen> {
  final ApiService _apiService = ApiService();

  // ==================== STEP 1: BVN VERIFICATION ====================
  bool _isBvnVerificationInProgress = false;
  bool _isBvnVerified = false;
  String? _bvnSessionId;
  String? _bvnErrorMessage;

  // Step 1 Controllers
  final TextEditingController _bvnController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // ==================== STEP 2: OTP VERIFICATION ====================
  bool _isOtpSent = false;
  bool _isSendingOtp = false;
  int _otpResendCooldown = 0;
  Timer? _resendTimer;
  final TextEditingController _otpController = TextEditingController();

  // ==================== STEP 3: LOAN APPLICATION ====================
  bool _isLoanRequestInProgress = false;
  String? _loanErrorMessage;
  String? _loanSuccessMessage;
  String? _applicationId;
  bool _showSuccessScreen = false;

  // Step 3 Controllers
  final TextEditingController _bankAccountController = TextEditingController();
  final TextEditingController _bankCodeController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  String? _selectedIncomeSource;
  final TextEditingController _tenureMonthsController = TextEditingController();
  final TextEditingController _employerNameController = TextEditingController();
  final TextEditingController _documentPasswordController =
  TextEditingController();

  @override
  void initState() {
    super.initState();
    // Don't auto-fill BVN in production. Uncomment only for testing.
    // _bvnController.text = '22146518957';
    // _phoneController.text = '07026790425';
  }

  @override
  void dispose() {
    _bvnController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _bankAccountController.dispose();
    _bankCodeController.dispose();
    _bankNameController.dispose();
    _tenureMonthsController.dispose();
    _employerNameController.dispose();
    _documentPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Loan'),
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
                _buildHeaderCard(isSmallScreen),
                const SizedBox(height: 24),

                if (_showSuccessScreen)
                  _buildSuccessStep(isSmallScreen)
                else if (_isBvnVerified)
                  _buildLoanApplicationStep(isSmallScreen)
                else if (_isOtpSent)
                    _buildOtpVerificationStep(isSmallScreen)
                  else
                    _buildBvnEntryStep(isSmallScreen),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==================== HEADER WITH EDUBANC BRANDING ====================

  Widget _buildHeaderCard(bool isSmallScreen) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row — icon + title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.credit_card,
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
                      'Loan Application',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _getStepDescription(),
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

          // Edubanc "Powered by" strip
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text(
                  'Powered by',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 8),
                Image.asset(
                  'assets/images/edubanc_logo.png',
                  height: 18,
                  fit: BoxFit.contain,
                  color: Colors.white,
                  colorBlendMode: BlendMode.srcIn,
                  errorBuilder: (context, error, stackTrace) {
                    return const Text(
                      'edubanc',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getStepDescription() {
    if (_showSuccessScreen) return 'Application Submitted! 🎉';
    if (_isBvnVerified) return 'Step 3: Complete Credit Assessment';
    if (_isOtpSent) return 'Step 2: Enter OTP';
    return 'Step 1: Verify BVN';
  }

  // ==================== STEP 1: BVN ENTRY ====================

  Widget _buildBvnEntryStep(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProgressIndicator(1),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.info, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Step 1: Enter BVN Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.info,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter your BVN and the phone number registered with your BVN. '
                    'An OTP will be sent to that phone number.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Container(
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
                'BVN Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _bvnController,
                keyboardType: TextInputType.number,
                maxLength: 11,
                decoration: const InputDecoration(
                  labelText: 'BVN',
                  hintText: 'Enter your 11-digit BVN',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.credit_card),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'Enter the phone number linked to your BVN',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  prefixText: '0',
                ),
              ),
              const SizedBox(height: 16),

              if (_bvnErrorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                    Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _bvnErrorMessage!,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isBvnVerificationInProgress ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isBvnVerificationInProgress
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
                      Text('Sending OTP...'),
                    ],
                  )
                      : const Text(
                    'Send OTP',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== STEP 2: OTP VERIFICATION ====================

  Widget _buildOtpVerificationStep(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProgressIndicator(2),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.success.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'OTP Sent Successfully!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.success,
                      ),
                    ),
                    Text(
                      'Enter the 6-digit code sent to ${_phoneController.text}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter OTP',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please enter the 6-digit OTP sent to your phone',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'OTP',
                  hintText: 'Enter 6-digit OTP',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.password),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: (_otpResendCooldown > 0 || _isSendingOtp)
                        ? null
                        : _resendOtp,
                    child: _isSendingOtp
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : Text(
                      _otpResendCooldown > 0
                          ? 'Resend in ${_otpResendCooldown}s'
                          : 'Resend OTP',
                      style: TextStyle(
                        color: _otpResendCooldown > 0
                            ? AppColors.grey
                            : AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isOtpSent = false;
                        _bvnErrorMessage = null;
                        _otpController.clear();
                      });
                    },
                    child: const Text(
                      '← Back',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (_bvnErrorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                    Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _bvnErrorMessage!,
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                  _isBvnVerificationInProgress ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isBvnVerificationInProgress
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
                      Text('Verifying...'),
                    ],
                  )
                      : const Text(
                    'Verify OTP',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== STEP 3: LOAN APPLICATION ====================

  Widget _buildLoanApplicationStep(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildProgressIndicator(3),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.success.withOpacity(0.3)),
          ),
          child: Row(
            children: const [
              Icon(Icons.check_circle, color: AppColors.success),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'BVN Verified Successfully! Complete the form to apply.',
                  style: TextStyle(color: AppColors.success),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verified Information',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'BVN: ',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Text(
                    _bvnController.text,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    'Phone: ',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Text(
                    _phoneController.text,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (_loanErrorMessage != null)
          Container(
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
                    _loanErrorMessage!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              ],
            ),
          ),

        Container(
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
                'Credit Assessment Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _bankAccountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Bank Account Number',
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
                controller: _bankNameController,
                decoration: const InputDecoration(
                  labelText: 'Bank Name',
                  hintText: 'e.g., Access Bank',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: _selectedIncomeSource,
                decoration: const InputDecoration(
                  labelText: 'Income Source',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'SalaryEarner', child: Text('Salary Earner')),
                  DropdownMenuItem(
                      value: 'BusinessOwner', child: Text('Business Owner')),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedIncomeSource = value;
                  });
                },
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _tenureMonthsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tenure (Months)',
                  hintText: 'e.g., 6',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_month),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _employerNameController,
                decoration: const InputDecoration(
                  labelText: 'Employer Name (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_center),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _documentPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Document Password (Optional)',
                  hintText: 'If your PDF is password protected',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border:
                  Border.all(color: AppColors.info.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: AppColors.info, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'After submitting, you will upload your bank statement for credit assessment.',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoanRequestInProgress
                      ? null
                      : _proceedToCreditAssessment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isLoanRequestInProgress
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
                      Text('Processing...'),
                    ],
                  )
                      : const Text(
                    'Proceed to Upload Bank Statement',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== SUCCESS SCREEN (WITH EDUBANC LOGO) ====================

  Widget _buildSuccessStep(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            gradient: AppColors.cardGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.success.withOpacity(0.3),
                blurRadius: 20,
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.check_circle,
              color: Colors.white,
              size: 60,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Edubanc logo on success screen
        Image.asset(
          'assets/images/edubanc_logo.png',
          height: 28,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Text(
              'edubanc',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
                letterSpacing: -1,
              ),
            );
          },
        ),
        const SizedBox(height: 16),

        const Text(
          'BVN Verified!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Proceed to upload your bank statement for credit assessment.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  // ==================== PROGRESS INDICATOR ====================

  Widget _buildProgressIndicator(int currentStep) {
    return Row(
      children: [
        _buildProgressStep(1, 'BVN', currentStep >= 1),
        Expanded(
          child: Container(
            height: 2,
            color: currentStep >= 2 ? AppColors.primary : AppColors.grey,
          ),
        ),
        _buildProgressStep(2, 'OTP', currentStep >= 2),
        Expanded(
          child: Container(
            height: 2,
            color: currentStep >= 3 ? AppColors.primary : AppColors.grey,
          ),
        ),
        _buildProgressStep(3, 'Apply', currentStep >= 3),
      ],
    );
  }

  Widget _buildProgressStep(int step, String label, bool isActive) {
    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? AppColors.primary : AppColors.greyLight,
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.grey,
              width: 2,
            ),
          ),
          child: Center(
            child: isActive
                ? Text(
              step.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            )
                : const Icon(
              Icons.check,
              color: AppColors.success,
              size: 16,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? AppColors.primary : AppColors.grey,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ==================== API METHODS ====================

  /// Step 1 → Send OTP
  Future<void> _sendOtp() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

    if (token == null || user == null) {
      setState(() {
        _bvnErrorMessage = 'Authentication error. Please login again.';
      });
      return;
    }

    if (user.schoolId.isEmpty ||
        user.schoolId == '00000000-0000-0000-0000-000000000000') {
      setState(() =>
      _bvnErrorMessage = 'Internal school ID missing. Please re-login.');
      return;
    }

    final String bvn = _bvnController.text.trim();
    final String phone = _phoneController.text.trim();

    if (bvn.isEmpty || bvn.length < 11) {
      setState(() => _bvnErrorMessage = 'Please enter a valid 11-digit BVN');
      return;
    }

    if (phone.isEmpty || phone.length < 10) {
      setState(() => _bvnErrorMessage = 'Please enter a valid phone number');
      return;
    }

    setState(() {
      _isBvnVerificationInProgress = true;
      _bvnErrorMessage = null;
    });

    try {
      // 1. Initiate BVN session
      final initiateResult = await _apiService.initiateBvnVerification(
        token: token,
        guardianId: user.id,
        internalSchoolId: user.schoolId,
      );

      if (!initiateResult['success']) {
        setState(() {
          _isBvnVerificationInProgress = false;
          _bvnErrorMessage =
              initiateResult['message'] ?? 'Failed to initiate BVN';
        });
        return;
      }

      final String? sessionId = initiateResult['sessionId'];
      if (sessionId == null || sessionId.isEmpty) {
        setState(() {
          _isBvnVerificationInProgress = false;
          _bvnErrorMessage = 'Invalid session response from server';
        });
        return;
      }

      setState(() => _bvnSessionId = sessionId);

      // 2. Actually send the OTP to the phone number
      final verifyResult = await _apiService.verifyBvnMethod(
        token: token,
        guardianId: user.id,
        internalSchoolId: user.schoolId,
        sessionId: sessionId,
        method: 'phone',
        phoneNumber: phone,
      );

      if (verifyResult['success']) {
        setState(() {
          _isOtpSent = true;
          _isBvnVerificationInProgress = false;
          _bvnErrorMessage = null;
          _otpController.clear();
        });

        _startResendTimer();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OTP sent to $phone'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() {
          _isBvnVerificationInProgress = false;
          _bvnErrorMessage = verifyResult['message'] ?? 'Failed to send OTP';
        });
      }
    } catch (e) {
      setState(() {
        _isBvnVerificationInProgress = false;
        _bvnErrorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  /// Resend OTP
  Future<void> _resendOtp() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

    if (token == null || user == null) {
      setState(() => _bvnErrorMessage = 'Authentication error');
      return;
    }

    if (_bvnSessionId == null || _bvnSessionId!.isEmpty) {
      setState(() =>
      _bvnErrorMessage = 'Session expired. Please go back and try again.');
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _bvnErrorMessage = null;
    });

    try {
      final result = await _apiService.verifyBvnMethod(
        token: token,
        guardianId: user.id,
        internalSchoolId: user.schoolId,
        sessionId: _bvnSessionId!,
        method: 'phone',
        phoneNumber: _phoneController.text.trim(),
      );

      setState(() => _isSendingOtp = false);

      if (result['success']) {
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP resent successfully'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() {
          _bvnErrorMessage = result['message'] ?? 'Failed to resend OTP';
        });
      }
    } catch (e) {
      setState(() {
        _isSendingOtp = false;
        _bvnErrorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  /// Verify OTP
  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    final bvn = _bvnController.text.trim();
    final phone = _phoneController.text.trim();
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

    if (token == null || user == null) {
      setState(() => _bvnErrorMessage = 'Authentication error');
      return;
    }

    if (otp.isEmpty || otp.length < 6) {
      setState(() => _bvnErrorMessage = 'Please enter the 6-digit OTP');
      return;
    }

    setState(() {
      _isBvnVerificationInProgress = true;
      _bvnErrorMessage = null;
    });

    try {
      final result = await _apiService.confirmBvnOtp(
        token: token,
        guardianId: user.id,
        internalSchoolId: user.schoolId,
        sessionId: _bvnSessionId ?? '',
        otp: otp,
        bvn: bvn,
        bvnPhoneNumber: phone,
      );

      if (result['success']) {
        setState(() {
          _isBvnVerified = true;
          _isBvnVerificationInProgress = false;
          _bvnErrorMessage = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('BVN Verified Successfully! 🎉'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() {
          _isBvnVerificationInProgress = false;
          _bvnErrorMessage =
              result['message'] ?? 'Invalid OTP. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isBvnVerificationInProgress = false;
        _bvnErrorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _otpResendCooldown = 60);

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_otpResendCooldown > 0) {
          _otpResendCooldown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  /// Proceed to credit assessment step
  Future<void> _proceedToCreditAssessment() async {
    // After BVN verification, navigate to the credit assessment upload screen
    Navigator.pop(context, true);
  }
}