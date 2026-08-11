// screens/paystack_webview_screen.dart

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class PaystackWebViewScreen extends StatefulWidget {
  final String checkoutUrl;
  final String reference;
  final VoidCallback onPaymentSuccess;
  final VoidCallback onPaymentCancel;

  const PaystackWebViewScreen({
    Key? key,
    required this.checkoutUrl,
    required this.reference,
    required this.onPaymentSuccess,
    required this.onPaymentCancel,
  }) : super(key: key);

  @override
  State<PaystackWebViewScreen> createState() => _PaystackWebViewScreenState();
}

class _PaystackWebViewScreenState extends State<PaystackWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _isError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    print('🔗 Initializing WebView with URL: ${widget.checkoutUrl}');

    // Create the WebViewController
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            print('🔄 Loading progress: $progress%');
            if (progress == 100) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            }
          },
          onPageStarted: (String url) {
            print('📄 Page started: $url');
            if (mounted) {
              setState(() {
                _isLoading = true;
                _isError = false;
              });
            }
          },
          onPageFinished: (String url) {
            print('✅ Page finished: $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              _checkUrlStatus(url);
            }
          },
          onWebResourceError: (WebResourceError error) {
            print('❌ WebView error: ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _isError = true;
                _errorMessage = error.description;
              });
            }
          },
          onUrlChange: (UrlChange change) {
            print('🔗 URL changed to: ${change.url}');
            if (change.url != null) {
              _checkUrlStatus(change.url!);
            }
          },
        ),
      );

    // Android specific settings - removed problematic methods
    if (_controller.platform is AndroidWebViewController) {
      // Enable debugging for Android (optional)
      // Note: This method might not be available in all versions
      try {
        // @ts-ignore - ignore if not available
        AndroidWebViewController.enableDebugging(true);
      } catch (e) {
        print('⚠️ Could not enable debugging: $e');
      }
    }

    // Load the URL
    _loadUrl();
  }

  void _loadUrl() {
    try {
      final uri = Uri.parse(widget.checkoutUrl);
      print('🌐 Loading URL: $uri');
      _controller.loadRequest(uri);
    } catch (e) {
      print('❌ Error loading URL: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isError = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _checkUrlStatus(String url) {
    final lowerUrl = url.toLowerCase();
    print('🔍 Checking URL: $lowerUrl');

    // Check for success indicators
    if (lowerUrl.contains('success') ||
        lowerUrl.contains('approved') ||
        lowerUrl.contains('trxref=success') ||
        (lowerUrl.contains('reference') && lowerUrl.contains('status=success'))) {
      _handlePaymentSuccess();
    }
    // Check for cancel indicators
    else if (lowerUrl.contains('cancel') ||
        lowerUrl.contains('cancelled') ||
        lowerUrl.contains('status=cancel') ||
        lowerUrl.contains('trxref=cancel')) {
      _handlePaymentCancel();
    }
  }

  void _handlePaymentSuccess() {
    if (_isLoading) return;

    print('✅ Payment successful!');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment completed successfully!'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context);
        widget.onPaymentSuccess();
      }
    });
  }

  void _handlePaymentCancel() {
    if (_isLoading) return;

    print('❌ Payment cancelled');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment was cancelled'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context);
        widget.onPaymentCancel();
      }
    });
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isError = false;
        _errorMessage = null;
      });
      _loadUrl();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay with Paystack'),
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        elevation: 0,
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
                    child: const Text('Continue Payment'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (mounted) {
                        Navigator.pop(context);
                        widget.onPaymentCancel();
                      }
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
            onPressed: _reload,
          ),
        ],
      ),
      body: _isError
          ? _buildErrorView()
          : Stack(
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
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load payment page',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error occurred',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onPaymentCancel();
              },
              child: const Text('Cancel Payment'),
            ),
          ],
        ),
      ),
    );
  }
}