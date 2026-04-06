import 'package:flutter/material.dart';

class V3PromenaSifreScreen extends StatelessWidget {
  final String vozacIme;

  const V3PromenaSifreScreen({super.key, required this.vozacIme});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Informacija')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Ova opcija više nije dostupna.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}
