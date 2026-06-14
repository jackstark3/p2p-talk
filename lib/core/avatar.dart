import 'dart:math';

import 'package:flutter/material.dart';

/// Generates a consistent avatar for a given name.
class AvatarGenerator {
  AvatarGenerator._();

  static final List<Color> _colors = [
    Colors.blue, Colors.green, Colors.orange, Colors.purple,
    Colors.teal, Colors.pink, Colors.indigo, Colors.red,
    Colors.amber.shade700!, Colors.cyan.shade700!,
  ];

  /// Returns a deterministic color based on the string.
  static Color colorFor(String text) {
    if (text.isEmpty) return Colors.grey;
    final hash = text.codeUnits.fold<int>(0, (v, c) => v * 31 + c).abs();
    return _colors[hash % _colors.length];
  }

  /// Returns the first displayable character.
  static String letterFor(String text) {
    if (text.isEmpty) return '?';
    final c = text[0].toUpperCase();
    // Use ascii letters/digits, fallback to first char
    if (RegExp(r'[A-Z0-9]').hasMatch(c)) return c;
    // Try to extract first ascii letter
    for (final ch in text.toUpperCase().characters) {
      if (RegExp(r'[A-Z0-9]').hasMatch(ch)) return ch;
    }
    return c;
  }

  /// Builds a CircleAvatar widget.
  static Widget build(String name, {double radius = 20}) {
    final letter = letterFor(name);
    final color = colorFor(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withOpacity(0.2),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: radius * 0.75,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}
