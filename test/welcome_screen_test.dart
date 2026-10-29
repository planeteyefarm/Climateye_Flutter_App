import 'package:climateeye/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Login/Register is the unauthenticated entry screen', (t) async {
    await t.pumpWidget(const MaterialApp(home: LoginScreen()));
    await t.pump();

    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Get Started  →'), findsNothing);
  });
}
