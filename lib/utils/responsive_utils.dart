import 'package:flutter/material.dart';
import '../config/app_config.dart';

class ResponsiveUtils {
  static bool isTablet(BuildContext context) {
    return MediaQuery.of(context).size.shortestSide >= AppConfig.tabletBreakpoint;
  }

  static double getResponsiveFontSize(BuildContext context, double baseSize) {
    return isTablet(context) ? baseSize * 1.2 : baseSize;
  }

  static EdgeInsets getResponsivePadding(BuildContext context) {
    return isTablet(context)
        ? const EdgeInsets.all(32)
        : const EdgeInsets.all(16);
  }

  static double getResponsiveWidth(BuildContext context, double percentage) {
    return MediaQuery.of(context).size.width * percentage;
  }
}
