import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../widgets/message_bubble.dart';
import '../utils/app_colors.dart';

class ConversationScreen extends StatefulWidget {
  final String userId;
  final String userRole;
  final String userName;
  final String? userEmail;
  final String? userPhone;

  const ConversationScreen({
    super.key,
    required this.userId,
    required this.userRole,
    required this.userName,
    this.userEmail,
    this.userPhone,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late ApiService _apiService;
  late UserModel _currentUser;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadCurrentUser();
    _fetchConversation();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadCurrentUser() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUser = authProvider.currentUser!;
  }

  Future<void> _fetchConversation() async {
    setState(() {
      _isLoading = true;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return;

    final currentUserRole = _getUserRole();

    final result = await _apiService.getConversation(
      token: token,
      user1Id: _currentUser.id,
      user1Role: currentUserRole,
      user2Id: widget.userId,
      user2Role: widget.userRole,
    );

    if (result['success'] && mounted) {
      final messagesData = result['data'] as List? ?? [];
      setState(() {
        _messages = messagesData.map((m) => MessageModel.fromJson(m)).toList();
        _isLoading = false;
      });

      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isSending = true;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) {
      setState(() {
        _isSending = false;
      });
      return;
    }

    final currentUserRole = _getUserRole();

    final result = await _apiService.sendMessage(
      token: token,
      senderId: _currentUser.id,
      senderRole: currentUserRole,
      receiverId: widget.userId,
      receiverRole: widget.userRole,
      content: content,
    );

    if (result['success'] && mounted) {
      _messageController.clear();
      await _fetchConversation();

      // Also try to send a push notification via backend
      // The backend should handle sending the actual push notification
      // This is just a marker that a message was sent
      print('✅ Message sent successfully - Push notification will be sent by backend');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Failed to send message'),
          backgroundColor: AppColors.error,
        ),
      );
    }

    setState(() {
      _isSending = false;
    });
  }

  String _getUserRole() {
    if (_currentUser.isAdmin) return 'SchoolAdmin';
    if (_currentUser.isTeacher) return 'Teacher';
    if (_currentUser.isGuardian) return 'Guardian';
    return 'Unknown';
  }

  // Format time for message bubbles
  String _formatMessageTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    // For messages from today - show time like "2:30 PM"
    if (difference.inDays == 0) {
      return _formatTimeOnly(time);
    }
    // For yesterday
    else if (difference.inDays == 1) {
      return 'Yesterday ${_formatTimeOnly(time)}';
    }
    // For messages within the last 7 days
    else if (difference.inDays < 7) {
      const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return '${weekdays[time.weekday - 1]} ${_formatTimeOnly(time)}';
    }
    // For older messages
    else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${time.day} ${months[time.month - 1]}, ${time.year}';
    }
  }

  // Format time only (e.g., "2:30 PM")
  String _formatTimeOnly(DateTime time) {
    final localTime = time.toLocal();
    int hour = localTime.hour;
    final minute = localTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';

    if (hour == 0) {
      hour = 12;
    } else if (hour > 12) {
      hour = hour - 12;
    }

    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 360;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.userName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (widget.userEmail != null)
              Text(
                widget.userEmail!,
                style: const TextStyle(fontSize: 11),
              ),
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withOpacity(0.05),
              AppColors.background,
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _messages.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: AppColors.grey,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No messages yet',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Send a message to start the conversation',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.symmetric(
                  vertical: isSmallScreen ? 8 : 12,
                  horizontal: isSmallScreen ? 8 : 12,
                ),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isMe = message.senderId == _currentUser.id;
                  final senderName = isMe ? 'Me' : widget.userName;

                  return MessageBubble(
                    message: message.content,
                    isMe: isMe,
                    senderName: senderName,
                    time: _formatMessageTime(message.sentAt), // Using new time formatter
                    isRead: message.isRead,
                  );
                },
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmallScreen ? 12 : 16,
                vertical: isSmallScreen ? 8 : 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.greyLight,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        maxLines: null,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(
                            fontSize: isSmallScreen ? 13 : 14,
                            color: AppColors.textSecondary,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: isSmallScreen ? 10 : 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _isSending
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.send, color: Colors.white),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
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