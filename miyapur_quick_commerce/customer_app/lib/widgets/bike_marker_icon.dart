import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Generates high-fidelity, Zomato/Zepto-style animated bitmap markers for live
/// quick-commerce order tracking in Miyapur:
///
/// 1. [createZomatoBikeMarker]: Custom delivery bike with floating ETA badge ("⚡ ~8 mins")
///    and directional heading indicator.
/// 2. [createStoreHubMarker]: Distinct dark store hub pin ("🏬 Miyapur Central Hub").
/// 3. [createCustomerHomeMarker]: Distinct delivery address pin ("🏠 Your Address").
class BikeMarkerIcon {
  BikeMarkerIcon._();

  static final Map<String, BitmapDescriptor> _cache = {};

  /// Generates the signature Zomato-style rider marker with a floating ETA pill
  /// and animated bike orientation.
  static Future<BitmapDescriptor> createZomatoBikeMarker({
    required int etaMins,
    double headingDeg = 0.0,
    String riderName = "Ravi",
  }) async {
    // Quantize heading to 5-degree increments to keep the memory cache compact
    final quantHeading = (headingDeg / 5).round() * 5;
    final key = "zomato_bike_${etaMins}_$quantHeading";
    if (_cache.containsKey(key)) return _cache[key]!;

    const double width = 160.0;
    const double height = 150.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, width, height));

    // 1. Top Floating ETA Pill ("⚡ ~8 mins")
    const double pillWidth = 126.0;
    const double pillHeight = 32.0;
    const double pillLeft = (width - pillWidth) / 2;
    const double pillTop = 4.0;

    // Pill shadow
    final pillShadowPaint = ui.Paint()
      ..color = const ui.Color(0x33000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 6);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(pillLeft, pillTop + 2, pillWidth, pillHeight),
        const ui.Radius.circular(16),
      ),
      pillShadowPaint,
    );

    // Pill body (Brand Emerald Green)
    final pillPaint = ui.Paint()
      ..color = const ui.Color(0xFF059669)
      ..style = ui.PaintingStyle.fill;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight),
        const ui.Radius.circular(16),
      ),
      pillPaint,
    );

    // Pill border
    final pillBorderPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight),
        const ui.Radius.circular(16),
      ),
      pillBorderPaint,
    );

    // Downward arrow pointer under the pill
    final pointerPath = ui.Path()
      ..moveTo(width / 2 - 6, pillTop + pillHeight)
      ..lineTo(width / 2 + 6, pillTop + pillHeight)
      ..lineTo(width / 2, pillTop + pillHeight + 6)
      ..close();
    canvas.drawPath(pointerPath, pillPaint);

    // Pill Text
    final textSpan = TextSpan(
      text: "⚡ ~$etaMins MINS • $riderName",
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.3,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, pillTop + (pillHeight - textPainter.height) / 2),
    );

    // 2. Bike Circle Disc (x: width/2, y: 92)
    const double circleCenterX = width / 2;
    const double circleCenterY = 92.0;
    const double discRadius = 34.0;

    // Glowing Pulse Halo
    final haloPaint = ui.Paint()
      ..color = const ui.Color(0x33059669)
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const Offset(circleCenterX, circleCenterY), discRadius + 8, haloPaint);

    // Drop shadow under bike disc
    final discShadow = ui.Paint()
      ..color = const ui.Color(0x33000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5);
    canvas.drawCircle(const Offset(circleCenterX, circleCenterY + 2), discRadius, discShadow);

    // White disc base
    final discPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const Offset(circleCenterX, circleCenterY), discRadius, discPaint);

    // Emerald border ring
    final discBorder = ui.Paint()
      ..color = const ui.Color(0xFF059669)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(const Offset(circleCenterX, circleCenterY), discRadius, discBorder);

    // 3. Render Scooter Silhouette (Rotated according to headingDeg)
    canvas.save();
    canvas.translate(circleCenterX, circleCenterY);
    // Google Maps bearings: 0 is North. Standard canvas 0 is East. Adjust by -90 deg.
    final rotRad = (headingDeg - 90) * math.pi / 180.0;
    canvas.rotate(rotRad);
    _drawZomatoScooter(canvas);
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen);
    }
    final bytes = byteData.buffer.asUint8List();
    final descriptor = BitmapDescriptor.fromBytes(bytes);
    _cache[key] = descriptor;
    return descriptor;
  }

  /// Draws a detailed Zomato/Zepto-style delivery scooter with delivery box and rider.
  static void _drawZomatoScooter(ui.Canvas canvas) {
    // Wheels (Front & Rear)
    final wheelTirePaint = ui.Paint()
      ..color = const ui.Color(0xFF1E293B)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.5;
    final wheelHubPaint = ui.Paint()
      ..color = const ui.Color(0xFF94A3B8)
      ..style = ui.PaintingStyle.fill;

    const double rearWheelX = -13.0;
    const double frontWheelX = 13.0;
    const double wheelY = 10.0;
    const double wheelR = 6.0;

    // Rear Wheel
    canvas.drawCircle(const Offset(rearWheelX, wheelY), wheelR, wheelTirePaint);
    canvas.drawCircle(const Offset(rearWheelX, wheelY), 2.2, wheelHubPaint);

    // Front Wheel
    canvas.drawCircle(const Offset(frontWheelX, wheelY), wheelR, wheelTirePaint);
    canvas.drawCircle(const Offset(frontWheelX, wheelY), 2.2, wheelHubPaint);

    // Chassis / Footboard line
    final framePaint = ui.Paint()
      ..color = const ui.Color(0xFF1E293B)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(const Offset(rearWheelX, wheelY - 2), const Offset(frontWheelX, wheelY - 2), framePaint);

    // Delivery Box (Zomato / Flash Fresh Green Hot-Bag)
    final boxPaint = ui.Paint()
      ..color = const ui.Color(0xFF059669)
      ..style = ui.PaintingStyle.fill;
    final boxBorder = ui.Paint()
      ..color = const ui.Color(0xFF064E3B)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final boxRect = ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(-17, -10, 11, 14),
      const ui.Radius.circular(2.5),
    );
    canvas.drawRRect(boxRect, boxPaint);
    canvas.drawRRect(boxRect, boxBorder);

    // Rider Torso & Seat
    final riderPaint = ui.Paint()
      ..color = const ui.Color(0xFF0F172A)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(const Offset(-4, 4), const Offset(2, -7), riderPaint);

    // Rider Helmet
    final helmetPaint = ui.Paint()
      ..color = const ui.Color(0xFFF59E0B) // Amber protective helmet
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const Offset(2, -12), 4.8, helmetPaint);

    // Handlebar Stem
    final barPaint = ui.Paint()
      ..color = const ui.Color(0xFF334155)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(const Offset(9, 6), const Offset(11, -5), barPaint);
    canvas.drawLine(const Offset(8, -5), const Offset(14, -5), barPaint);

    // Amber Headlight Beam dot
    final lightPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFD700)
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const Offset(15, -1), 3.0, lightPaint);
  }

  /// Dark Store Hub Marker ("🏬 Miyapur Central Hub")
  static Future<BitmapDescriptor> createStoreHubMarker() async {
    const key = "hub_marker_pin";
    if (_cache.containsKey(key)) return _cache[key]!;

    const double width = 140.0;
    const double height = 100.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, width, height));

    // 1. Top Pill ("🏬 Dark Store Hub")
    const double pillWidth = 132.0;
    const double pillHeight = 28.0;
    const double pillLeft = (width - pillWidth) / 2;
    const double pillTop = 4.0;

    final pillPaint = ui.Paint()
      ..color = const ui.Color(0xFF064E3B)
      ..style = ui.PaintingStyle.fill;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight),
        const ui.Radius.circular(14),
      ),
      pillPaint,
    );

    // Border
    final pillBorder = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight),
        const ui.Radius.circular(14),
      ),
      pillBorder,
    );

    // Pointer
    final pointer = ui.Path()
      ..moveTo(width / 2 - 5, pillTop + pillHeight)
      ..lineTo(width / 2 + 5, pillTop + pillHeight)
      ..lineTo(width / 2, pillTop + pillHeight + 5)
      ..close();
    canvas.drawPath(pointer, pillPaint);

    // Text
    final textPainter = TextPainter(
      text: const TextSpan(
        text: "🏬 MIYAPUR DARK STORE",
        style: TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, pillTop + (pillHeight - textPainter.height) / 2),
    );

    // 2. Hub Circle Pin
    const double cx = width / 2;
    const double cy = 64.0;
    const double r = 22.0;

    final shadowPaint = ui.Paint()
      ..color = const ui.Color(0x33000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(const Offset(cx, cy + 2), r, shadowPaint);

    final basePaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const Offset(cx, cy), r, basePaint);

    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFF064E3B)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(const Offset(cx, cy), r, borderPaint);

    // Store building icon inside
    final storePaint = ui.Paint()
      ..color = const ui.Color(0xFF064E3B)
      ..style = ui.PaintingStyle.fill;
    // Awning
    canvas.drawRect(const ui.Rect.fromLTWH(cx - 10, cy - 8, 20, 6), storePaint);
    // Base walls
    canvas.drawRect(const ui.Rect.fromLTWH(cx - 9, cy - 2, 18, 12), storePaint);
    // Door (white cutout)
    final doorPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill;
    canvas.drawRect(const ui.Rect.fromLTWH(cx - 3, cy + 3, 6, 7), doorPaint);

    // Pin needle tip
    final needlePath = ui.Path()
      ..moveTo(cx - 5, cy + r - 2)
      ..lineTo(cx + 5, cy + r - 2)
      ..lineTo(cx, cy + r + 8)
      ..close();
    canvas.drawPath(needlePath, pillPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
    }
    final bytes = byteData.buffer.asUint8List();
    final descriptor = BitmapDescriptor.fromBytes(bytes);
    _cache[key] = descriptor;
    return descriptor;
  }

  /// Customer Home Delivery Destination Pin ("🏠 Your Address")
  static Future<BitmapDescriptor> createCustomerHomeMarker({String label = "Your Address"}) async {
    final key = "dest_marker_${label.hashCode}";
    if (_cache.containsKey(key)) return _cache[key]!;

    const double width = 140.0;
    const double height = 100.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, const ui.Rect.fromLTWH(0, 0, width, height));

    // 1. Top Pill ("🏠 Your Address")
    const double pillWidth = 126.0;
    const double pillHeight = 28.0;
    const double pillLeft = (width - pillWidth) / 2;
    const double pillTop = 4.0;

    final pillPaint = ui.Paint()
      ..color = const ui.Color(0xFFDC2626) // Crimson Red
      ..style = ui.PaintingStyle.fill;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight),
        const ui.Radius.circular(14),
      ),
      pillPaint,
    );

    final pillBorder = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(pillLeft, pillTop, pillWidth, pillHeight),
        const ui.Radius.circular(14),
      ),
      pillBorder,
    );

    // Pointer
    final pointer = ui.Path()
      ..moveTo(width / 2 - 5, pillTop + pillHeight)
      ..lineTo(width / 2 + 5, pillTop + pillHeight)
      ..lineTo(width / 2, pillTop + pillHeight + 5)
      ..close();
    canvas.drawPath(pointer, pillPaint);

    // Text
    final textPainter = TextPainter(
      text: TextSpan(
        text: "🏠 $label".toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: pillWidth - 10);
    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, pillTop + (pillHeight - textPainter.height) / 2),
    );

    // 2. Home Circle Pin
    const double cx = width / 2;
    const double cy = 64.0;
    const double r = 22.0;

    final shadowPaint = ui.Paint()
      ..color = const ui.Color(0x33000000)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawCircle(const Offset(cx, cy + 2), r, shadowPaint);

    final basePaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill;
    canvas.drawCircle(const Offset(cx, cy), r, basePaint);

    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFFDC2626)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(const Offset(cx, cy), r, borderPaint);

    // House silhouette inside
    final housePaint = ui.Paint()
      ..color = const ui.Color(0xFFDC2626)
      ..style = ui.PaintingStyle.fill;
    // Roof triangle
    final roofPath = ui.Path()
      ..moveTo(cx, cy - 10)
      ..lineTo(cx + 10, cy - 1)
      ..lineTo(cx - 10, cy - 1)
      ..close();
    canvas.drawPath(roofPath, housePaint);
    // House body
    canvas.drawRect(const ui.Rect.fromLTWH(cx - 8, cy - 1, 16, 12), housePaint);
    // Door cutout (white)
    final doorPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..style = ui.PaintingStyle.fill;
    canvas.drawRect(const ui.Rect.fromLTWH(cx - 3, cy + 3, 6, 8), doorPaint);

    // Pin needle tip
    final needlePath = ui.Path()
      ..moveTo(cx - 5, cy + r - 2)
      ..lineTo(cx + 5, cy + r - 2)
      ..lineTo(cx, cy + r + 8)
      ..close();
    canvas.drawPath(needlePath, pillPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
    }
    final bytes = byteData.buffer.asUint8List();
    final descriptor = BitmapDescriptor.fromBytes(bytes);
    _cache[key] = descriptor;
    return descriptor;
  }

  /// Backward compatibility helper
  static Future<BitmapDescriptor> create({
    String colorHex = "#059669",
    String label = "Rider",
    double? headingDeg,
  }) async {
    return createZomatoBikeMarker(
      etaMins: 10,
      headingDeg: headingDeg ?? 0.0,
      riderName: label,
    );
  }
}
