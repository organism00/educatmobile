import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../utils/jwt_decoder.dart';

class ApiService {
  //static const String baseUrl = 'https://educat.codeweb.com.ng/api';
  static const String baseUrl = 'https://scrmapi-lpkm.onrender.com/api';
  static const String loginEndpoint = '/Login/Login';
  static const Duration timeout = Duration(seconds: 30);

  // ==================== AUTHENTICATION ====================

  Future<Map<String, dynamic>> login({
    required String schoolRegistrationNumber,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$loginEndpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'schoolRegistrationNumber': schoolRegistrationNumber,  // Note: field name might need to be 'schoolReg'
          'email': email,
          'password': password,
        }),
      ).timeout(timeout);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        // ✅ FIX: Extract accessToken from the data object
        final tokenData = responseData['data'];
        final accessToken = tokenData['accessToken'];  // Get the accessToken inside data
        final refreshToken = tokenData['refreshToken'];  // Also store refreshToken if needed

        final decodedToken = JwtDecoder.decode(accessToken);
        final user = UserModel.fromJwtToken(decodedToken, accessToken);

        return {
          'success': true,
          'token': accessToken,
          'refreshToken': refreshToken,
          'user': user,
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Invalid credentials',
        };
      }
    } catch (e) {
      print('Login error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // ==================== GUARDIAN ENDPOINTS ====================

  // Endpoint 1: Get Guardian Students (Wards)
  Future<Map<String, dynamic>> getGuardianStudents({
    required String token,
    required String guardianId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/Student/GetGuardianStudents/$guardianId');
      print('Fetching students from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Students response status: ${response.statusCode}');
      print('Students response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': true,
          'data': [],
          'message': 'No students found',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'data': [],
          'message': responseData['responseMessage'] ?? 'No students found',
        };
      }
    } catch (e) {
      print('Get students error: $e');
      return {
        'success': true,
        'data': [],
        'message': 'Could not fetch students: ${e.toString()}',
      };
    }
  }

  // Endpoint 2: Get Guardian Savings Account (Wallet)
  // Get Guardian Savings Account (Wallet)
  Future<Map<String, dynamic>> getGuardianSavingsAccount({
    required String token,
    required String guardianId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/Account/GetGuardianSavingsAccount/$guardianId');
      print('Fetching account from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Account response status: ${response.statusCode}');
      print('Account response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': true,
          'balance': 0.0,
          'accountNumber': '',
          'accountName': '',
          'bankName': '',
          'ledgerBalance': 0.0,
          'message': 'No account data found',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        final accountData = responseData['data'];
        return {
          'success': true,
          'balance': (accountData?['balance'] ?? 0.0).toDouble(),
          'accountNumber': accountData?['accountNumber'] ?? '',
          'accountName': accountData?['accountName'] ?? '',
          'bankName': accountData?['bankName'] ?? accountData?['bank'] ?? 'Not Available',
          'ledgerBalance': (accountData?['ledgerBalance'] ?? 0.0).toDouble(),
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'balance': 0.0,
          'accountNumber': '',
          'accountName': '',
          'bankName': '',
          'ledgerBalance': 0.0,
          'message': responseData['responseMessage'] ?? 'No account data',
        };
      }
    } catch (e) {
      print('Get account error: $e');
      return {
        'success': true,
        'balance': 0.0,
        'accountNumber': '',
        'accountName': '',
        'bankName': '',
        'ledgerBalance': 0.0,
        'message': 'Could not fetch account: ${e.toString()}',
      };
    }
  }
  // Endpoint 3: Get Guardian by ID (to get guardian details)
  Future<Map<String, dynamic>> getGuardianById({
    required String token,
    required String guardianId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/Guardian/GetGuardianById/$guardianId');
      print('Fetching guardian from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Guardian response status: ${response.statusCode}');
      print('Guardian response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to fetch guardian details',
        };
      }
    } catch (e) {
      print('Get guardian error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // ==================== STUDENT RESULT ENDPOINTS ====================

  // Get Student Results
  Future<Map<String, dynamic>> getStudentResult({
    required String token,
    required String schoolId,
    required String studentId,
    required String classroomId,
    required String sessionId,
    required String termId,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Result/GetStudentResultBySchoolAndClass?schoolId=$schoolId&studentId=$studentId&classroomId=$classroomId&sessionId=$sessionId&term=$termId');
      print('Fetching student result from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Result response status: ${response.statusCode}');
      print('Result response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'hasResult': false,
          'message': 'No result found',
          'data': null,
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'hasResult': true,
          'data': responseData['data'],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': false,
          'hasResult': false,
          'message': responseData['responseMessage'] ?? 'No result found',
          'data': null,
        };
      }
    } catch (e) {
      print('Get result error: $e');
      return {
        'success': false,
        'hasResult': false,
        'message': 'Network error: ${e.toString()}',
        'data': null,
      };
    }
  }

  // ==================== NEWS ENDPOINTS ====================

  // Get All News
  Future<Map<String, dynamic>> getAllNews({
    required String token,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/News/GetAllNews');
      print('Fetching news from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('News response status: ${response.statusCode}');
      print('News response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': true,
          'data': [],
          'message': 'No news found',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'data': [],
          'message': responseData['responseMessage'] ?? 'No news found',
        };
      }
    } catch (e) {
      print('Get news error: $e');
      return {
        'success': true,
        'data': [],
        'message': 'Could not fetch news: ${e.toString()}',
      };
    }
  }

  // ==================== HMO ENDPOINTS ====================

  // Get Child Hospital Records
  Future<Map<String, dynamic>> getChildHospitalRecords({
    required String token,
    required String studentId,
    required String schoolId,
    required String sessionId,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/HMO/GetChildHospitalRecords?studentId=$studentId&schoolId=$schoolId&sessionId=$sessionId');
      print('Fetching hospital records from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Hospital records response status: ${response.statusCode}');
      print('Hospital records response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': true,
          'data': [],
          'summary': null,
          'message': 'No hospital records found',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'summary': responseData['summary'],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'data': [],
          'summary': null,
          'message': responseData['responseMessage'] ?? 'No hospital records found',
        };
      }
    } catch (e) {
      print('Get hospital records error: $e');
      return {
        'success': true,
        'data': [],
        'summary': null,
        'message': 'Could not fetch hospital records: ${e.toString()}',
      };
    }
  }

  // Get HMO Package Details
  Future<Map<String, dynamic>> getHMOPackageDetails({
    required String token,
    required String schoolId,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/HMO/GetPackageDetails?schoolId=$schoolId');
      print('Fetching HMO package from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('HMO package response status: ${response.statusCode}');
      print('HMO package response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': true,
          'data': null,
          'message': 'No HMO package found',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'data': null,
          'message': responseData['responseMessage'] ?? 'No HMO package found',
        };
      }
    } catch (e) {
      print('Get HMO package error: $e');
      return {
        'success': true,
        'data': null,
        'message': 'Could not fetch HMO package: ${e.toString()}',
      };
    }
  }

// ==================== TEACHER ENDPOINTS ====================

  // Add these methods to your ApiService class

  // ==================== TEACHER ATTENDANCE ENDPOINTS (UPDATED) ====================

// CLOCK IN - Updated to use http instead of Dio
  // ==================== TEACHER ATTENDANCE ENDPOINTS ====================

// CLOCK IN - Complete working version
  Future<Map<String, dynamic>> clockIn({
    required String teacherId,
    required String schoolId,
    required String qrCodeValue,
    required double latitude,
    required double longitude,
    required String deviceModel,
    required String appVersion,
    required String ipAddress,
    required String userAgent,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/TeacherAttendance/ClockIn?teacherId=$teacherId');
      print('📤 Clock In Request');
      print('URL: $url');
      print('Payload: ${jsonEncode({
        'schoolId': schoolId,
        'qrCodeValue': qrCodeValue,
        'latitude': latitude,
        'longitude': longitude,
        'deviceModel': deviceModel,
        'appVersion': appVersion,
        'ipAddress': ipAddress,
        'userAgent': userAgent,
      })}');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'schoolId': schoolId,
          'qrCodeValue': qrCodeValue,
          'latitude': latitude,
          'longitude': longitude,
          'deviceModel': deviceModel,
          'appVersion': appVersion,
          'ipAddress': ipAddress,
          'userAgent': userAgent,
        }),
      ).timeout(timeout);

      print('📥 Clock In Response');
      print('Status Code: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
        };
      }

      final responseData = jsonDecode(response.body);

      // Check if response indicates success
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Check if there's a status field in the response
        if (responseData['status'] == true || responseData['status'] == 'true') {
          return {
            'success': true,
            'data': responseData['data'],
            'message': responseData['responseMessage'] ?? 'Clock in successful',
          };
        } else {
          // Status is false or not present
          return {
            'success': false,
            'message': responseData['responseMessage'] ?? 'Clock in failed',
            'data': responseData['data'],
          };
        }
      } else {
        // Non-200 status code
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to clock in (Status ${response.statusCode})',
          'data': responseData['data'],
        };
      }
    } catch (e) {
      print('❌ Clock In Error: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

// CLOCK OUT - Updated to match the same pattern
  Future<Map<String, dynamic>> clockOut({
    required String schoolId,
    required String teacherId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/TeacherAttendance/ClockOut?schoolId=$schoolId&teacherId=$teacherId');
      print('📤 Clock Out Request');
      print('URL: $url');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      print('📥 Clock Out Response');
      print('Status Code: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (responseData['status'] == true || responseData['status'] == 'true') {
          return {
            'success': true,
            'data': responseData['data'],
            'message': responseData['responseMessage'] ?? 'Clock out successful',
          };
        } else {
          return {
            'success': false,
            'message': responseData['responseMessage'] ?? 'Clock out failed',
            'data': responseData['data'],
          };
        }
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to clock out (Status ${response.statusCode})',
        };
      }
    } catch (e) {
      print('❌ Clock Out Error: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    }
  }

// GET TEACHER ATTENDANCE STATUS
  Future<Map<String, dynamic>> getTeacherAttendanceStatus({
    required String teacherId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/TeacherAttendance/Status?teacherId=$teacherId');
      print('📤 Get Attendance Status');
      print('URL: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(timeout);

      print('📥 Attendance Status Response');
      print('Status Code: ${response.statusCode}');
      print('Body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
          'isClockedIn': false,
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (responseData['status'] == true || responseData['status'] == 'true') {
          // Extract attendance status from data
          final data = responseData['data'];
          final isClockedIn = data?['isClockedIn'] ?? data?['isClockedIn'] ?? false;

          return {
            'success': true,
            'data': data,
            'isClockedIn': isClockedIn,
            'message': responseData['responseMessage'] ?? 'Attendance status retrieved',
          };
        } else {
          return {
            'success': false,
            'message': responseData['responseMessage'] ?? 'Failed to get attendance status',
            'isClockedIn': false,
          };
        }
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to get attendance status (Status ${response.statusCode})',
          'isClockedIn': false,
        };
      }
    } catch (e) {
      print('❌ Get Attendance Status Error: $e');
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
        'isClockedIn': false,
      };
    }
  }

// GET TEACHER ATTENDANCE STATUS - Updated to use http instead of Dio

// Get today's attendance status for a teacher


// Get Teacher by ID
  Future<Map<String, dynamic>> getTeacherById({
    required String token,
    required String teacherId,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Teacher/GetTeacherById/$teacherId');
      print('Fetching teacher from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Teacher response status: ${response.statusCode}');
      print('Teacher response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to fetch teacher details',
        };
      }
    } catch (e) {
      print('Get teacher error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

// Get Teacher Classrooms
  Future<Map<String, dynamic>> getTeacherClassrooms({
    required String token,
    required String teacherId,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Classroom/GetClassroomByTeacherId/$teacherId');
      print('Fetching teacher classrooms from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Classrooms response status: ${response.statusCode}');
      print('Classrooms response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': true,
          'data': [],
          'message': 'No classrooms found',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'data': [],
          'message': responseData['responseMessage'] ?? 'No classrooms found',
        };
      }
    } catch (e) {
      print('Get classrooms error: $e');
      return {
        'success': true,
        'data': [],
        'message': 'Could not fetch classrooms: ${e.toString()}',
      };
    }
  }

// Get Students by Classroom ID
  Future<Map<String, dynamic>> getStudentsByClassroomId({
    required String token,
    required String classroomId,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Classroom/GetStudentsByClassId/$classroomId');
      print('Fetching students from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Students response status: ${response.statusCode}');
      print('Students response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': true,
          'data': [],
          'message': 'No students found',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'data': [],
          'message': responseData['responseMessage'] ?? 'No students found',
        };
      }
    } catch (e) {
      print('Get students error: $e');
      return {
        'success': true,
        'data': [],
        'message': 'Could not fetch students: ${e.toString()}',
      };
    }
  }


// Save Teacher Results
  Future<Map<String, dynamic>> saveTeacherResults({
    required String token,
    required String schoolId,
    required String classroomId,
    required String studentId,
    required String sessionId,
    required String termId,
    required List<Map<String, dynamic>> results,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Result/SaveResults');
      print('Saving results at: $url');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'schoolId': schoolId,
          'classroomId': classroomId,
          'studentId': studentId,
          'sessionId': sessionId,
          'termId': termId,
          'results': results,
        }),
      ).timeout(timeout);

      print('Save results response status: ${response.statusCode}');
      print('Save results response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to save results',
        };
      }
    } catch (e) {
      print('Save results error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

// Save Teacher Attendance - Updated with correct endpoint
  Future<Map<String, dynamic>> saveTeacherAttendance({
    required String token,
    required String studentId,
    required String classroomId,
    required String sessionId,
    required String termId,
    required int status,
    required DateTime date,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Attendance/MarkAttendance');
      print('Saving attendance at: $url');

      // Format date to ISO string
      final formattedDate = date.toIso8601String();

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'studentId': studentId,
          'classroomId': classroomId,
          'sessionId': sessionId,
          'termId': termId,
          'status': status,
          'date': formattedDate,
        }),
      ).timeout(timeout);

      print('Save attendance response status: ${response.statusCode}');
      print('Save attendance response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'message': responseData['responseMessage'] ?? 'Attendance marked successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to mark attendance',
        };
      }
    } catch (e) {
      print('Save attendance error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Get Attendance by Active Term
  Future<Map<String, dynamic>> getAttendanceByActiveTerm({
    required String token,
    required String schoolId,
    required String classroomId,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Attendance/GetAttendanceByActiveTerm/$schoolId/$classroomId');
      print('Fetching attendance history from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('Attendance history response status: ${response.statusCode}');
      print('Attendance history response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': true,
          'data': [],
          'message': 'No attendance records found',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'data': responseData['data'] ?? [],
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'data': [],
          'message': responseData['responseMessage'] ?? 'No attendance records found',
        };
      }
    } catch (e) {
      print('Get attendance history error: $e');
      return {
        'success': true,
        'data': [],
        'message': 'Could not fetch attendance history: ${e.toString()}',
      };
    }
  }

  // Add Subject
  Future<Map<String, dynamic>> addSubject({
    required String token,
    required String schoolId,
    required String classroomId,
    required String teacherId,
    required String sessionTermId,
    required String subjectName,
    required String description,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Result/AddSubject');
      print('Adding subject at: $url');

      final requestBody = {
        'schoolId': schoolId,
        'classroomId': classroomId,
        'teacherId': teacherId,
        'sessionTermId': sessionTermId,
        'subjectName': subjectName,
        'description': description,
      };

      print('Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      ).timeout(timeout);

      print('Add subject response status: ${response.statusCode}');
      print('Add subject response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'message': responseData['responseMessage'] ?? 'Subject added successfully',
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to add subject',
        };
      }
    } catch (e) {
      print('Add subject error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }
// Add Subject Scores
  Future<Map<String, dynamic>> addSubjectScores({
    required String token,
    required String schoolId,
    required String classroomId,
    required String subjectId,
    required String sessionId,
    required String sessionTermId,
    required String term,
    required List<Map<String, dynamic>> scores,
  }) async {
    try {
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Result/AddSubjectScores');
      print('Adding subject scores at: $url');

      // Format as array of objects (the API expects an array)
      final requestBody = [
        {
          'schoolId': schoolId,
          'classroomId': classroomId,
          'subjectId': subjectId,
          'sessionId': sessionId,
          'sessionTermId': sessionTermId,
          'term': term,
          'scores': scores.map((score) => {
            'studentId': score['studentId'],
            'ca': score['ca'],
            'examScore': score['examScore'],
            'remarks': score['remarks'] ?? 'Good performance',
          }).toList(),
        }
      ];

      print('Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      ).timeout(timeout);

      print('Add subject scores response status: ${response.statusCode}');
      print('Add subject scores response body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
        };
      }

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        return {
          'success': true,
          'message': responseData['responseMessage'] ?? 'Scores added successfully',
          'data': responseData['data'],
        };
      } else {
        // Handle validation errors
        String errorMessage = responseData['message'] ?? 'Failed to add scores';
        if (responseData['errors'] != null) {
          final errors = responseData['errors'];
          if (errors['dtos'] != null) {
            errorMessage = errors['dtos'][0];
          } else if (errors['[0].subjectId'] != null) {
            errorMessage = 'Invalid subject ID format. Please ensure subject ID is a valid GUID.';
          } else if (errors['[0].sessionId'] != null) {
            errorMessage = 'Invalid session ID format. Please ensure session ID is a valid GUID.';
          }
        }
        return {
          'success': false,
          'message': errorMessage,
        };
      }
    } catch (e) {
      print('Add subject scores error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }




  Future<Map<String, dynamic>> createAssignment({
    required String token,
    required String title,
    required String description,
    required String teacherId,
    required String classroomId,
    required DateTime dueDate,
    required String termId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('api/Assignment/CreateAssignment'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'description': description,
          'teacherId': teacherId,
          'classroomId': classroomId,
          'dueDate': dueDate.toIso8601String(),
          'termId': termId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Assignment created successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to create assignment. Status code: ${response.statusCode}',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error creating assignment: $e',
      };
    }
  }

  // Get assignments by class ID
  Future<Map<String, dynamic>> getAssignmentsByClassId({
    required String token,
    required String classroomId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Assignment/GetAssignmentByClassId/$classroomId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Assignments fetched successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch assignments',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

// Get all classrooms
  Future<Map<String, dynamic>> getAllClassrooms({
    required String token,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('https://educat.codeweb.com.ng/api/Classroom/GetAllClassroom'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Classrooms fetched successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch classrooms',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

// Get total students in a class
  Future<Map<String, dynamic>> getTotalStudentsInClass({
    required String token,
    required String classroomId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Classroom/GetTotalStudentInClass?classroomId=$classroomId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Students found',
          'data': data['data'] ?? 0,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch student count',
          'data': 0,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': 0,
      };
    }
  }

// Get total amount owed in a class
  Future<Map<String, dynamic>> getTotalAmountOwedInClass({
    required String token,
    required String classroomId,
    required String sessionId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Classroom/GetTotalAmountOwedInClass?classroomId=$classroomId&sessionId=$sessionId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Amount found',
          'data': data['data'] ?? 0.0,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch amount owed',
          'data': 0.0,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': 0.0,
      };
    }
  }

// Get students owing in a class
  Future<Map<String, dynamic>> getStudentsOwingInClass({
    required String token,
    required String classroomId,
    required String sessionId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Classroom/GetStudentCountOwingInClass?classroomId=$classroomId&sessionId=$sessionId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Students found',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch students owing',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }


  // Get all teachers by school
  Future<Map<String, dynamic>> getAllTeachersBySchool({
    required String token,
    required String schoolId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Teacher/GetTeachersBySchool/$schoolId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Teachers retrieved successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch teachers',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

// Get teacher by classroom
  Future<Map<String, dynamic>> getTeacherByClass({
    required String token,
    required String classroomId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Teacher/GetTeacherByClass/$classroomId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Teacher retrieved successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch teacher',
          'data': null,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': null,
      };
    }
  }

  // Get all guardians by school
  Future<Map<String, dynamic>> getAllGuardiansBySchool({
    required String token,
    required String schoolId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Guardian/GetGuardiansBySchool?schoolId=$schoolId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Guardians retrieved successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch guardians',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

// Get guardian count by school
  Future<Map<String, dynamic>> getGuardianCountBySchool({
    required String token,
    required String schoolId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Guardian/GetGuardianCountBySchool?schoolId=$schoolId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Count retrieved successfully',
          'data': data['data'] ?? 0,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch guardian count',
          'data': 0,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': 0,
      };
    }
  }

// Get guardian transactions by school
  Future<Map<String, dynamic>> getGuardianTransactionsBySchool({
    required String token,
    required String schoolId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/GuardianTransactions/GetTransactionsBySchool/$schoolId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Transactions retrieved successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch transactions',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

  // Get guardian's students (for mapping guardians to their children)
  Future<Map<String, dynamic>> getGuardianStudentsMapping({
    required String token,
    required String guardianId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Student/GetGuardianStudents/$guardianId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Students fetched successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch guardian students',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

  // Get all students by school
  Future<Map<String, dynamic>> getAllStudentsBySchool({
    required String token,
    required String schoolId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Student/GetStudentsBySchool?schoolId=$schoolId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Students fetched successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch students',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

  // Get classrooms by school ID
  Future<Map<String, dynamic>> getClassroomsBySchoolId({
    required String token,
    required String schoolId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Classroom/GetClassroomsBySchoolId?schoolId=$schoolId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Classrooms fetched successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch classrooms',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

  // ==================== MESSAGE ENDPOINTS ====================

// Send a message
  Future<Map<String, dynamic>> sendMessage({
    required String token,
    required String senderId,
    required String senderRole,
    required String receiverId,
    required String receiverRole,
    required String content,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/Message/SendMessage'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'senderId': senderId,
          'senderRole': senderRole,
          'receiverId': receiverId,
          'receiverRole': receiverRole,
          'content': content,  // Make sure this is 'content', not 'messageDto'
        }),
      );

      print('Send message response status: ${response.statusCode}');
      print('Send message response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Message sent successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to send message: ${response.body}',
          'data': null,
        };
      }
    } catch (e) {
      print('Error sending message: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'data': null,
      };
    }
  }

// Get inbox messages for a user
  Future<Map<String, dynamic>> getInboxMessages({
    required String token,
    required String userId,
    required String userRole,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Message/inbox/$userId/$userRole'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Messages retrieved successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch messages',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

// Get all messages (for admin)
  Future<Map<String, dynamic>> getAllMessages({
    required String token,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Message/GetAllMessages'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Messages retrieved successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch messages',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

// Get message by ID
  Future<Map<String, dynamic>> getMessageById({
    required String token,
    required String messageId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Message/GetMessageById/$messageId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Message retrieved successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch message',
          'data': null,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': null,
      };
    }
  }

// Get conversation between two users
  Future<Map<String, dynamic>> getConversation({
    required String token,
    required String user1Id,
    required String user1Role,
    required String user2Id,
    required String user2Role,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Message/GetConversation/$user1Id/$user1Role/$user2Id/$user2Role'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Conversation retrieved successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch conversation',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

// Mark message as read
  Future<Map<String, dynamic>> markMessageAsRead({
    required String token,
    required String messageId,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/Message/MarkAsRead/$messageId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Message marked as read',
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to mark message as read',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

  // Get user details by ID and role
  Future<Map<String, dynamic>> getUserDetails({
    required String token,
    required String userId,
    required String userRole,
  }) async {
    try {
      String endpoint = '';
      switch (userRole.toLowerCase()) {
        case 'teacher':
          endpoint = '$baseUrl/Teacher/GetTeacherById/$userId';
          break;
        case 'guardian':
          endpoint = '$baseUrl/Guardian/GetGuardianById/$userId';
          break;
        case 'schooladmin':
          endpoint = '$baseUrl/SchoolAdmin/GetSchoolAdminById/$userId';
          break;
        default:
          return {
            'success': false,
            'message': 'Unknown role',
            'data': null,
          };
      }

      final response = await http.get(
        Uri.parse(endpoint),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'User retrieved successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch user',
          'data': null,
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': null,
      };
    }
  }

  // Get admin inbox messages
  Future<Map<String, dynamic>> getAdminInboxMessages({
    required String token,
    required String adminId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Message/inbox/$adminId/SchoolAdmin'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Messages retrieved successfully',
          'data': data['data'] ?? [],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch messages',
          'data': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
        'data': [],
      };
    }
  }

  // Save FCM token to server
  Future<Map<String, dynamic>> saveFcmToken({
    required String token,
    required String userId,
    required String userRole,
    required String fcmToken,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/Notification/SaveFcmToken'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'userId': userId,
          'userRole': userRole,
          'fcmToken': fcmToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Token saved successfully',
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to save token',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }

// Send notification (for backend integration)
// Note: This is for reference - actual notification sending should be done from backend
  Future<Map<String, dynamic>> sendNotification({
    required String token,
    required String receiverId,
    required String receiverRole,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/Notification/Send'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'receiverId': receiverId,
          'receiverRole': receiverRole,
          'title': title,
          'body': body,
          'data': data,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        return {
          'success': responseData['status'] == true,
          'message': responseData['responseMessage'] ?? 'Notification sent successfully',
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to send notification',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Error: $e',
      };
    }
  }


  /// Get student all subjects scores by term ID
  Future<Map<String, dynamic>> getStudentAllSubjectsScoresByTermId({
    required String token,
    required String schoolId,
    required String classroomId,
    required String studentId,
    required String sessionKey,
    required String termId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Result/GetStudentAllSubjectsScoresByTermId?schoolId=$schoolId&classroomId=$classroomId&studentId=$studentId&sessionId=$sessionKey&termId=$termId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      print('Results response status: ${response.statusCode}');
      print('Results response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Results fetched successfully',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch results',
          'data': null,
        };
      }
    } catch (e) {
      print('Error fetching student results: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'data': null,
      };
    }
  }

  // Add these methods to your ApiService class

// Get total debt owed in class by term
  Future<Map<String, dynamic>> getTotalDebtOwedInClassByTerm({
    required String token,
    required String classroomId,
    required String sessionId,
    required String termId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Classroom/GetTotalDebtOwedInClassByTerm?classroomId=$classroomId&sessionId=$sessionId&termId=$termId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Success',
          'data': data['data'] ?? 0.0,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch debt amount',
          'data': 0.0,
        };
      }
    } catch (e) {
      print('Error getting total debt: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'data': 0.0,
      };
    }
  }

  // Add this method to your ApiService class

// ==================== STUDENT DISCOUNT ENDPOINTS ====================

  /// Get discounts for a specific student

  /// Get discounts for a specific student
  // In api_service.dart

  /// Get discounts for a specific student
  Future<Map<String, dynamic>> getStudentDiscounts({
    required String token,
    required String studentId,
  }) async {
    try {
      // Check if token is expired
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/StudentDiscount/GetDiscountsByStudent/$studentId');
      print('📤 Fetching student discounts from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('📥 Discounts Response Status: ${response.statusCode}');
      print('📥 Discounts Response Body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
          'discounts': [],
          'hasDiscounts': false,
          'discountCount': 0,
        };
      }

      final responseData = jsonDecode(response.body);
      final int httpStatus = response.statusCode;
      final bool isSuccess = responseData['status'] == true || responseData['status'] == 'true';

      if (httpStatus == 200 && isSuccess) {
        final data = responseData['data'];

        // Ensure data is a List
        final List<dynamic> discounts = data is List ? data : [];

        print('💰 Found ${discounts.length} discount(s)');
        for (var discount in discounts) {
          if (discount is Map<String, dynamic>) {
            print('   Discount ID: ${discount['discountId']}');
            print('   Amount: ₦${discount['discountAmount']}');
            print('   Reason: ${discount['reason']}');
            print('   Active: ${discount['isActive']}');
          }
        }

        return {
          'success': true,
          'message': responseData['responseMessage'] ?? 'Discounts retrieved successfully',
          'discounts': discounts, // This is now a List<dynamic> not List<DiscountModel>
          'hasDiscounts': discounts.isNotEmpty,
          'discountCount': discounts.length,
          'rawData': responseData,
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to fetch discounts',
          'discounts': [],
          'hasDiscounts': false,
          'discountCount': 0,
        };
      }
    } catch (e) {
      print('❌ Get student discounts error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'discounts': [],
        'hasDiscounts': false,
        'discountCount': 0,
      };
    }
  }

  /// Get class fee for a specific term
  Future<Map<String, dynamic>> getClassFeeForTerm({
    required String token,
    required String classId,
    required String sessionId,
  }) async {
    try {
      // Check if token is expired
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      // URL encode the sessionId to handle special characters like '/'
      final encodedSessionId = Uri.encodeComponent(sessionId);
      final url = Uri.parse('$baseUrl/SchoolFee/GetClassFeeForTerm?classId=$classId&sessionId=$encodedSessionId');

      print('📤 Fetching class fee from: $url');
      print('📤 ClassId: $classId');
      print('📤 SessionId: $sessionId');
      print('📤 Encoded SessionId: $encodedSessionId');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('📥 Class Fee Response Status: ${response.statusCode}');
      print('📥 Class Fee Response Body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
          'fee': 0.0,
        };
      }

      final responseData = jsonDecode(response.body);
      final int httpStatus = response.statusCode;

      // Check for validation errors
      if (httpStatus == 400 && responseData['errors'] != null) {
        final errors = responseData['errors'];
        String errorMessage = 'Validation error: ';
        errors.forEach((key, value) {
          errorMessage += '$key: ${value.join(', ')} ';
        });
        print('❌ Validation error: $errorMessage');
        return {
          'success': false,
          'message': errorMessage,
          'fee': 0.0,
        };
      }

      final bool isSuccess = responseData['status'] == true || responseData['status'] == 'true';

      if (httpStatus == 200 && isSuccess) {
        final double fee = (responseData['data'] as num?)?.toDouble() ?? 0.0;

        return {
          'success': true,
          'message': responseData['responseMessage'] ?? 'Class fee retrieved successfully',
          'fee': fee,
          'data': responseData['data'],
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to fetch class fee',
          'fee': 0.0,
        };
      }
    } catch (e) {
      print('❌ Get class fee error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'fee': 0.0,
      };
    }
  }

  /// Get student fee amount
  Future<Map<String, dynamic>> getStudentFee({
    required String token,
    required String studentId,
    required String sessionId,
  }) async {
    try {
      final url = Uri.parse('$baseUrl/Student/GetStudentFee?studentId=$studentId&sessionId=$sessionId');
      print('📤 Fetching student fee from: $url');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('📥 Fee Response Status: ${response.statusCode}');
      print('📥 Fee Response Body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
          'fee': 0.0,
        };
      }

      final responseData = jsonDecode(response.body);
      final int httpStatus = response.statusCode;
      final bool isSuccess = responseData['status'] == true || responseData['status'] == 'true';

      if (httpStatus == 200 && isSuccess) {
        final data = responseData['data'];
        final double fee = (data?['fee'] ?? data?['amount'] ?? 0.0).toDouble();

        return {
          'success': true,
          'message': responseData['responseMessage'] ?? 'Fee retrieved successfully',
          'fee': fee,
          'data': data,
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to fetch fee',
          'fee': 0.0,
        };
      }
    } catch (e) {
      print('❌ Get student fee error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'fee': 0.0,
      };
    }
  }


  /// Get discounted fee for a student (this is what calculates the fee after discount)
  /// Get discounted fee for a student
  // In api_service.dart

  /// Get discounted fee for a student (using sessionId and termId from the discount)
  Future<Map<String, dynamic>> getDiscountedFee({
    required String token,
    required String studentId,
    required double originalFee,
    required String sessionId,
    required String termId,
  }) async {
    try {
      // Check if token is expired
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      // URL encode parameters
      final encodedSessionId = Uri.encodeComponent(sessionId);
      final encodedTermId = Uri.encodeComponent(termId);

      final url = Uri.parse(
          '$baseUrl/StudentDiscount/GetDiscountedFee?studentId=$studentId&originalFee=$originalFee&sessionId=$encodedSessionId&termId=$encodedTermId'
      );

      print('📤 Fetching discounted fee from: $url');
      print('📤 StudentId: $studentId');
      print('📤 OriginalFee: $originalFee');
      print('📤 SessionId: $sessionId');
      print('📤 TermId: $termId');

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(timeout);

      print('📥 Discounted Fee Response Status: ${response.statusCode}');
      print('📥 Discounted Fee Response Body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
          'discountedFee': originalFee,
          'originalFee': originalFee,
          'discountAmount': 0,
          'hasDiscount': false,
        };
      }

      final responseData = jsonDecode(response.body);
      final int httpStatus = response.statusCode;
      final bool isSuccess = responseData['status'] == true || responseData['status'] == 'true';

      if (httpStatus == 200 && isSuccess) {
        final data = responseData['data'];
        final double discountedFee = (data?['feeAfterDiscount'] ?? data?['discountedFee'] ?? originalFee).toDouble();
        final double discountAmount = (data?['discountAmount'] ?? 0).toDouble();
        final bool hasDiscount = data?['hasDiscount'] ?? false;

        print('💰 Discount Calculation Result:');
        print('   Original Fee: ₦$originalFee');
        print('   Discount Amount: ₦$discountAmount');
        print('   Fee After Discount: ₦$discountedFee');
        print('   Has Discount: $hasDiscount');

        return {
          'success': true,
          'message': responseData['responseMessage'] ?? 'Discount applied successfully',
          'discountedFee': discountedFee,
          'originalFee': originalFee,
          'discountAmount': discountAmount,
          'hasDiscount': hasDiscount,
          'discountDetails': data,
          'rawData': responseData,
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to calculate discounted fee',
          'discountedFee': originalFee,
          'originalFee': originalFee,
          'discountAmount': 0,
          'hasDiscount': false,
        };
      }
    } catch (e) {
      print('❌ Get discounted fee error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'discountedFee': originalFee,
        'originalFee': originalFee,
        'discountAmount': 0,
        'hasDiscount': false,
      };
    }
  }
  /// Initiate school fee payment
  Future<Map<String, dynamic>> initiateSchoolFeePayment({
    required String token,
    required String studentId,
    required String schoolId,
    required String guardianId,
    required double amount,
    required String customerEmail,
    required String gateway,
    required String redirectUrl,
    required String callbackUrl,
    required String classroomId,
  }) async {
    try {
      // Check if token is expired
      if (JwtDecoder.isTokenExpired(token)) {
        return {
          'success': false,
          'message': 'Session expired. Please login again.',
          'expired': true,
        };
      }

      final url = Uri.parse('$baseUrl/Payment/InitiateSchoolFeeGatewayPayment');
      print('📤 Initiating payment at: $url');

      final requestBody = {
        'studentId': studentId,
        'schoolId': schoolId,
        'guardianId': guardianId,
        'amount': amount,
        'customerEmail': customerEmail,
        'gateway': gateway,
        'redirectUrl': redirectUrl,
        'callbackUrl': callbackUrl,
        'classroomId': classroomId,
      };

      print('📤 Payment Request Body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      ).timeout(timeout);

      print('📥 Payment Response Status: ${response.statusCode}');
      print('📥 Payment Response Body: ${response.body}');

      if (response.body.isEmpty) {
        return {
          'success': false,
          'message': 'Empty response from server',
        };
      }

      final responseData = jsonDecode(response.body);
      final int httpStatus = response.statusCode;
      final bool isSuccess = responseData['status'] == true || responseData['status'] == 'true';

      if (httpStatus == 200 && isSuccess) {
        final data = responseData['data'];
        return {
          'success': true,
          'message': responseData['responseMessage'] ?? 'Payment initialized successfully',
          'data': data,
          'checkoutUrl': data?['checkoutUrl'],
          'reference': data?['reference'],
          'gateway': data?['gateway'],
          'rawData': responseData,
        };
      } else {
        return {
          'success': false,
          'message': responseData['responseMessage'] ?? 'Failed to initiate payment',
        };
      }
    } catch (e) {
      print('❌ Initiate payment error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

// Get total amount paid in class by term
  Future<Map<String, dynamic>> getTotalAmountPaidInClassByTerm({
    required String token,
    required String classroomId,
    required String sessionId,
    required String termId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Classroom/GetTotalAmountPaidInClassByTerm?classroomId=$classroomId&sessionId=$sessionId&termId=$termId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Success',
          'data': data['data'] ?? 0.0,
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch paid amount',
          'data': 0.0,
        };
      }
    } catch (e) {
      print('Error getting total paid: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'data': 0.0,
      };
    }
  }




// Get students owing in class by term
  Future<Map<String, dynamic>> getStudentsOwingInClassByTerm({
    required String token,
    required String classroomId,
    required String sessionId,
    required String termId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Classroom/GetStudentsOwingInClassByTerm?classroomId=$classroomId&sessionId=$sessionId&termId=$termId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Success',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch students owing',
          'data': null,
        };
      }
    } catch (e) {
      print('Error getting students owing: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'data': null,
      };
    }
  }

// Get expected revenue for term (overall and per classroom)
  Future<Map<String, dynamic>> getExpectedRevenueForTerm({
    required String token,
    required String sessionId,
    required String termId,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/Classroom/GetExpectedRevenueForTerm?sessionId=$sessionId&termId=$termId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': data['status'] == true,
          'message': data['responseMessage'] ?? 'Success',
          'data': data['data'],
        };
      } else {
        return {
          'success': false,
          'message': 'Failed to fetch expected revenue',
          'data': null,
        };
      }
    } catch (e) {
      print('Error getting expected revenue: $e');
      return {
        'success': false,
        'message': 'Error: $e',
        'data': null,
      };

    }


  }

}