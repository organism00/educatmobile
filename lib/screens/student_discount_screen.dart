// screens/student_discount_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/discount_model.dart';
import '../services/auth_provider.dart';
import '../services/discount_provider.dart';
import '../utils/app_colors.dart';

class StudentDiscountScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentClass;
  final String admissionNo;

  const StudentDiscountScreen({
    Key? key,
    required this.studentId,
    required this.studentName,
    required this.studentClass,
    required this.admissionNo,
  }) : super(key: key);

  @override
  State<StudentDiscountScreen> createState() => _StudentDiscountScreenState();
}

class _StudentDiscountScreenState extends State<StudentDiscountScreen> {
  bool _isLoading = true;
  List<DiscountModel> _discounts = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadDiscounts();
  }

  // screens/student_discount_screen.dart - Updated _loadDiscounts

  Future<void> _loadDiscounts() async {
    print('🔄 Loading discounts for student: ${widget.studentId}');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final token = Provider.of<AuthProvider>(context, listen: false).token;
      print('🔑 Token: ${token != null ? 'Present' : 'Missing'}');

      if (token == null) {
        setState(() {
          _errorMessage = 'Authentication required';
          _isLoading = false;
        });
        return;
      }

      final discountProvider = Provider.of<DiscountProvider>(context, listen: false);

      // Fetch discounts for this student
      print('📤 Calling fetchStudentDiscounts...');
      final success = await discountProvider.fetchStudentDiscounts(
        token: token,
        studentId: widget.studentId,
      );

      print('📥 Success: $success');

      if (success) {
        // Get the discounts for this student
        final studentDiscounts = discountProvider.getDiscountsForStudent(widget.studentId);
        print('📦 Retrieved ${studentDiscounts.length} discounts from provider');

        setState(() {
          _discounts = List.from(studentDiscounts); // Create a new list
          _isLoading = false;
        });

        if (_discounts.isEmpty) {
          print('ℹ️ No discounts found for student: ${widget.studentName}');
        } else {
          for (var discount in _discounts) {
            print('   ✅ ${discount.discountType}: ₦${discount.amount} (${discount.isValid ? 'Active' : 'Expired'})');
          }
        }
      } else {
        print('❌ Failed to load discounts');
        setState(() {
          _errorMessage = discountProvider.errorMessage ?? 'Failed to load discounts';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Exception: $e');
      setState(() {
        _errorMessage = 'Failed to load discounts: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Student Discounts'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _errorMessage != null
          ? _buildErrorView()
          : _buildDiscountsList(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: AppColors.error),
          const SizedBox(height: 16),
          Text(
            _errorMessage!,
            style: TextStyle(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadDiscounts,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountsList() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Student Info Card
          _buildStudentInfoCard(),
          const SizedBox(height: 24),

          // Discounts List
          if (_discounts.isEmpty)
            _buildEmptyState()
          else ...[
            const Text(
              'Applied Discounts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            ..._discounts.map((discount) => _buildDiscountCard(discount)),
          ],
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  widget.studentName.isNotEmpty ? widget.studentName[0].toUpperCase() : 'S',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
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
                    Text(
                      'Admission No: ${widget.admissionNo}',
                      style: TextStyle(
                        fontSize: 14,
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
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Discounts:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _discounts.isEmpty ? Colors.grey[200] : AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _discounts.isEmpty ? 'No Discounts' : '${_discounts.length} Discount${_discounts.length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _discounts.isEmpty ? Colors.grey[600] : AppColors.success,
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

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.discount_rounded,
            size: 64,
            color: AppColors.grey,
          ),
          const SizedBox(height: 12),
          const Text(
            'No Discounts Available',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.studentName} currently has no discounts applied.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDiscountCard(DiscountModel discount) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradientLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: discount.isValid ? AppColors.primary.withOpacity(0.3) : AppColors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: discount.isValid ? AppColors.primary.withOpacity(0.1) : AppColors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  discount.isValid ? Icons.check_circle : Icons.cancel,
                  color: discount.isValid ? AppColors.success : AppColors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      discount.discountType,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 14 : 16,
                        color: discount.isValid ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                    if (discount.description.isNotEmpty)
                      Text(
                        discount.description,
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: discount.statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  discount.statusText,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: discount.statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Display the discount amount - since there's no percentage, only show amount
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Discount Amount: ',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  discount.formattedAmount,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Show creation info if available
          if (discount.createdBy != null && discount.createdBy!.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.person, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Created by: ${discount.createdBy}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (discount.createdAt != null) ...[
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Applied on: ${_formatDate(discount.createdAt!)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          // Show session and term info if available
          if (discount.sessionId != null && discount.sessionId!.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.assessment, size: 12, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Session ID: ${discount.sessionId!.substring(0, 8)}...',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
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

  String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}