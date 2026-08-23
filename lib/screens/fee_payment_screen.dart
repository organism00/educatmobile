// screens/fee_payment_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/auth_provider.dart';
import '../services/fee_provider.dart';
import '../utils/app_colors.dart';

class FeePaymentScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentClass;
  final String classroomId;
  final double originalFee;
  final String sessionId;

  const FeePaymentScreen({
    Key? key,
    required this.studentId,
    required this.studentName,
    required this.studentClass,
    required this.classroomId,
    required this.originalFee,
    required this.sessionId,
  }) : super(key: key);

  @override
  State<FeePaymentScreen> createState() => _FeePaymentScreenState();
}

class _FeePaymentScreenState extends State<FeePaymentScreen> {
  bool _isCalculating = true;
  String? _errorMessage;
  String _selectedGateway = 'paystack';
  final TextEditingController _emailController = TextEditingController();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _calculateDiscount();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _calculateDiscount() async {
    setState(() {
      _isCalculating = true;
      _errorMessage = null;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final feeProvider = Provider.of<FeeProvider>(context, listen: false);

    if (token == null) {
      setState(() {
        _errorMessage = 'Not authenticated';
        _isCalculating = false;
      });
      return;
    }

    final success = await feeProvider.calculateDiscountedFee(
      token: token,
      studentId: widget.studentId,
      originalFee: widget.originalFee,
    );

    if (!success && mounted) {
      setState(() {
        _errorMessage = feeProvider.errorMessage ?? 'Failed to calculate discount';
        _isCalculating = false;
      });
    } else if (mounted) {
      setState(() {
        _isCalculating = false;
      });
    }
  }

  Future<void> _initiatePayment() async {
    final token = Provider.of<AuthProvider>(context, listen: false).token;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final feeProvider = Provider.of<FeeProvider>(context, listen: false);
    final currentUser = authProvider.currentUser;

    if (token == null || currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not authenticated'), backgroundColor: AppColors.error),
      );
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email'), backgroundColor: AppColors.warning),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    final amountToPay = feeProvider.hasDiscount ? feeProvider.discountedFee : widget.originalFee;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );

    final success = await feeProvider.initiatePayment(
      token: token,
      studentId: widget.studentId,
      schoolId: currentUser.schoolId,
      guardianId: currentUser.id,
      amount: amountToPay,
      customerEmail: email,
      gateway: _selectedGateway,
      redirectUrl: 'https://educat.codeweb.com.ng/payment/callback',
      callbackUrl: 'https://educat.codeweb.com.ng/payment/webhook',
      classroomId: widget.classroomId,
    );

    if (mounted) {
      Navigator.pop(context);
    }

    setState(() {
      _isProcessing = false;
    });

    if (success && mounted && feeProvider.checkoutUrl != null) {
      final checkoutUrl = feeProvider.checkoutUrl!;
      print('🔗 Checkout URL: $checkoutUrl');
      await _launchPaymentUrlWithFallback(checkoutUrl);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feeProvider.errorMessage ?? 'Failed to initiate payment'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ==================== PAYMENT URL LAUNCHER WITH MULTIPLE FALLBACKS ====================

  Future<void> _launchPaymentUrlWithFallback(String url) async {
    // Method 1: Try launching with custom tabs (Chrome)
    bool launched = await _launchWithCustomTabs(url);
    if (launched) return;

    // Method 2: Try launching with external browser
    launched = await _launchWithBrowser(url);
    if (launched) return;

    // Method 3: Try launching with platform default
    launched = await _launchWithPlatformDefault(url);
    if (launched) return;

    // Method 4: Show dialog for manual copy-paste
    _showManualPaymentDialog(url);
  }

  Future<bool> _launchWithCustomTabs(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      // Check if URL can be launched
      if (await canLaunchUrl(uri)) {
        // Try with Chrome Custom Tabs
        final bool result = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (result) {
          print('✅ Payment page launched with Custom Tabs');
          _showSuccessMessage();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('❌ Custom Tabs launch failed: $e');
      return false;
    }
  }

  Future<bool> _launchWithBrowser(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      // Try with browser
      final bool result = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (result) {
        print('✅ Payment page launched with Browser');
        _showSuccessMessage();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Browser launch failed: $e');
      return false;
    }
  }

  Future<bool> _launchWithPlatformDefault(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      // Try with platform default
      final bool result = await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
      if (result) {
        print('✅ Payment page launched with Platform Default');
        _showSuccessMessage();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Platform Default launch failed: $e');
      return false;
    }
  }

  void _showSuccessMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment page opened! Please complete your payment.'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 3),
      ),
    );

    // Navigate back after a delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context, true);
      }
    });
  }

  void _showManualPaymentDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Open Payment Page'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 48, color: AppColors.warning),
            const SizedBox(height: 16),
            const Text(
              'We couldn\'t automatically open the payment page.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.greyLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Please copy the URL and open it in your browser manually.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // Copy URL to clipboard
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('URL copied to clipboard!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy URL'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // Try WebView as last resort
              _openInWebView(url);
            },
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open in App'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _openInWebView(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WebViewPaymentScreen(
          url: url,
          onSuccess: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment successful!'),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context, true);
          },
          onCancel: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Payment cancelled'),
                backgroundColor: Colors.orange,
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Fee Payment'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isCalculating
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Calculating your fee...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      )
          : _errorMessage != null
          ? _buildErrorView()
          : _buildPaymentForm(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppColors.error),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _calculateDiscount,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentForm() {
    final feeProvider = Provider.of<FeeProvider>(context);
    final isProcessing = feeProvider.isProcessingPayment || _isProcessing;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStudentInfoCard(),
          const SizedBox(height: 16),
          _buildFeeDetailsCard(feeProvider),
          const SizedBox(height: 16),
          _buildEmailInput(),
          const SizedBox(height: 16),
          _buildGatewaySelector(),
          const SizedBox(height: 24),
          _buildPayButton(feeProvider, isProcessing),
          if (feeProvider.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feeProvider.errorMessage!,
                      style: TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.info.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.security_rounded, color: AppColors.info, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You will be redirected to our secure payment gateway',
                    style: TextStyle(
                      color: AppColors.info,
                      fontSize: 12,
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

  Widget _buildStudentInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                widget.studentName.isNotEmpty ? widget.studentName[0].toUpperCase() : 'S',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Class: ${widget.studentClass}',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Session: ${widget.sessionId}',
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

  Widget _buildFeeDetailsCard(FeeProvider feeProvider) {
    final hasDiscount = feeProvider.hasDiscount;
    final originalFee = widget.originalFee;
    final discountedFee = feeProvider.discountedFee;
    final discountAmount = feeProvider.discountAmount;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasDiscount ? AppColors.success.withOpacity(0.3) : AppColors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fee Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          if (hasDiscount) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Original Fee:', style: TextStyle(color: AppColors.textSecondary)),
                Text(
                  '₦${originalFee.toStringAsFixed(2)}',
                  style: const TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Discount:', style: TextStyle(color: AppColors.success)),
                Text(
                  '-₦${discountAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Amount to Pay:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '₦${discountedFee.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.discount_rounded, size: 16, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text(
                    'You saved ₦${discountAmount.toStringAsFixed(2)}!',
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fee Amount:', style: TextStyle(color: AppColors.textSecondary)),
                Text(
                  '₦${originalFee.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: AppColors.info),
                  const SizedBox(width: 4),
                  const Text(
                    'No discount available',
                    style: TextStyle(
                      color: AppColors.info,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmailInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Details',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              labelText: 'Customer Email',
              hintText: 'Enter your email address',
              prefixIcon: Icon(Icons.email_outlined, color: AppColors.primary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.grey.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primary),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGatewaySelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Payment Gateway',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedGateway == 'paystack'
                          ? AppColors.primary
                          : AppColors.grey.withOpacity(0.3),
                    ),
                  ),
                  child: RadioListTile<String>(
                    title: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PAY',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Paystack',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Secure',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    value: 'paystack',
                    groupValue: _selectedGateway,
                    onChanged: (value) {
                      setState(() {
                        _selectedGateway = value!;
                      });
                    },
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPayButton(FeeProvider feeProvider, bool isProcessing) {
    final amount = feeProvider.hasDiscount ? feeProvider.discountedFee : widget.originalFee;

    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: isProcessing ? null : _initiatePayment,
        style: ElevatedButton.styleFrom(
          backgroundColor: isProcessing ? AppColors.primary.withOpacity(0.7) : AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: isProcessing ? 0 : 4,
          shadowColor: AppColors.primary.withOpacity(0.3),
        ),
        child: isProcessing
            ? Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Processing...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.open_in_browser_rounded, size: 20),
            const SizedBox(width: 10),
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                children: [
                  const TextSpan(text: 'Pay '),
                  TextSpan(
                    text: '₦${amount.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── WebView Payment Screen (Fallback) ──────────────────────────────────────

class WebViewPaymentScreen extends StatefulWidget {
  final String url;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  const WebViewPaymentScreen({
    Key? key,
    required this.url,
    required this.onSuccess,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<WebViewPaymentScreen> createState() => _WebViewPaymentScreenState();
}

class _WebViewPaymentScreenState extends State<WebViewPaymentScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            setState(() => _isLoading = false);
            if (url.contains('success') || url.contains('approved')) {
              widget.onSuccess();
            } else if (url.contains('cancel') || url.contains('cancelled')) {
              widget.onCancel();
            }
          },
          onUrlChange: (change) {
            if (change.url != null) {
              final url = change.url!;
              if (url.contains('success') || url.contains('approved')) {
                widget.onSuccess();
              } else if (url.contains('cancel') || url.contains('cancelled')) {
                widget.onCancel();
              }
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay with Paystack'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Cancel Payment'),
                content: const Text('Are you sure you want to cancel this payment?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Continue'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onCancel();
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _controller.reload();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading payment page...',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}