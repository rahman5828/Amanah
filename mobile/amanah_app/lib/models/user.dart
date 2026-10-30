class User {
  final String id;
  final String fullName;
  final String email;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.fullName,
    required this.email,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      email: json['email'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}