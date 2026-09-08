import 'dart:io';
import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../services/file_picker_service.dart';
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
  final TextEditingController _documentPasswordController = TextEditingController();

  // File Selection
  File? _selectedFile;
  String? _selectedFileName;
  bool _isFileSelected = false;

  @override
  void initState() {
    super.initState();
    // Auto-fill test data for Step 1
    _bvnController.text = '22146518957';
    _phoneController.text = '07026790425';

    // Auto-fill test data for Step 3
    _bankAccountController.text = '0123456789';
    _bankCodeController.text = '044';
    _bankNameController.text = 'Access Bank';
    _selectedIncomeSource = 'BusinessOwner';
    _tenureMonthsController.text = '6';
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

                // Show different content based on current step
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
      child: Row(
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
        // Progress indicator
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
                'Enter your BVN and phone number. An OTP will be sent to your phone.',
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
                  hintText: 'Enter phone number (e.g., 07026790425)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                  prefixText: '0',
                ),
              ),
              const SizedBox(height: 8),

              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.info.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.science, color: AppColors.info, size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Test Mode: BVN: 22146518957, Phone: 07026790425',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.info,
                        ),
                      ),
                    ),
                  ],
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
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error),
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
        // Progress indicator
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
                decoration: InputDecoration(
                  labelText: 'OTP',
                  hintText: 'Enter 6-digit OTP',
                  border: OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.password),
                  counterText: '',
                  suffixIcon: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.info.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.science, color: AppColors.info, size: 16),
                        SizedBox(width: 4),
                        Text(
                          'Test: 000000',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.info,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: _otpResendCooldown > 0
                        ? null
                        : () {
                      // Just reset the timer without calling API
                      _startResendTimer();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('OTP resent! (Test Mode)'),
                          backgroundColor: AppColors.info,
                        ),
                      );
                    },
                    child: Text(
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
                      style: TextStyle(
                        color: AppColors.textSecondary,
                      ),
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
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error),
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
                  onPressed: _isBvnVerificationInProgress ? null : _verifyOtp,
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
        // Progress indicator
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
            children: [
              const Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 8),
              const Expanded(
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
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Text(
                    _bvnController.text,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                children: [
                  const Text(
                    'Phone: ',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Text(
                    _phoneController.text,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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

              // Bank Account Number
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

              // Bank Code
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

              // Bank Name
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

              // Income Source
              DropdownButtonFormField<String>(
                value: _selectedIncomeSource,
                decoration: const InputDecoration(
                  labelText: 'Income Source',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                ),
                items: const [
                  DropdownMenuItem(value: 'SalaryEarner', child: Text('Salary Earner')),
                  DropdownMenuItem(value: 'BusinessOwner', child: Text('Business Owner')),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedIncomeSource = value;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Tenure Months
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

              // Employer Name (Optional)
              TextField(
                controller: _employerNameController,
                decoration: const InputDecoration(
                  labelText: 'Employer Name (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_center),
                ),
              ),
              const SizedBox(height: 12),

              // Document Password (Optional)
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

              // File Upload
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isFileSelected ? AppColors.success : AppColors.grey,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  color: _isFileSelected ? AppColors.success.withOpacity(0.05) : Colors.transparent,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _isFileSelected ? Icons.file_present : Icons.upload_file,
                          color: _isFileSelected ? AppColors.success : AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isFileSelected
                                ? _selectedFileName ?? 'File selected'
                                : 'Upload Bank Statement (PDF, JPEG, PNG - Max 5MB)',
                            style: TextStyle(
                              color: _isFileSelected ? AppColors.success : AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickFile,
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Choose File'),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.primary),
                              foregroundColor: AppColors.primary,
                            ),
                          ),
                        ),
                        if (_isFileSelected) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _selectedFile = null;
                                _selectedFileName = null;
                                _isFileSelected = false;
                              });
                            },
                            icon: const Icon(Icons.close, color: AppColors.error),
                            tooltip: 'Remove file',
                          ),
                        ],
                      ],
                    ),
                    if (_isFileSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: AppColors.success, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'File ready for upload',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (!_isFileSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.info.withOpacity(0.2)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: AppColors.info, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Upload a PDF, JPEG, or PNG file (max 5MB)',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoanRequestInProgress ? null : _submitLoanApplication,
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
                      Text('Submitting...'),
                    ],
                  )
                      : const Text(
                    'Submit Loan Application',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== SUCCESS SCREEN ====================

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
        const Text(
          'Application Submitted!',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your loan application has been submitted successfully.',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              const Text(
                'Application ID:',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _applicationId ?? 'N/A',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.warning.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warning, size: 14),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'We are processing your application. You will receive an update shortly.',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
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

  // ==================== BVN METHODS (Test Mode - No API Call) ====================

  Future<void> _sendOtp() async {
    // Validate BVN and Phone
    final String bvn = _bvnController.text.trim();
    final String phone = _phoneController.text.trim();

    if (bvn.isEmpty || bvn.length < 11) {
      setState(() {
        _bvnErrorMessage = 'Please enter a valid 11-digit BVN';
      });
      return;
    }

    if (phone.isEmpty || phone.length < 10) {
      setState(() {
        _bvnErrorMessage = 'Please enter a valid phone number';
      });
      return;
    }

    // TEST MODE: Bypass API call and go directly to OTP entry
    setState(() {
      _isOtpSent = true;
      _bvnErrorMessage = null;
      _otpController.clear();
      // Set a test session ID for simulation
      _bvnSessionId = 'test-session-123';
    });

    _startResendTimer();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Test Mode: OTP sent! (Use 000000)'),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _verifyOtp() async {
    final String otp = _otpController.text.trim();

    if (otp.isEmpty || otp.length < 6) {
      setState(() {
        _bvnErrorMessage = 'Please enter a valid 6-digit OTP';
      });
      return;
    }

    // TEST MODE: Accept any 6-digit OTP, but specifically 000000
    if (otp == '000000') {
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
        _bvnErrorMessage = 'Invalid OTP. Please enter the correct OTP.';
      });
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _otpResendCooldown = 30;
    });

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_otpResendCooldown > 0) {
          _otpResendCooldown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  // ==================== FILE PICKER ====================


  // Add this method to request permissions
  // Future<bool> _requestStoragePermission() async {
  //   try {
  //     if (Platform.isAndroid) {
  //       // For Android 13+ (API 33+)
  //       if (await Permission.storage.isGranted) {
  //         final status = await Permission.storage.request();
  //         if (status.isGranted) {
  //           return true;
  //         }
  //       }
  //
  //       // For Android 11+ (API 30+), use manage external storage
  //       if (await Permission.manageExternalStorage.isGranted) {
  //         final status = await Permission.manageExternalStorage.request();
  //         if (status.isGranted) {
  //           return true;
  //         }
  //       }
  //
  //       return await Permission.storage.isGranted;
  //     }
  //     return true; // iOS doesn't need this permission
  //   } catch (e) {
  //     print('Permission error: $e');
  //     return false;
  //   }
  // }


// Updated _pickFile method


  Future<void> _pickFile() async {
    try {
      // Request permission for Android
      if (Platform.isAndroid) {
        final hasPermission = await _requestStoragePermission();
        if (!hasPermission) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission required to select files'),
              backgroundColor: AppColors.warning,
            ),
          );
          return;
        }
      }

      // Show file type selection
      final fileType = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Select File Type'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Image (JPEG/PNG)'),
                onTap: () => Navigator.pop(context, 'image'),
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('PDF Document'),
                onTap: () => Navigator.pop(context, 'pdf'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (fileType == null || fileType == 'cancel') {
        return;
      }

      Map<String, dynamic>? result;

      if (fileType == 'image') {
        result = await FilePickerService.pickFile(
          allowedExtensions: ['jpg', 'jpeg', 'png'],
        );
      } else if (fileType == 'pdf') {
        result = await FilePickerService.pickFile(
          allowedExtensions: ['pdf'],
        );
      }

      if (result != null) {
        final fileSize = result['size'] as int? ?? 0;
        if (fileSize > 5 * 1024 * 1024) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File size exceeds 5MB limit. Please compress the file.'),
              backgroundColor: AppColors.error,
            ),
          );
          return;
        }

        String? path = result['path'];
        String name = result['name'] ?? 'file';

        if (path != null && path.isNotEmpty) {
          setState(() {
            _selectedFile = File(path);
            _selectedFileName = name;
            _isFileSelected = true;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File selected: $name'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }




  Future<bool> _requestStoragePermission() async {
    try {
      if (Platform.isAndroid) {
        // For Android 13+ (API 33+)
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt >= 33) {
          // Android 13+ - use READ_MEDIA_IMAGES
          final status = await Permission.photos.request();
          if (status.isGranted) {
            return true;
          }
          final storageStatus = await Permission.storage.request();
          return storageStatus.isGranted;
        } else if (sdkInt >= 30) {
          // Android 11-12 - use MANAGE_EXTERNAL_STORAGE
          final status = await Permission.manageExternalStorage.request();
          if (status.isGranted) {
            return true;
          }
          final storageStatus = await Permission.storage.request();
          return storageStatus.isGranted;
        } else {
          // Android 10 and below
          final status = await Permission.storage.request();
          return status.isGranted;
        }
      }
      return true; // iOS doesn't need this permission
    } catch (e) {
      print('Permission error: $e');
      return false;
    }
  }

  // ==================== SUBMIT APPLICATION ====================

  Future<void> _submitLoanApplication() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

    if (token == null || user == null) {
      setState(() {
        _loanErrorMessage = 'Authentication error. Please login again.';
      });
      return;
    }

    // Validate all fields
    final String bankAccount = _bankAccountController.text.trim();
    final String bankCode = _bankCodeController.text.trim();
    final String bankName = _bankNameController.text.trim();
    final String tenureMonths = _tenureMonthsController.text.trim();

    if (bankAccount.isEmpty || bankAccount.length < 10) {
      setState(() {
        _loanErrorMessage = 'Please enter a valid bank account number';
      });
      return;
    }

    if (bankCode.isEmpty) {
      setState(() {
        _loanErrorMessage = 'Please enter the bank code';
      });
      return;
    }

    if (bankName.isEmpty) {
      setState(() {
        _loanErrorMessage = 'Please enter the bank name';
      });
      return;
    }

    if (_selectedIncomeSource == null || _selectedIncomeSource!.isEmpty) {
      setState(() {
        _loanErrorMessage = 'Please select your income source';
      });
      return;
    }

    if (tenureMonths.isEmpty || int.tryParse(tenureMonths) == null) {
      setState(() {
        _loanErrorMessage = 'Please enter a valid tenure in months';
      });
      return;
    }

    if (!_isFileSelected || _selectedFile == null) {
      setState(() {
        _loanErrorMessage = 'Please upload your bank statement';
      });
      return;
    }

    setState(() {
      _isLoanRequestInProgress = true;
      _loanErrorMessage = null;
    });

    try {
      final result = await _apiService.uploadCreditAssessment(
        token: token,
        guardianId: user.id,
        edubanclSchoolId: user.schoolId,
        bankAccountNumber: bankAccount,
        bankCode: bankCode,
        bankName: bankName,
        incomeSource: _selectedIncomeSource!,
        tenureMonths: int.parse(tenureMonths),
        file: _selectedFile!,
        documentPassword: _documentPasswordController.text.trim().isEmpty
            ? null
            : _documentPasswordController.text.trim(),
        employerName: _employerNameController.text.trim().isEmpty
            ? null
            : _employerNameController.text.trim(),
      );

      if (result['success']) {
        setState(() {
          _applicationId = result['applicationId'];
          _isLoanRequestInProgress = false;
          _loanSuccessMessage = result['message'] ?? 'Application submitted successfully!';
          _loanErrorMessage = null;
          _showSuccessScreen = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Application submitted successfully! 🎉'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        setState(() {
          _isLoanRequestInProgress = false;
          _loanErrorMessage = result['message'] ?? 'Failed to submit application';
        });
      }
    } catch (e) {
      setState(() {
        _isLoanRequestInProgress = false;
        _loanErrorMessage = 'Error: ${e.toString()}';
      });
    }
  }
}