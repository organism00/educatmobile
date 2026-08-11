// Create new file: screens/webview_wrapper.dart

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class WebViewWrapper extends StatefulWidget {
  final String url;
  final String title;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  const WebViewWrapper({
    Key? key,
    required this.url,
    required this.title,
    required this.onSuccess,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<WebViewWrapper> createState() => _WebViewWrapperState();
}

class _WebViewWrapperState extends State<WebViewWrapper> {
  late WebViewController _controller;
  bool _isLoading = true;
  bool _isError = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    print('🔗 Initializing WebView with URL: ${widget.url}');

    // Initialize the controller with platform-specific setup
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              if (mounted) setState(() => _isLoading = false);
            }
          },
          onPageStarted: (String url) {
            if (mounted) setState(() {
              _isLoading = true;
              _isError = false;
            });
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            _checkUrlStatus(url);
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) setState(() {
              _isLoading = false;
              _isError = true;
              _errorMessage = error.description;
            });
          },
          onUrlChange: (UrlChange change) {
            if (change.url != null) _checkUrlStatus(change.url!);
          },
        ),
      );

    // Try to load the URL
    try {
      final uri = Uri.parse(widget.url);
      _controller.loadRequest(uri);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _isError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _checkUrlStatus(String url) {
    final lowerUrl = url.toLowerCase();

    // Success indicators
    if (lowerUrl.contains('success') ||
        lowerUrl.contains('approved') ||
        lowerUrl.contains('trxref=success') ||
        lowerUrl.contains('status=success')) {
      _handleSuccess();
    }
    // Cancel indicators
    else if (lowerUrl.contains('cancel') ||
        lowerUrl.contains('cancelled') ||
        lowerUrl.contains('status=cancel') ||
        lowerUrl.contains('trxref=cancel')) {
      _handleCancel();
    }
  }

  void _handleSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment successful!'),
        backgroundColor: Colors.green,
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
      }
    });
  }

  void _handleCancel() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment cancelled'),
        backgroundColor: Colors.orange,
      ),
    );
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.pop(context);
        widget.onCancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
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
                content: const Text('Are you sure?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Continue'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (mounted) {
                        Navigator.pop(context);
                        widget.onCancel();
                      }
                    },
                    child: const Text('Cancel'),
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

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            const Text(
              'Failed to load page',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Unknown error',
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _isError = false;
                  _errorMessage = null;
                });
                _controller.reload();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B35),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onCancel();
              },
              child: const Text('Cancel Payment'),
            ),
          ],
        ),
      ),
    );
  }
}