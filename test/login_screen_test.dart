import 'package:climateeye/screens/login_screen.dart';
import 'package:climateeye/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login and register are distinct; register has no website API',
      (t) async {
    await t.pumpWidget(const MaterialApp(home: LoginScreen()));
    await t.pump();

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName ==
                'assets/images/welcome_mountain_lake.jpg',
      ),
      findsOneWidget,
    );
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Full name'), findsNothing);

    await t.tap(find.text('Register'));
    await t.pump();

    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Join ClimateEye'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);

    await t.enterText(find.byType(TextField).at(0), 'Ada Lovelace');
    await t.enterText(find.byType(TextField).at(1), 'ada@example.com');
    await t.enterText(find.byType(TextField).at(2), 'ada');
    await t.enterText(find.byType(TextField).at(3), 'secret1');
    await t.enterText(find.byType(TextField).at(4), 'secret1');

    final btn = find.byWidgetPredicate(
      (w) => w is GradientButton && w.label == 'Create Account',
    );
    t.widget<GradientButton>(btn).onPressed!();
    await t.pump();

    expect(
      find.text('User registration is not available yet. Please sign in.'),
      findsOneWidget,
    );
  });

  testWidgets('login validates empty credentials like the website', (t) async {
    await t.pumpWidget(const MaterialApp(home: LoginScreen()));
    await t.pump();
    final btn = find.byWidgetPredicate(
      (w) => w is GradientButton && w.label == 'Sign In',
    );
    t.widget<GradientButton>(btn).onPressed!();
    await t.pump();
    expect(find.text('Please enter both username and password'), findsOneWidget);
  });
}
