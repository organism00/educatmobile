class StudentResult {
  final String studentId;
  final String studentName;
  final String className;
  final String term;
  final String session;
  final List<SubjectScore> subjects;
  final double totalScore;
  final double averageScore;
  final String grade;
  final String remark;
  final double attendancePercentage;
  final String teacherRemark;
  final String principalRemark;

  StudentResult({
    required this.studentId,
    required this.studentName,
    required this.className,
    required this.term,
    required this.session,
    required this.subjects,
    required this.totalScore,
    required this.averageScore,
    required this.grade,
    required this.remark,
    required this.attendancePercentage,
    required this.teacherRemark,
    required this.principalRemark,
  });

  factory StudentResult.fromJson(Map<String, dynamic> json) {
    List<SubjectScore> subjects = [];
    if (json['subjects'] != null) {
      subjects = (json['subjects'] as List)
          .map((s) => SubjectScore.fromJson(s))
          .toList();
    }

    return StudentResult(
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'] ?? '',
      className: json['className'] ?? '',
      term: json['term'] ?? '',
      session: json['session'] ?? '',
      subjects: subjects,
      totalScore: (json['totalScore'] ?? 0).toDouble(),
      averageScore: (json['averageScore'] ?? 0).toDouble(),
      grade: json['grade'] ?? 'N/A',
      remark: json['remark'] ?? 'N/A',
      attendancePercentage: (json['attendancePercentage'] ?? 0).toDouble(),
      teacherRemark: json['teacherRemark'] ?? 'No remark',
      principalRemark: json['principalRemark'] ?? 'No remark',
    );
  }
}

class SubjectScore {
  final String subjectId;
  final String subjectName;
  final double caScore;
  final double examScore;
  final double totalScore;
  final String grade;
  final String remark;

  SubjectScore({
    required this.subjectId,
    required this.subjectName,
    required this.caScore,
    required this.examScore,
    required this.totalScore,
    required this.grade,
    required this.remark,
  });

  factory SubjectScore.fromJson(Map<String, dynamic> json) {
    return SubjectScore(
      subjectId: json['subjectId'] ?? '',
      subjectName: json['subjectName'] ?? '',
      caScore: (json['caScore'] ?? 0).toDouble(),
      examScore: (json['examScore'] ?? 0).toDouble(),
      totalScore: (json['totalScore'] ?? 0).toDouble(),
      grade: json['grade'] ?? 'N/A',
      remark: json['remark'] ?? 'Fair performance',
    );
  }
}