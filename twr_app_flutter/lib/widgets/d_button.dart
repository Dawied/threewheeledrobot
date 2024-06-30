import 'package:flutter/material.dart';

class DButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const DButton({super.key, required this.onPressed, required this.label});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
