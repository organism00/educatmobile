import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_model.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/auth_provider.dart';
import '../widgets/message_list_tile.dart';
import '../utils/app_colors.dart';
import 'conversation_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late ApiService _apiService;
  late UserModel _currentUser;
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  // Cache for user names and details
  Map<String, Map<String, dynamic>> _userDetailsCache = {};

  // Responsive variables
  late bool _isMobile;
  late bool _isTablet;
  late bool _isDesktop;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadCurrentUser();
    _fetchMessages();
  }

  void _loadCurrentUser() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _currentUser = authProvider.currentUser!;
  }

  Future<Map<String, dynamic>?> _getUserDetails(String userId, String userRole) async {
    if (_userDetailsCache.containsKey(userId)) {
      return _userDetailsCache[userId];
    }

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) return null;

    final result = await _apiService.getUserDetails(
      token: token,
      userId: userId,
      userRole: userRole,
    );

    if (result['success'] && result['data'] != null) {
      final userData = result['data'];
      String name = '';

      switch (userRole.toLowerCase()) {
        case 'teacher':
          name = '${userData['firstname'] ?? ''} ${userData['lastname'] ?? ''}'.trim();
          break;
        case 'guardian':
          name = '${userData['firstname'] ?? ''} ${userData['lastname'] ?? ''}'.trim();
          break;
        case 'schooladmin':
          name = '${userData['firstname'] ?? ''} ${userData['lastname'] ?? ''}'.trim();
          break;
        default:
          name = userId;
      }

      if (name.isEmpty) name = userId;

      final userDetails = {
        'name': name,
        'email': userData['email'] ?? '',
        'phone': userData['phone'] ?? '',
      };

      _userDetailsCache[userId] = userDetails;
      return userDetails;
    }

    return {
      'name': userId,
      'email': '',
      'phone': '',
    };
  }

  // Format time for conversation list (shows like "2:30 PM", "Yesterday", "Mon", "15/05/2024")
  String _formatConversationTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays == 0) {
      // Today - show time
      return _formatTimeOnly(time);
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day name
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[time.weekday - 1];
    } else {
      // Older - show date
      return '${time.day}/${time.month}/${time.year}';
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

  Future<void> _fetchMessages() async {
    setState(() {
      _isLoading = true;
    });

    final token = Provider.of<AuthProvider>(context, listen: false).token;
    if (token == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final currentUserRole = _getUserRole();

    final result = await _apiService.getInboxMessages(
      token: token,
      userId: _currentUser.id,
      userRole: currentUserRole,
    );

    if (result['success'] && mounted) {
      final messagesData = result['data'] as List? ?? [];
      final messages = messagesData.map((m) => MessageModel.fromJson(m)).toList();

      // Group messages by conversation
      final Map<String, MessageModel> latestMessages = {};

      for (var message in messages) {
        final otherUserId = message.senderId == _currentUser.id
            ? message.receiverId
            : message.senderId;
        final otherUserRole = message.senderId == _currentUser.id
            ? message.receiverRole
            : message.senderRole;
        final conversationKey = '$otherUserId|$otherUserRole';

        if (!latestMessages.containsKey(conversationKey) ||
            message.sentAt.isAfter(latestMessages[conversationKey]!.sentAt)) {
          latestMessages[conversationKey] = message;
        }
      }

      final uniqueMessages = latestMessages.values.toList();
      uniqueMessages.sort((a, b) => b.sentAt.compareTo(a.sentAt));

      // Fetch details for each unique user
      List<Future> futures = [];
      for (var message in uniqueMessages) {
        final otherUserId = message.senderId == _currentUser.id
            ? message.receiverId
            : message.senderId;
        final otherUserRole = message.senderId == _currentUser.id
            ? message.receiverRole
            : message.senderRole;

        futures.add(_getUserDetails(otherUserId, otherUserRole).then((details) {
          if (details != null) {
            if (message.senderId == _currentUser.id) {
              message.receiverName = details['name'] as String?;
            } else {
              message.senderName = details['name'] as String?;
            }
          }
        }));
      }

      await Future.wait(futures);

      setState(() {
        _messages = uniqueMessages;
        _isLoading = false;
        _isRefreshing = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  String _getUserRole() {
    if (_currentUser.isAdmin) return 'SchoolAdmin';
    if (_currentUser.isTeacher) return 'Teacher';
    if (_currentUser.isGuardian) return 'Guardian';
    return 'Unknown';
  }

  String _getOtherUserName(MessageModel message) {
    if (message.senderId == _currentUser.id) {
      return message.receiverName ?? message.receiverId;
    } else {
      return message.senderName ?? message.senderId;
    }
  }

  String _getOtherUserRole(MessageModel message) {
    if (message.senderId == _currentUser.id) {
      return message.receiverRole;
    } else {
      return message.senderRole;
    }
  }

  String _getOtherUserId(MessageModel message) {
    if (message.senderId == _currentUser.id) {
      return message.receiverId;
    } else {
      return message.senderId;
    }
  }

  Future<void> _refreshMessages() async {
    setState(() {
      _isRefreshing = true;
    });
    await _fetchMessages();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    _isMobile = screenWidth < 600;
    _isTablet = screenWidth >= 600 && screenWidth < 1200;
    _isDesktop = screenWidth >= 1200;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Messages',
          style: TextStyle(
            fontSize: _isMobile ? 20 : 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.primary, size: _isMobile ? 20 : 24),
            onPressed: _refreshMessages,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshMessages,
        color: AppColors.primary,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _messages.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.inbox,
                size: _isMobile ? 48 : 64,
                color: AppColors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                'No messages yet',
                style: TextStyle(
                  fontSize: _isMobile ? 14 : 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Messages will appear here',
                style: TextStyle(
                  fontSize: _isMobile ? 12 : 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        )
            : ListView.builder(
          padding: EdgeInsets.all(_isMobile ? 12 : 16),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final message = _messages[index];
            final otherUserName = _getOtherUserName(message);
            final otherUserRole = _getOtherUserRole(message);
            final otherUserId = _getOtherUserId(message);
            final isUnread = !message.isRead && message.receiverId == _currentUser.id;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              child: MessageListTile(
                senderName: otherUserName,
                senderRole: otherUserRole,
                content: message.content,
                time: _formatConversationTime(message.sentAt), // Using new time formatter
                isRead: !isUnread,
                onTap: () async {
                  if (isUnread) {
                    final token = Provider.of<AuthProvider>(context, listen: false).token;
                    if (token != null) {
                      await _apiService.markMessageAsRead(
                        token: token,
                        messageId: message.messageId,
                      );
                    }
                  }

                  final userDetails = await _getUserDetails(otherUserId, otherUserRole);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConversationScreen(
                        userId: otherUserId,
                        userRole: otherUserRole,
                        userName: otherUserName,
                        userEmail: userDetails?['email'] as String?,
                        userPhone: userDetails?['phone'] as String?,
                      ),
                    ),
                  ).then((_) => _refreshMessages());
                },
              ),
            );
          },
        ),
      ),
    );
  }
}