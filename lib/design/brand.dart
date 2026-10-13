import 'package:flutter/material.dart';

class UptrackBrand extends StatelessWidget {
  const UptrackBrand({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Uptrack',
    image: true,
    excludeSemantics: true,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Image.asset(
        Theme.of(context).brightness == Brightness.dark
            ? 'assets/brand/uptrack-wordmark-dark.png'
            : 'assets/brand/uptrack-wordmark-light.png',
        width: 160,
        height: 48,
        fit: BoxFit.contain,
      ),
    ),
  );
}
