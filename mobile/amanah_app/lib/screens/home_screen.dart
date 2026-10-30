
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../main.dart';

class HomeScreen extends StatefulWidget {
  final String fullName;
  final String email;

  const HomeScreen({
    super.key,
    required this.fullName,
    required this.email,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color forest = Color(0xFF344F45);
  static const Color ivory = Color(0xFFF4F0E8);

  final AuthService _authService = AuthService();

  bool _isLoggingOut = false;

  Future<void> _logout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      await _authService.logout();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const WelcomeScreen(),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to log out. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

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
            onPressed: _isLoggingOut ? null : _logout,
            tooltip: 'Logout',
            icon: _isLoggingOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.logout),
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
              style: TextStyle(
                fontSize: 18,
                color: forest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.fullName,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: forest,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.email,
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
              'A calmer, more connected life begins '
              'with one small step.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
