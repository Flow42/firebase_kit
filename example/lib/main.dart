import 'package:firebase_kit/firebase_kit.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  final kit = await FirebaseKit.initialize(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(ExampleApp(auth: kit.auth));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, required this.auth});

  final AuthService auth;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'firebase_kit Example',
      home: Scaffold(
        appBar: AppBar(title: const Text('firebase_kit Example')),
        body: StreamBuilder<AuthUser?>(
          stream: auth.authStateChanges(),
          initialData: auth.currentUser,
          builder: (context, snapshot) {
            final user = snapshot.data;
            return Center(
              child: Text(
                user == null ? 'Signed out' : 'Signed in as ${user.label}',
              ),
            );
          },
        ),
      ),
    );
  }
}
