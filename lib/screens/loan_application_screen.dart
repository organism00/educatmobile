import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../utils/app_colors.dart';

class LoanApplicationScreen extends StatefulWidget {
  final String creditAssessmentId;
  final double eligibleAmount;

  const LoanApplicationScreen({
    super.key,
    required this.creditAssessmentId,
    required this.eligibleAmount,
  });

  @override
  State<LoanApplicationScreen> createState() => _LoanApplicationScreenState();
}

class _LoanApplicationScreenState extends State<LoanApplicationScreen> {
  final ApiService _apiService = ApiService();

  // Controllers
  final TextEditingController _studentIdController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _nextOfKinNameController = TextEditingController();
  final TextEditingController _nextOfKinPhoneController = TextEditingController();
  final TextEditingController _nextOfKinRelationshipController = TextEditingController();
  final TextEditingController _nextOfKinOccupationController = TextEditingController();

  String? _selectedLoanType;
  String? _selectedTerm;
  String? _selectedAcademicSession;
  String? _selectedTenure;

  bool _isSubmitting = false;
  String? _errorMessage;
  bool _showSuccess = false;
  String? _applicationId;

  @override
  void initState() {
    super.initState();
    // Auto-fill test student ID
    _studentIdController.text = '70afafea-a243-4b7d-7fa1-08def6bf471e';
    _selectedLoanType = 'Termly';
    _selectedTerm = 'FirstTerm';
    _selectedAcademicSession = '2025/2026';
    _selectedTenure = 'SixMonths';
    _amountController.text = '120000';
    _nextOfKinNameController.text = 'Jane Doe';
    _nextOfKinPhoneController.text = '08012345678';
    _nextOfKinRelationshipController.text = 'Spouse';
    _nextOfKinOccupationController.text = 'Teacher';
  }

