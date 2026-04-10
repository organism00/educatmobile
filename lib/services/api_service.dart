import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../utils/jwt_decoder.dart';

class ApiService {
  static const String baseUrl = 'https://educat.codeweb.com.ng/api';
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
          'schoolRegistrationNumber': schoolRegistrationNumber,
          'email': email,
          'password': password,
        }),
      ).timeout(timeout);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['status'] == true) {
        final token = responseData['data'];
        final decodedToken = JwtDecoder.decode(token);
        final user = UserModel.fromJwtToken(decodedToken, token);

        return {
          'success': true,
          'token': token,
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
          'ledgerBalance': (accountData?['ledgerBalance'] ?? 0.0).toDouble(),
          'message': responseData['responseMessage'],
        };
      } else {
        return {
          'success': true,
          'balance': 0.0,
          'accountNumber': '',
          'accountName': '',
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
}