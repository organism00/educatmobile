import 'dart:convert';

class JwtDecoder {
  static Map<String, dynamic> decode(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        throw Exception('Invalid token format');
      }

      final payload = _decodeBase64(parts[1]);
      return jsonDecode(payload);
    } catch (e) {
      print('Error decoding JWT: $e');
      return {};
    }
  }

  static String _decodeBase64(String str) {
    String output = str.replaceAll('-', '+').replaceAll('_', '/');
    switch (output.length % 4) {
      case 0:
        break;
      case 2:
        output += '==';
        break;
      case 3:
        output += '=';
        break;
      default:
        throw Exception('Illegal base64url string!');
    }
    return utf8.decode(base64Url.decode(output));
  }

  static bool isTokenExpired(String token) {
    try {
      final decoded = decode(token);
      final expiry = decoded['exp'];
      if (expiry != null) {
        final expiryDate = DateTime.fromMillisecondsSinceEpoch(expiry * 1000);
        return expiryDate.isBefore(DateTime.now());
      }
      return true;
    } catch (e) {
      return true;
    }
  }
}