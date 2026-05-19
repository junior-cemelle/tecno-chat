import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { student, teacher }

class UserModel {
  final String uid;
  final String phone;
  final String email;
  final String displayName;
  final String avatarUrl;
  final UserRole role;
  final String career;
  final int? semester;       // solo alumnos
  final String? department;  // solo profesores
  final bool isOnline;
  final DateTime lastSeen;
  final List<String> contactIds;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.phone,
    required this.email,
    required this.displayName,
    required this.avatarUrl,
    required this.role,
    required this.career,
    this.semester,
    this.department,
    required this.isOnline,
    required this.lastSeen,
    required this.contactIds,
    required this.createdAt,
  });

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      phone: d['phone'] ?? '',
      email: d['email'] ?? '',
      displayName: d['displayName'] ?? '',
      avatarUrl: d['avatarUrl'] ?? '',
      role: d['role'] == 'teacher' ? UserRole.teacher : UserRole.student,
      career: d['career'] ?? '',
      semester: d['semester'],
      department: d['department'],
      isOnline: d['isOnline'] ?? false,
      lastSeen: (d['lastSeen'] as Timestamp).toDate(),
      contactIds: List<String>.from(d['contactIds'] ?? []),
      createdAt: (d['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'email': email,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'role': role.name,
        'career': career,
        'semester': semester,
        'department': department,
        'isOnline': isOnline,
        'lastSeen': Timestamp.fromDate(lastSeen),
        'contactIds': contactIds,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  bool get isTeacher => role == UserRole.teacher;
}
