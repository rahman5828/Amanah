import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  final String fullName;
  final String email;

  const HomeScreen({
    super.key,
    required this.fullName,
    required this.email,
  });

  static const Color forest = Color(0xFF344F45);
  static const Color ivory = Color(0xFFF4F0E8);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ivory,
      appBar: AppBar(
        title: const Text('AMANAH'),
        backgroundColor: forest,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 30),
            const Text(
              'Welcome to AMANAH,',
              style: TextStyle(fontSize: 18, color: forest),
            ),
            const SizedBox(height: 8),
            Text(
              fullName,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: forest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              email,
              style: TextStyle(
                fontSize: 15,
                color: forest.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 35),
            const Text(
              'Your journey starts here.',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: forest,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'A calmer, more connected life begins with one small step.',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}