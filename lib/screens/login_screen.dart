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

void main() => runApp(const EduCatApp());

class EduCatApp extends StatelessWidget {
  const EduCatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EduCat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF8C00)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _rememberMe = false;
  bool _rememberSchool = true;

  final _schoolRegController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late SessionManager _sessionManager;
  late ApiService _apiService;

  static const Color kOrange = Color(0xFFF7941D);
  static const Color kNavy = Color(0xFF1A2340);
  static const Color kLightOrange = Color(0xFFFFF3E8);
  static const Color kBorder = Color(0xFFE8E8E8);
  static const Color kTextGrey = Color(0xFF999999);
  static const Color kBackground = Color(0xFFFAF8F5);

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadSavedData();
  }

  @override
  void dispose() {
    _schoolRegController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionManager = SessionManager(prefs);

    final savedSchoolReg = _sessionManager.getSavedSchoolRegNo();
    if (savedSchoolReg != null && savedSchoolReg.isNotEmpty) {
      _schoolRegController.text = savedSchoolReg;
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
        _schoolRegController.text.trim(),
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
        schoolRegistrationNumber: _schoolRegController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (success && mounted) {
        final user = authProvider.currentUser;
        final authToken = authProvider.token!;
        final userRole = user?.role ?? '';

        await _registerFcmToken(user!, authToken);

        if (userRole == 'SchoolAdmin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminDashboard()),
          );
        } else if (userRole == 'Teacher') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => TeacherDashboard(user: user)),
          );
        } else if (userRole == 'Guardian') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const GuardianDashboard()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Unknown user role: $userRole. Please contact support.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else if (mounted && authProvider.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage!),
            backgroundColor: Colors.red,
          ),
        );
      }

      setState(() {
        _isLoading = false;
      });
    }
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
              _schoolRegController.clear();
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
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Stack(
        children: [
          // Background school illustration (top-right)
          Positioned(
            top: 0,
            right: -20,
            child: _buildSchoolIllustration(),
          ),
          // Wave at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomWave(),
          ),
          SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      _buildLogo(),
                      const SizedBox(height: 40),
                      _buildWelcomeHeader(),
                      const SizedBox(height: 28),
                      _buildInputField(
                        icon: Icons.account_balance,
                        label: 'School Registration Number',
                        hint: 'Enter your school registration number',
                        controller: _schoolRegController,
                        validator: _validateSchoolRegNo,
                        textCapitalization: TextCapitalization.characters,
                      ),
                      const SizedBox(height: 16),
                      _buildInputField(
                        icon: Icons.mail_outline,
                        label: 'Email Address',
                        hint: 'Enter your email address',
                        controller: _emailController,
                        validator: _validateEmail,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),
                      _buildPasswordField(),
                      const SizedBox(height: 12),
                      _buildForgotPassword(),
                      const SizedBox(height: 12),
                      _buildRememberMe(),
                      const SizedBox(height: 24),
                      _buildSignInButton(),
                      const SizedBox(height: 24),
                      _buildSecurityCard(),
                      const SizedBox(height: 24),
                      _buildSignUpRow(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo Image
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/educatlogo.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(
                  Icons.school_rounded,
                  size: 40,
                  color: kOrange,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'Edu',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: kNavy,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'Cat',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: kOrange,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Empowering Schools.\nTransforming Lives.',
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF555555),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        Container(width: 32, height: 3, color: kOrange),
      ],
    );
  }

  Widget _buildWelcomeHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'Welcome Back!',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: kNavy,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Sign in to access your EduCat account',
          style: TextStyle(fontSize: 14, color: Color(0xFF777777)),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required IconData icon,
    required String label,
    required String hint,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kLightOrange,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: kOrange, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextFormField(
              controller: controller,
              validator: validator,
              keyboardType: keyboardType,
              textCapitalization: textCapitalization,
              style: const TextStyle(fontSize: 14, color: kNavy),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF888888),
                  fontWeight: FontWeight.w500,
                ),
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: kTextGrey,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                errorStyle: const TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: kLightOrange,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.lock_outline, color: kOrange, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              validator: _validatePassword,
              style: const TextStyle(fontSize: 14, color: kNavy),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF888888),
                  fontWeight: FontWeight.w500,
                ),
                hintText: 'Enter your password',
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: kTextGrey,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                errorStyle: const TextStyle(
                  fontSize: 11,
                  color: Colors.red,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: kTextGrey,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRememberMe() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Transform.scale(
              scale: 0.9,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (value) => setState(() => _rememberMe = value ?? false),
                activeColor: kOrange,
                checkColor: Colors.white,
                side: const BorderSide(color: kBorder, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const Text(
              'Remember me',
              style: TextStyle(
                color: Color(0xFF555555),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Transform.scale(
              scale: 0.9,
              child: Checkbox(
                value: _rememberSchool,
                onChanged: (value) => setState(() => _rememberSchool = value ?? true),
                activeColor: kOrange,
                checkColor: Colors.white,
                side: const BorderSide(color: kBorder, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
            const Text(
              'Remember school',
              style: TextStyle(
                color: Color(0xFF555555),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildForgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: _showForgotPasswordDialog,
        child: const Text(
          'Forgot Password?',
          style: TextStyle(
            color: kOrange,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: authProvider.isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: kOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
              shadowColor: kOrange.withOpacity(0.4),
            ),
            child: authProvider.isLoading || _isLoading
                ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  'Sign In',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(width: 10),
                Icon(Icons.arrow_forward, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSecurityCard() {
    final hasSavedCredentials = _schoolRegController.text.isNotEmpty ||
        _emailController.text.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: kLightOrange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.verified_user_outlined,
                        color: kOrange,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Secure. Reliable. Built for Schools.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: kNavy,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your data is protected with industry-standard security so you can focus on what matters most.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF777777),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _buildBackpackIllustration(),
            ],
          ),
          if (hasSavedCredentials) ...[
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: kTextGrey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _buildSavedInfoText(),
                    style: TextStyle(
                      color: kTextGrey,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: _clearSavedData,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      color: Colors.red[400],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _buildSavedInfoText() {
    List<String> saved = [];
    if (_schoolRegController.text.isNotEmpty) {
      saved.add('School: ${_schoolRegController.text}');
    }
    if (_emailController.text.isNotEmpty) {
      saved.add('Email: ${_emailController.text}');
    }
    return saved.join(' | ');
  }

  Widget _buildBackpackIllustration() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: kLightOrange,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.backpack,
        color: kNavy,
        size: 42,
      ),
    );
  }

  Widget _buildSignUpRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: kLightOrange,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_outline, color: kOrange, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Don't have an account?",
              style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
            ),
            GestureDetector(
              onTap: _showForgotPasswordDialog,
              child: const Text(
                'Contact your school administrator.',
                style: TextStyle(
                  fontSize: 13,
                  color: kOrange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSchoolIllustration() {
    return Opacity(
      opacity: 0.15,
      child: Container(
        width: 180,
        height: 200,
        child: const Icon(
          Icons.account_balance,
          size: 160,
          color: Color(0xFFF7941D),
        ),
      ),
    );
  }

  Widget _buildBottomWave() {
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        height: 80,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF7941D), Color(0xFFFFB347)],
          ),
        ),
      ),
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.quadraticBezierTo(
      size.width * 0.25, 0,
      size.width * 0.5, size.height * 0.3,
    );
    path.quadraticBezierTo(
      size.width * 0.75, size.height * 0.6,
      size.width, size.height * 0.2,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) => false;
}

class _BookPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE07B00)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(size.width / 2, 4)
      ..lineTo(size.width, 12)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width / 2, size.height - 4)
      ..close();
    canvas.drawPath(path, paint);

    final path2 = Path()
      ..moveTo(size.width / 2, 4)
      ..lineTo(0, 12)
      ..lineTo(0, size.height)
      ..lineTo(size.width / 2, size.height - 4)
      ..close();
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(_BookPainter oldDelegate) => false;
}