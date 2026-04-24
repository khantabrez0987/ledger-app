import 'package:flutter/material.dart';

class CompanyLogo extends StatelessWidget {
  const CompanyLogo({
    super.key,
    this.height = 180,
    this.fit = BoxFit.contain,
  });

  final double height;
  final BoxFit fit;

  static const String assetPath = 'assets/images/company_logo.png';
  static const String pdfAssetPath = 'assets/images/pdf_logo.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
    );
  }
}
