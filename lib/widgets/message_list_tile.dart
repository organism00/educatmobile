import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class MessageListTile extends StatelessWidget {
  final String senderName;
  final String senderRole;
  final String content;
  final String time;
  final bool isRead;
  final VoidCallback onTap;

  const MessageListTile({
    super.key,
    required this.senderName,
    required this.senderRole,
    required this.content,
    required this.time,
    required this.isRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 360;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : AppColors.primary.withOpacity(0.05),
          border: Border(
            bottom: BorderSide(color: AppColors.greyLight, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: isSmallScreen ? 45 : 50,
              height: isSmallScreen ? 45 : 50,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 18 : 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        senderName,
                        style: TextStyle(
                          fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          fontSize: isSmallScreen ? 14 : 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getRoleColor(senderRole).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          senderRole,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: _getRoleColor(senderRole),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    content,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                      fontSize: isSmallScreen ? 12 : 13,
                      color: isRead ? AppColors.textSecondary : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                if (!isRead)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'schooladmin':
        return AppColors.primary;
      case 'teacher':
        return AppColors.info;
      case 'guardian':
        return AppColors.success;
      default:
        return AppColors.grey;
    }
  }
}