// models/user_model.dart
import 'dart:convert';

class UserModel {
  final String id;
  final String email;
  final String role;
  final String schoolName;
  final String schoolReg;
  final String schoolId;              // ← internal SCRM school UUID
  final String edubanclSchoolId;      // ← 🆕 Edubanc's school UUID
  final String sessionId;
  final String sessionKey;
  final String term;
  final String termId;
  final String token;
  String name;
  String? phone;
  String? address;
  String? firstName;
  String? lastName;
  String? dateOfBirth;
  String? employmentDate;

  // Additional useful properties
  String? profileImage;
  String? deviceId;
  String? fcmToken;

  UserModel({
    required this.id,
    required this.email,
    required this.role,
    required this.schoolName,
    required this.schoolReg,
    required this.schoolId,
    this.edubanclSchoolId = '',      // 🆕 default empty for backwards compatibility
    required this.sessionId,
    required this.sessionKey,
    required this.term,
    required this.termId,
    required this.token,
    required this.name,
    this.phone,
    this.address,
    this.firstName,
    this.lastName,
    this.dateOfBirth,
    this.employmentDate,
    this.profileImage,
    this.deviceId,
    this.fcmToken,
  });

  // Factory method to create UserModel from JWT token
  factory UserModel.fromJwtToken(Map<String, dynamic> payload, String token) {
    return UserModel(
      id: payload['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ??
          payload['nameidentifier'] ??
          payload['sub'] ?? '',
      email: payload['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'] ??
          payload['email'] ?? '',
      role: payload['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ??
          payload['role'] ?? '',
      schoolName: payload['schoolName'] ?? '',
      schoolReg: payload['schoolReg'] ?? '',
      schoolId: payload['schoolId'] ?? '',
      // 🆕 Try multiple possible field names from the JWT
      edubanclSchoolId: payload['edubanclSchoolId'] ??
          payload['edubancSchoolId'] ??
          payload['edubanc_id'] ??
          payload['edubanclSchoolId'] ??
          '',
      sessionId: payload['sessionId'] ?? '',
      sessionKey: payload['sessionKey'] ?? '',
      term: payload['term'] ?? '',
      termId: payload['termId'] ?? '',
      token: token,
      name: payload['name'] ?? payload['unique_name'] ?? '',
    );
  }

  // Factory method to create UserModel from Guardian data
  factory UserModel.fromGuardianData(Map<String, dynamic> data, UserModel jwtUser) {
    final firstName = data['firstname'] ?? '';
    final lastName = data['lastname'] ?? '';
    final fullName = '$firstName $lastName'.trim();

    return UserModel(
      id: jwtUser.id,
      email: jwtUser.email,
      role: jwtUser.role,
      schoolName: jwtUser.schoolName,
      schoolReg: jwtUser.schoolReg,
      schoolId: jwtUser.schoolId,
      edubanclSchoolId: jwtUser.edubanclSchoolId,  // 🆕 preserve from JWT
      sessionId: jwtUser.sessionId,
      sessionKey: jwtUser.sessionKey,
      term: jwtUser.term,
      termId: jwtUser.termId,
      token: jwtUser.token,
      name: fullName.isNotEmpty ? fullName : jwtUser.email.split('@').first,
      phone: data['phone'],
      address: data['homeAddress'] ?? data['address'],
      firstName: firstName,
      lastName: lastName,
      profileImage: data['imagePath'],
    );
  }

  // Factory method to create UserModel from Teacher data
  factory UserModel.fromTeacherData(Map<String, dynamic> data, UserModel jwtUser) {
    final firstName = data['firstname'] ?? '';
    final lastName = data['lastname'] ?? '';
    final fullName = '$firstName $lastName'.trim();

    return UserModel(
      id: jwtUser.id,
      email: jwtUser.email,
      role: jwtUser.role,
      schoolName: jwtUser.schoolName,
      schoolReg: jwtUser.schoolReg,
      schoolId: jwtUser.schoolId,
      edubanclSchoolId: jwtUser.edubanclSchoolId,
      sessionId: jwtUser.sessionId,
      sessionKey: jwtUser.sessionKey,
      term: jwtUser.term,
      termId: jwtUser.termId,
      token: jwtUser.token,
      name: fullName.isNotEmpty ? fullName : jwtUser.email.split('@').first,
      phone: data['phone'],
      address: data['homeAddress'],
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: data['dateOfBirth'],
      employmentDate: data['employmentDate'],
      profileImage: data['imagePath'],
    );
  }

  // Factory method to create UserModel from Student data
  factory UserModel.fromStudentData(Map<String, dynamic> data, UserModel jwtUser) {
    final firstName = data['firstname'] ?? '';
    final lastName = data['lastname'] ?? '';
    final fullName = '$firstName $lastName'.trim();

    return UserModel(
      id: jwtUser.id,
      email: jwtUser.email,
      role: jwtUser.role,
      schoolName: jwtUser.schoolName,
      schoolReg: jwtUser.schoolReg,
      schoolId: jwtUser.schoolId,
      edubanclSchoolId: jwtUser.edubanclSchoolId,
      sessionId: jwtUser.sessionId,
      sessionKey: jwtUser.sessionKey,
      term: jwtUser.term,
      termId: jwtUser.termId,
      token: jwtUser.token,
      name: fullName.isNotEmpty ? fullName : jwtUser.email.split('@').first,
      phone: data['phone'],
      address: data['homeAddress'],
      firstName: firstName,
      lastName: lastName,
      dateOfBirth: data['dateOfBirth'],
      profileImage: data['imagePath'],
    );
  }

  // Factory method to create UserModel from JSON
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      schoolName: json['schoolName'] ?? '',
      schoolReg: json['schoolReg'] ?? '',
      schoolId: json['schoolId'] ?? '',
      // 🆕 Look for edubanc1SchoolId in JSON (with fallbacks for possible API naming)
      edubanclSchoolId: json['edubanclSchoolId'] ??
          json['edubancSchoolId'] ??
          json['edubanc_id'] ??
          '',
      sessionId: json['sessionId'] ?? '',
      sessionKey: json['sessionKey'] ?? '',
      term: json['term'] ?? '',
      termId: json['termId'] ?? '',
      token: json['token'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'],
      address: json['address'],
      firstName: json['firstName'],
      lastName: json['lastName'],
      dateOfBirth: json['dateOfBirth'],
      employmentDate: json['employmentDate'],
      profileImage: json['profileImage'],
      deviceId: json['deviceId'],
      fcmToken: json['fcmToken'],
    );
  }

  // Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role,
      'schoolName': schoolName,
      'schoolReg': schoolReg,
      'schoolId': schoolId,
      'edubanclSchoolId': edubanclSchoolId,   // 🆕
      'sessionId': sessionId,
      'sessionKey': sessionKey,
      'term': term,
      'termId': termId,
      'token': token,
      'name': name,
      'phone': phone,
      'address': address,
      'firstName': firstName,
      'lastName': lastName,
      'dateOfBirth': dateOfBirth,
      'employmentDate': employmentDate,
      'profileImage': profileImage,
      'deviceId': deviceId,
      'fcmToken': fcmToken,
    };
  }

  // Copy with method for updating specific fields
  UserModel copyWith({
    String? id,
    String? email,
    String? role,
    String? schoolName,
    String? schoolReg,
    String? schoolId,
    String? edubanclSchoolId,           // 🆕
    String? sessionId,
    String? sessionKey,
    String? term,
    String? termId,
    String? token,
    String? name,
    String? phone,
    String? address,
    String? firstName,
    String? lastName,
    String? dateOfBirth,
    String? employmentDate,
    String? profileImage,
    String? deviceId,
    String? fcmToken,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      role: role ?? this.role,
      schoolName: schoolName ?? this.schoolName,
      schoolReg: schoolReg ?? this.schoolReg,
      schoolId: schoolId ?? this.schoolId,
      edubanclSchoolId: edubanclSchoolId ?? this.edubanclSchoolId,   // 🆕
      sessionId: sessionId ?? this.sessionId,
      sessionKey: sessionKey ?? this.sessionKey,
      term: term ?? this.term,
      termId: termId ?? this.termId,
      token: token ?? this.token,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      employmentDate: employmentDate ?? this.employmentDate,
      profileImage: profileImage ?? this.profileImage,
      deviceId: deviceId ?? this.deviceId,
      fcmToken: fcmToken ?? this.fcmToken,
    );
  }

  // Helper getters (unchanged)
  bool get isAdmin => role == 'SchoolAdmin' || role == 'Admin' || role == 'SuperAdmin';
  bool get isTeacher => role == 'Teacher';
  bool get isGuardian => role == 'Guardian';
  bool get isStudent => role == 'Student';
  bool get isSuperAdmin => role == 'SuperAdmin';

  String get fullName => name;
  String get initials {
    if (firstName != null && lastName != null) {
      return '${firstName![0]}${lastName![0]}'.toUpperCase();
    }
    if (name.isNotEmpty) {
      final parts = name.split(' ');
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return name.substring(0, 1).toUpperCase();
    }
    return email.substring(0, 1).toUpperCase();
  }

  String get displayName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return name.isNotEmpty ? name : email.split('@').first;
  }

  UserModel updateToken(String newToken) {
    return copyWith(token: newToken);
  }

  UserModel updateDeviceId(String deviceId) {
    return copyWith(deviceId: deviceId);
  }

  UserModel updateFcmToken(String fcmToken) {
    return copyWith(fcmToken: fcmToken);
  }

  // 🆕 Helper: check whether Edubanc school ID is set
  bool get hasEdubancSchoolId =>
      edubanclSchoolId.isNotEmpty &&
          edubanclSchoolId != '00000000-0000-0000-0000-000000000000';

  // 🆕 Helper: check whether internal school ID is set
  bool get hasInternalSchoolId =>
      schoolId.isNotEmpty &&
          schoolId != '00000000-0000-0000-0000-000000000000';

  bool hasPermission(String permission) {
    if (isSuperAdmin) return true;
    if (isAdmin) return true;
    if (isTeacher && permission.startsWith('teacher_')) return true;
    return false;
  }

  String get roleDisplayName {
    switch (role) {
      case 'SuperAdmin':
        return 'Super Admin';
      case 'SchoolAdmin':
        return 'School Admin';
      case 'Teacher':
        return 'Teacher';
      case 'Guardian':
        return 'Guardian';
      case 'Student':
        return 'Student';
      default:
        return role;
    }
  }

  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, email: $email, role: $role, '
        'schoolId: $schoolId, edubanclSchoolId: $edubanclSchoolId, '
        'school: $schoolName)';
  }
}