  @override
  void dispose() {
    _studentIdController.dispose();
    _amountController.dispose();
    _nextOfKinNameController.dispose();
    _nextOfKinPhoneController.dispose();
    _nextOfKinRelationshipController.dispose();
    _nextOfKinOccupationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apply for Loan'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: _showSuccess
              ? _buildSuccessScreen(isSmallScreen)
              : SingleChildScrollView(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
            child: _buildForm(isSmallScreen),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessScreen(bool isSmallScreen) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
              'Loan Application Submitted!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
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
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
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
                  'Go to Dashboard',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Eligibility Banner
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
              Expanded(
                child: Text(
                  'You are eligible for a loan up to ₦${widget.eligibleAmount.toStringAsFixed(2)}',
                  style: TextStyle(color: AppColors.success),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        if (_errorMessage != null)
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
                    _errorMessage!,
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
                'Loan Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),

              // Student ID
              TextField(
                controller: _studentIdController,
                decoration: const InputDecoration(
                  labelText: 'Student ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                  hintText: 'Enter the student ID',
                ),
              ),
              const SizedBox(height: 12),

              // Loan Type
              DropdownButtonFormField<String>(
                value: _selectedLoanType,
                decoration: const InputDecoration(
                  labelText: 'Loan Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.style),
                ),
                items: const [
                  DropdownMenuItem(value: 'Termly', child: Text('Termly')),
                  DropdownMenuItem(value: 'Session', child: Text('Session')),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedLoanType = value;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Term
              DropdownButtonFormField<String>(
                value: _selectedTerm,
                decoration: const InputDecoration(
                  labelText: 'Term',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.book),
                ),
                items: const [
                  DropdownMenuItem(value: 'FirstTerm', child: Text('First Term')),
                  DropdownMenuItem(value: 'SecondTerm', child: Text('Second Term')),
                  DropdownMenuItem(value: 'ThirdTerm', child: Text('Third Term')),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedTerm = value;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Academic Session
              DropdownButtonFormField<String>(
                value: _selectedAcademicSession,
                decoration: const InputDecoration(
                  labelText: 'Academic Session',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today),
                ),
                items: const [
                  DropdownMenuItem(value: '2024/2025', child: Text('2024/2025')),
                  DropdownMenuItem(value: '2025/2026', child: Text('2025/2026')),
                  DropdownMenuItem(value: '2026/2027', child: Text('2026/2027')),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedAcademicSession = value;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Tenure
              DropdownButtonFormField<String>(
                value: _selectedTenure,
                decoration: const InputDecoration(
                  labelText: 'Repayment Tenure',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer),
                ),
                items: const [
                  DropdownMenuItem(value: 'OneMonth', child: Text('1 Month')),
                  DropdownMenuItem(value: 'TwoMonths', child: Text('2 Months')),
                  DropdownMenuItem(value: 'ThreeMonths', child: Text('3 Months')),
                  DropdownMenuItem(value: 'SixMonths', child: Text('6 Months')),
                  DropdownMenuItem(value: 'TwelveMonths', child: Text('12 Months')),
                ],
                onChanged: (String? value) {
                  setState(() {
                    _selectedTenure = value;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Amount
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Requested Amount (₦)',
                  prefixText: '₦',
                  border: OutlineInputBorder(),
                  hintText: 'Enter amount',
                ),
              ),
              const SizedBox(height: 16),

              const Divider(),
              const SizedBox(height: 8),

              const Text(
                'Next of Kin Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _nextOfKinNameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _nextOfKinPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _nextOfKinRelationshipController,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.family_restroom),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _nextOfKinOccupationController,
                decoration: const InputDecoration(
                  labelText: 'Occupation',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
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
            onPressed: _isSubmitting ? null : _submitApplication,
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
                Text('Submitting...'),
              ],
            )
                : const Text(
              'Submit Application',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitApplication() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;

    if (token == null || user == null) {
      setState(() {
        _errorMessage = 'Authentication error. Please login again.';
      });
      return;
    }

    // Validate
    if (_studentIdController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter the student ID');
      return;
    }

    if (_selectedLoanType == null) {
      setState(() => _errorMessage = 'Please select loan type');
      return;
    }

    if (_selectedTerm == null) {
      setState(() => _errorMessage = 'Please select term');
      return;
    }

    if (_selectedAcademicSession == null) {
      setState(() => _errorMessage = 'Please select academic session');
      return;
    }

    if (_selectedTenure == null) {
      setState(() => _errorMessage = 'Please select repayment tenure');
      return;
    }

    final double? amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Please enter a valid loan amount');
      return;
    }

    if (amount > widget.eligibleAmount) {
      setState(() {
        _errorMessage = 'Requested amount (₦${amount.toStringAsFixed(2)}) exceeds eligible amount (₦${widget.eligibleAmount.toStringAsFixed(2)})';
      });
      return;
    }

    if (_nextOfKinNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter next of kin name');
      return;
    }

    if (_nextOfKinPhoneController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter next of kin phone number');
      return;
    }

    if (_nextOfKinRelationshipController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter next of kin relationship');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await _apiService.submitLoanApplication(
        token: token,
        guardianId: user.id,
        studentId: _studentIdController.text.trim(),
        internalSchoolId: user.schoolId,
        edubanclSchoolId: user.schoolId,
        creditAssessmentId: widget.creditAssessmentId,
        loanType: _selectedLoanType!,
        term: _selectedTerm!,
        academicSession: _selectedAcademicSession!,
        tenure: _selectedTenure!,
        requestedAmount: amount,
        nextOfKin: {
          'name': _nextOfKinNameController.text.trim(),
          'phone': _nextOfKinPhoneController.text.trim(),
          'relationship': _nextOfKinRelationshipController.text.trim(),
          'occupation': _nextOfKinOccupationController.text.trim(),
        },
      );

      setState(() {
        _isSubmitting = false;
      });

      if (result['success']) {
        setState(() {
          _showSuccess = true;
          _applicationId = result['applicationId'];
        });
      } else {
        String errorMessage = result['message'] ?? 'Failed to submit loan application';

        if (result['errors'] != null) {
          final errors = result['errors'] as Map<String, dynamic>;
          final errorMessages = <String>[];
          errors.forEach((key, value) {
            if (value is List) {
              errorMessages.add('$key: ${value.join(', ')}');
            } else {
              errorMessages.add('$key: $value');
            }
          });
          errorMessage = errorMessages.join('; ');
        }

        setState(() {
          _errorMessage = errorMessage;
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }
}