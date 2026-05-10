import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/auth_provider.dart';
import '../services/session_manager.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import '../utils/app_colors.dart';
import 'guardian_dashboard.dart';
import 'teacher_dashboard.dart';
import 'admin_dashboard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _schoolRegNoController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _rememberSchool = true;

  late SessionManager _sessionManager;
  late ApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadSavedData();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionManager = SessionManager(prefs);

    final savedSchoolReg = _sessionManager.getSavedSchoolRegNo();
    if (savedSchoolReg != null && savedSchoolReg.isNotEmpty) {
      _schoolRegNoController.text = savedSchoolReg;
      _rememberSchool = _sessionManager.getRememberSchool();
    }

    final savedEmail = _sessionManager.getSavedEmail();
    final savedPassword = _sessionManager.getSavedPassword();
    final rememberMe = _sessionManager.getRememberMe();

    if (rememberMe) {
      _rememberMe = true;
      if (savedEmail != null && savedEmail.isNotEmpty) {
        _emailController.text = savedEmail;
      }
      if (savedPassword != null && savedPassword.isNotEmpty) {
        _passwordController.text = savedPassword;
      }
    }

    setState(() {});
  }

  @override
  void dispose() {
    _schoolRegNoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _registerFcmToken(UserModel user, String authToken) async {
    try {
      final notificationService = NotificationService();
      final fcmToken = notificationService.fcmToken;

      if (fcmToken != null && fcmToken.isNotEmpty) {
        final userRole = user.isTeacher ? 'Teacher' : (user.isGuardian ? 'Guardian' : 'SchoolAdmin');

        await _apiService.saveFcmToken(
          token: authToken,
          userId: user.id,
          userRole: userRole,
          fcmToken: fcmToken,
        );

        // Subscribe to topics
        await notificationService.subscribeToTopic('all_users');
        await notificationService.subscribeToTopic(user.role.toLowerCase());
        await notificationService.subscribeToTopic('school_${user.schoolId}');

        print('✅ FCM Token registered successfully');
      }
    } catch (e) {
      print('❌ Error registering FCM token: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      await _sessionManager.saveSchoolRegNo(
        _schoolRegNoController.text.trim(),
        remember: _rememberSchool,
      );

      if (_rememberMe) {
        await _sessionManager.saveEmail(_emailController.text.trim(), remember: true);
        await _sessionManager.savePassword(_passwordController.text, remember: true);
        await _sessionManager.setRememberMe(true);
      } else {
        await _sessionManager.saveEmail('', remember: false);
        await _sessionManager.savePassword('', remember: false);
        await _sessionManager.setRememberMe(false);
      }

      final success = await authProvider.login(
        schoolRegistrationNumber: _schoolRegNoController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (success && mounted) {
        final user = authProvider.currentUser;
        final authToken = authProvider.token!;
        final userRole = user?.role ?? '';

        // Register FCM token for push notifications
        await _registerFcmToken(user!, authToken);

        print('User Role from JWT: $userRole');
        print('isAdmin: ${user.isAdmin}');
        print('isTeacher: ${user.isTeacher}');
        print('isGuardian: ${user.isGuardian}');

        // Route based on role
        if (userRole == 'SchoolAdmin') {
          print('Navigating to Admin Dashboard');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminDashboard()),
          );
        }
        else if (userRole == 'Teacher') {
          print('Navigating to Teacher Dashboard');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => TeacherDashboard(user: user)),
          );
        }
        else if (userRole == 'Guardian') {
          print('Navigating to Guardian Dashboard');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const GuardianDashboard()),
          );
        }
        else {
          print('Unknown role: $userRole');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unknown user role: $userRole. Please contact support.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      } else if (mounted && authProvider.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage!),
            backgroundColor: AppColors.error,
          ),
        );
      }

      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _validateSchoolRegNo(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter School Registration Number';
    }
    if (value.length < 4) {
      return 'School Registration Number must be at least 4 characters';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  void _clearSavedData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Saved Data'),
        content: const Text('Are you sure you want to clear all saved login information?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _sessionManager.clearSavedCredentials();
              _schoolRegNoController.clear();
              _emailController.clear();
              _passwordController.clear();
              setState(() {
                _rememberSchool = true;
                _rememberMe = false;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Saved login information cleared'),
                  backgroundColor: AppColors.success,
                ),
              );
            },
            child: const Text('Clear', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6B35), Color(0xFFF7931E), Color(0xFFFFB347)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Image.asset(
                          'assets/images/educat.png',
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.school, size: 60, color: Color(0xFFFF6B35)),
                          ),
                        ),
                      ),

                      const Text(
                        'EducatMobile',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Multi-School Management System',
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                      ),
                      const SizedBox(height: 40),

                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline, size: 16, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Login as: School Admin • Teacher • Guardian',
                              style: TextStyle(color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ),

                      if (_schoolRegNoController.text.isNotEmpty || _emailController.text.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _buildSavedInfoText(),
                                  style: const TextStyle(color: Colors.white, fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _clearSavedData,
                                child: const Icon(Icons.close, size: 16, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Container(
                              height: 55,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                              ),
                              child: TextFormField(
                                controller: _schoolRegNoController,
                                validator: _validateSchoolRegNo,
                                style: const TextStyle(color: Colors.black87, fontSize: 16),
                                textCapitalization: TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: 'School Registration Number',
                                  hintText: 'e.g., PS001',
                                  prefixIcon: const Icon(Icons.business, color: Color(0xFFFF6B35)),
                                  suffixIcon: _schoolRegNoController.text.isNotEmpty
                                      ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => _schoolRegNoController.clear(),
                                  )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            Container(
                              height: 55,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                              ),
                              child: TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                validator: _validateEmail,
                                style: const TextStyle(color: Colors.black87, fontSize: 16),
                                decoration: InputDecoration(
                                  labelText: 'Email Address',
                                  hintText: 'Enter your email',
                                  prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFFFF6B35)),
                                  suffixIcon: _emailController.text.isNotEmpty
                                      ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () => _emailController.clear(),
                                  )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            Container(
                              height: 55,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
                              ),
                              child: TextFormField(
                                controller: _passwordController,
                                obscureText: !_isPasswordVisible,
                                validator: _validatePassword,
                                style: const TextStyle(color: Colors.black87, fontSize: 16),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  hintText: 'Enter your password',
                                  prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFFFF6B35)),
                                  suffixIcon: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_passwordController.text.isNotEmpty)
                                        IconButton(
                                          icon: const Icon(Icons.clear, size: 18),
                                          onPressed: () => _passwordController.clear(),
                                        ),
                                      IconButton(
                                        icon: Icon(
                                          _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                                          color: Colors.grey,
                                        ),
                                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                                      ),
                                    ],
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _rememberSchool,
                                        onChanged: (value) => setState(() => _rememberSchool = value ?? true),
                                        activeColor: Colors.white,
                                        checkColor: const Color(0xFFFF6B35),
                                        side: const BorderSide(color: Colors.white),
                                      ),
                                      const Expanded(
                                        child: Text(
                                          'Remember my school',
                                          style: TextStyle(color: Colors.white, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: _rememberMe,
                                        onChanged: (value) => setState(() => _rememberMe = value ?? false),
                                        activeColor: Colors.white,
                                        checkColor: const Color(0xFFFF6B35),
                                        side: const BorderSide(color: Colors.white),
                                      ),
                                      const Expanded(
                                        child: Text(
                                          'Remember me (save email & password)',
                                          style: TextStyle(color: Colors.white, fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 8),

                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => _showForgotPasswordDialog(),
                                child: const Text('Forgot Password?', style: TextStyle(color: Colors.white)),
                              ),
                            ),

                            const SizedBox(height: 16),

                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: authProvider.isLoading ? null : _handleLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFFFF6B35),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                                child: authProvider.isLoading
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B35)),
                                  ),
                                )
                                    : const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildSavedInfoText() {
    List<String> saved = [];
    if (_schoolRegNoController.text.isNotEmpty) {
      saved.add('School: ${_schoolRegNoController.text}');
    }
    if (_emailController.text.isNotEmpty) {
      saved.add('Email: ${_emailController.text}');
    }
    return saved.join(' | ');
  }

  void _showForgotPasswordDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: const Text('Please contact your school administrator to reset your password.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}