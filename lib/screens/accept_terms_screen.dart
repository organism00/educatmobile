import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../utils/app_colors.dart';
import 'setup_mandate_screen.dart';

class AcceptTermsScreen extends StatefulWidget {
  final String applicationId;

  const AcceptTermsScreen({
    super.key,
    required this.applicationId,
  });

  @override
  State<AcceptTermsScreen> createState() => _AcceptTermsScreenState();
}

class _AcceptTermsScreenState extends State<AcceptTermsScreen> {
  final ApiService _apiService = ApiService();

  bool _isSubmitting = false;
  bool _termsAccepted = false;
  bool _scrolledToBottom = false;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50) {
      if (!_scrolledToBottom) {
        setState(() {
          _scrolledToBottom = true;
        });
      }
    }
  }

  Future<void> _acceptTerms() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;

    if (token == null) {
      setState(() {
        _errorMessage = 'Authentication error. Please login again.';
      });
      return;
    }

    if (!_termsAccepted) {
      setState(() {
        _errorMessage = 'Please check the box to accept the terms.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await _apiService.acceptLoanTerms(
        token: token,
        applicationId: widget.applicationId,
      );

      setState(() {
        _isSubmitting = false;
      });

      if (result['success']) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Terms accepted successfully!'),
            backgroundColor: AppColors.success,
          ),
        );

        // Navigate to mandate setup
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SetupMandateScreen(
              applicationId: widget.applicationId,
            ),
          ),
        );
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to accept terms';
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Accept Loan Terms'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: AppColors.background,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(isSmallScreen),
                      const SizedBox(height: 24),
                      _buildTermsCard(isSmallScreen),
                      const SizedBox(height: 16),
                      if (_errorMessage != null) _buildErrorWidget(),
                      _buildAcceptCheckbox(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.description,
                color: AppColors.primary,
                size: isSmallScreen ? 24 : 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Loan Terms & Conditions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Application ID: ${widget.applicationId.length > 8 ? widget.applicationId.substring(0, 8) : widget.applicationId}',
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
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Please read the terms carefully before accepting.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTermsCard(bool isSmallScreen) {
    return Container(
      padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.greyLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'LOAN AGREEMENT TERMS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          _buildTermSection(
            number: '1',
            title: 'Loan Amount & Disbursement',
            content: 'The approved loan amount will be disbursed directly to the school '
                'on behalf of the student for educational purposes only. Funds will be '
                'credited to the school\'s account within 24-48 hours after mandate setup.',
          ),
          _buildTermSection(
            number: '2',
            title: 'Repayment Obligation',
            content: 'The guardian agrees to repay the loan amount in full according to '
                'the selected repayment tenure. Repayment will be made through direct '
                'debit from the registered bank account. Late payments may attract '
                'additional charges.',
          ),
          _buildTermSection(
            number: '3',
            title: 'Direct Debit Authorization',
            content: 'By accepting these terms, you authorize the lender to set up a '
                'direct debit mandate on your bank account. You agree to maintain '
                'sufficient funds in the account to cover the scheduled repayments.',
          ),
          _buildTermSection(
            number: '4',
            title: 'Interest & Charges',
            content: 'The loan attracts interest as calculated during the credit '
                'assessment. All applicable fees and charges are disclosed in the '
                'loan offer and are binding upon acceptance.',
          ),
          _buildTermSection(
            number: '5',
            title: 'Default & Consequences',
            content: 'Failure to repay the loan may result in: (a) additional late fees, '
                '(b) reporting to credit bureaus, (c) legal action to recover the debt, '
                'and (d) restriction on future loan applications.',
          ),
          _buildTermSection(
            number: '6',
            title: 'Data Usage & Privacy',
            content: 'Your personal and financial information will be used strictly for '
                'loan processing and recovery purposes. Data will be handled in '
                'accordance with applicable data protection laws.',
          ),
          _buildTermSection(
            number: '7',
            title: 'Right to Cancel',
            content: 'You have the right to cancel this agreement within 24 hours of '
                'acceptance by contacting the lender. After this period, cancellation '
                'may be subject to penalties.',
          ),
          _buildTermSection(
            number: '8',
            title: 'Governing Law',
            content: 'This agreement shall be governed by the laws of the Federal '
                'Republic of Nigeria. Any disputes shall be resolved through '
                'arbitration or the appropriate courts.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'By accepting, you agree to all terms and conditions outlined above.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermSection({
    required String number,
    required String title,
    required String content,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Text(
              content,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
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

  Widget _buildAcceptCheckbox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _termsAccepted ? AppColors.success : AppColors.grey,
          width: _termsAccepted ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _termsAccepted,
            onChanged: (value) {
              setState(() {
                _termsAccepted = value ?? false;
                if (_termsAccepted) {
                  _errorMessage = null;
                }
              });
            },
            activeColor: AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _termsAccepted = !_termsAccepted;
                  if (_termsAccepted) {
                    _errorMessage = null;
                  }
                });
              },
              child: const Text(
                'I have read and agree to the loan terms and conditions',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_isSubmitting || !_termsAccepted) ? null : _acceptTerms,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.grey,
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
              Text('Accepting Terms...'),
            ],
          )
              : const Text(
            'Accept & Continue',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}