import 'package:flutter/material.dart';
import 'spring_press.dart';

class ScaleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const ScaleButton({super.key, required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) => SpringPress(onTap: onTap, child: child);
}
