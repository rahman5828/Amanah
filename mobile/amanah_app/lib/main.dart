
import 'package:flutter/material.dart';

import 'core/errors/auth_exceptions.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AmanahApp());
}

class AmanahApp extends StatelessWidget {
  const AmanahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AMANAH',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F0E8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF344F45),
          primary: const Color(0xFF344F45),
          surface: const Color(0xFFF4F0E8),
        ),
        fontFamily: 'Roboto',
      ),
      home: const SessionGate(),
    );
  }
}

// Checks whether the user already has a valid login session.
class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  final AuthService _authService = AuthService();

  bool _isLoading = true;
  bool _hasError = false;

  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final profile = await _authService.getProfile();

      if (!mounted) return;

      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } on NotAuthenticatedException {
      if (!mounted) return;
      // No saved token — go to welcome.
      setState(() {
        _profile = null;
        _isLoading = false;
        _hasError = false;
      });
    } on SessionExpiredException {
      if (!mounted) return;
      // Token already cleared by AuthService on 401.
      setState(() {
        _profile = null;
        _isLoading = false;
        _hasError = false;
      });
    } on ForbiddenException {
      if (!mounted) return;
      // Authenticated but not allowed — keep token, show retry.
      setState(() {
        _profile = null;
        _isLoading = false;
        _hasError = true;
      });
    } on NetworkException {
      if (!mounted) return;
      // Offline / timeout — preserve token.
      setState(() {
        _profile = null;
        _isLoading = false;
        _hasError = true;
      });
    } on ServerException {
      if (!mounted) return;
      // 5xx — preserve token.
      setState(() {
        _profile = null;
        _isLoading = false;
        _hasError = true;
      });
    } on ResponseParseException {
      if (!mounted) return;
      // Malformed body — preserve token.
      setState(() {
        _profile = null;
        _isLoading = false;
        _hasError = true;
      });
    } catch (error) {
      if (!mounted) return;
      // Unexpected — preserve token and allow retry.
      setState(() {
        _profile = null;
        _isLoading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F0E8),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmbraceLogo(size: 64),
              SizedBox(height: 24),
              CircularProgressIndicator(
                color: Color(0xFF344F45),
              ),
              SizedBox(height: 16),
              Text(
                'Preparing your space...',
                style: TextStyle(
                  color: Color(0xFF344F45),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasError) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F0E8),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    color: Color(0xFF344F45),
                    size: 56,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Unable to connect',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF344F45),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'We couldn\'t verify your session. '
                    'Please check your internet connection '
                    'and try again.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.6,
                      color: Color(0xFF69786D),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: _checkSession,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF344F45),
                      ),
                      child: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      await _authService.logout();

                      if (!mounted) return;

                      setState(() {
                        _hasError = false;
                        _profile = null;
                      });
                    },
                    child: const Text(
                      'Continue without signing in',
                      style: TextStyle(
                        color: Color(0xFF344F45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_profile != null) {
      return HomeScreen(
        fullName: _profile!['full_name'] as String,
        email: _profile!['email'] as String,
      );
    }

    return const WelcomeScreen();
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const forest = Color(0xFF344F45);
  static const sage = Color(0xFFA8B9A5);
  static const ivory = Color(0xFFF4F0E8);
  static const coral = Color(0xFFD9A18F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),

              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EDE5),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Center(
                  child: EmbraceLogo(size: 72),
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                'AMANAH',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 5,
                  color: forest,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Intelligence that cares.',
                style: TextStyle(
                  fontSize: 15,
                  color: forest,
                  letterSpacing: 0.4,
                ),
              ),

              const Spacer(flex: 2),

              const Text(
                'A calmer, more\nconnected life.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 34,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: forest,
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'Your personal space to organise life,\n'
                'care for your family, and stay close\n'
                'to what matters most.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.7,
                  color: Color(0xFF69786D),
                ),
              ),

              const Spacer(flex: 2),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: forest,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LoginScreen(),
                      ),
                    );
                  },
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Get started',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 12),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                'A little more care, every day.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8A978D),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class EmbraceLogo extends StatelessWidget {
  final double size;

  const EmbraceLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: EmbracePainter(),
    );
  }
}

class EmbracePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.16
      ..strokeCap = StrokeCap.round;

    paint.color = const Color(0xFF344F45);

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: size.width * 0.34,
      ),
      -2.5,
      2.4,
      false,
      paint,
    );

    paint.color = const Color(0xFFD9A18F);

    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: size.width * 0.34,
      ),
      0.65,
      2.4,
      false,
      paint,
    );

    canvas.drawCircle(
      center,
      size.width * 0.09,
      Paint()..color = const Color(0xFF344F45),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
