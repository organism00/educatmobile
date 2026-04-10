import 'dart:convert';

class UserModel {
  final String id;
  final String email;
  final String role;
  final String schoolName;
  final String schoolReg;
  final String schoolId;
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

  UserModel({
    required this.id,
    required this.email,
    required this.role,
    required this.schoolName,
    required this.schoolReg,
    required this.schoolId,
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
    this.employmentDate
  });

  factory UserModel.fromJwtToken(Map<String, dynamic> payload, String token) {
    return UserModel(
      id: payload['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier'] ?? '',
      email: payload['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'] ?? '',
      role: payload['http://schemas.microsoft.com/ws/2008/06/identity/claims/role'] ?? '',
      schoolName: payload['schoolName'] ?? '',
      schoolReg: payload['schoolReg'] ?? '',
      schoolId: payload['schoolId'] ?? '',
      sessionId: payload['sessionId'] ?? '',
      sessionKey: payload['sessionKey'] ?? '',
      term: payload['term'] ?? '',
      termId: payload['termId'] ?? '',
      token: token,
      name: '', // Will be updated from API
    );
  }

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
      sessionId: jwtUser.sessionId,
      sessionKey: jwtUser.sessionKey,
      term: jwtUser.term,
      termId: jwtUser.termId,
      token: jwtUser.token,
      name: fullName.isNotEmpty ? fullName : jwtUser.email.split('@').first,
      phone: data['phone'],
      address: data['homeAddress'] ?? data['address'],
      firstName: firstName,
      lastName: lastName
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'role': role,
      'schoolName': schoolName,
      'schoolReg': schoolReg,
      'schoolId': schoolId,
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
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      schoolName: json['schoolName'] ?? '',
      schoolReg: json['schoolReg'] ?? '',
      schoolId: json['schoolId'] ?? '',
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
    );
  }

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
    );
  }

  bool get isAdmin => role == 'SchoolAdmin';
  bool get isTeacher => role == 'Teacher';
  bool get isGuardian => role == 'Guardian';
}