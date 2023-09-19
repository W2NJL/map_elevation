library map_elevation;

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart' as lg;
import 'package:wtfda_radioland/classes/unitOfMeasurement.dart';
import 'package:wtfda_radioland/src/fm_station.dart';
import 'package:wtfda_radioland/classes/radioLandSearchValues.dart';
import 'package:wtfda_radioland/classes/helperFunctions.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:wtfda_radioland/util/constants.dart';

/// Elevation statefull widget
class Elevation extends StatefulWidget {
  final RadioStation radioStation;
  final RadioLandSearchValues radioLandSearchValues;
  final double yourHAGL;
  final lg.LatLng transmitter;
  final lg.LatLng receiver;
  /// List of points to draw on elevation widget
  /// Lat and Long are required to emit notification on hover
  final List<ElevationPoint> points;

  /// Background color of the elevation graph
  final Color? color;

  /// Elevation gradient colors
  /// See [ElevationGradientColors] for more details
  final ElevationGradientColors? elevationGradientColors;

  /// [WidgetBuilder] like Function to add child over the graph
  final Function(BuildContext context, Size size)? child;

  Elevation(this.points, this.radioLandSearchValues, this.radioStation, this.yourHAGL,
      {this.color, this.elevationGradientColors, this.child, required this.transmitter, required this.receiver});

  @override
  State<StatefulWidget> createState() => _ElevationState();
}

class _ElevationState extends State<Elevation> {
  double? _hoverLinePosition;
  double? _hoveredAltitude;

  @override
// Helper function
  Widget _buildPositionedText(String text, double left, double bottom, bool leftAlign) {
    return Positioned(
      left: leftAlign ? left - 50.w : left.w, // Subtract additional value if leftAlign is true
      bottom: bottom.h,
      child: Container(
        padding: EdgeInsets.all(3),
        color: Colors.white.withOpacity(0.8),
        child: Text(
          text,
          style: TextStyle(fontSize: 9.sp, color: Colors.black, fontWeight: FontWeight.w600),
          textAlign: leftAlign ? TextAlign.right : TextAlign.left, // Align text based on leftAlign
        ),
      ),
    );
  }

  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints bc) {
      Offset _lbPadding = Offset(35, 6);
      _ElevationPainter elevationPainter = _ElevationPainter(widget.points,
          unitOfMeasurement: widget.radioLandSearchValues.unitsOfMeasurement!,
          paintColor: widget.color ?? Colors.transparent,
          receiver: widget.receiver,
          transmitter: widget.transmitter,
          elevationGradientColors: widget.elevationGradientColors,
          lbPadding: _lbPadding, transmitterAMSL: double.parse(widget.radioStation.amslValue), radioStationDistance: widget.radioStation.distance);
      return GestureDetector(
          onHorizontalDragUpdate: (DragUpdateDetails details) {
            final pointFromPosition = elevationPainter
                .getPointFromPosition(details.globalPosition.dx);

            if (pointFromPosition != null) {
              ElevationHoverNotification(pointFromPosition)..dispatch(context);
              setState(() {
                _hoverLinePosition = details.globalPosition.dx;
                _hoveredAltitude = pointFromPosition.altitude;
              });
            }
          },
          onHorizontalDragEnd: (DragEndDetails details) {
            ElevationHoverNotification(null)..dispatch(context);
            setState(() {
              _hoverLinePosition = null;
            });
          },
          child: Stack(children: <Widget>[
            CustomPaint(
              painter: elevationPainter,
              size: Size(bc.maxWidth, bc.maxHeight),
            ),



            if (widget.child != null && widget.child is Function)
              Container(
                margin: EdgeInsets.only(left: _lbPadding.dx),
                width: bc.maxWidth - _lbPadding.dx,
                height: bc.maxHeight - _lbPadding.dy,
                child: Builder(
                    builder: (BuildContext context) => widget.child!(
                        context,
                        Size(bc.maxWidth - _lbPadding.dx,
                            bc.maxHeight - _lbPadding.dy))),
              ),
            if (_hoverLinePosition != null)
              Positioned(
                left: _hoverLinePosition,
                top: 0,
                child: Container(
                  height: bc.maxHeight,
                  width: 1,
                  decoration: BoxDecoration(color: Colors.black),
                ),
              ),
            if (_hoverLinePosition != null)
              Positioned(
                left: _hoverLinePosition,
                top: 0,
                child: Container(
                  height: bc.maxHeight,
                  width: 1,
                  decoration: BoxDecoration(color: Colors.black),
                ),
              ),
            if (_hoverLinePosition != null && _hoveredAltitude != null)
              _buildPositionedText(
                widget.radioLandSearchValues.unitsOfMeasurement == UnitOfMeasurement.metric
                    ? '${(_hoveredAltitude!*convertFtToM).round()} m.'
                    : '${_hoveredAltitude!.round()} ft.',
                _hoverLinePosition!, // Adjust this value as needed
                90, // Adjust this value as needed
                _hoverLinePosition! > bc.maxWidth * 0.8, // Text will align to left if hoverLinePosition is > 80% of widget width
              ),
          ]));
    });
  }

}

class _ElevationPainter extends CustomPainter {
  List<ElevationPoint> points;
  late List<double> _relativeAltitudes;
  Color paintColor;
  Offset lbPadding;
  late int _min, _max;
  late double widthOffset;
  lg.LatLng transmitter;
  lg.LatLng receiver;
  double? transmitterPosition;
  double? receiverPosition;
  double transmitterAMSL;
  double radioStationDistance;
  UnitOfMeasurement unitOfMeasurement;
  ElevationGradientColors? elevationGradientColors;

  _ElevationPainter(this.points,
      {required this.paintColor,
        required this.transmitterAMSL,
        required this.radioStationDistance,
        required this.unitOfMeasurement,
      this.lbPadding = Offset.zero,
        required this.transmitter, // Add this
        required this.receiver,    // Add this
      this.elevationGradientColors}) {
    _min = (points.map((point) => point.altitude).toList().reduce(min) / 100)
            .floor() *
        100;
    _max = (points.map((point) => point.altitude).toList().reduce(max) / 100)
            .ceil() *
        100;

    _relativeAltitudes =
        points.map((point) => (point.altitude - _min) / (_max - _min)).toList();
  }

  double _getCurvatureDropForPoint(int index) {
    // Assuming the first point is the transmitter and the last point is the receiver
    // Calculate the ratio of where this point stands in the entire line
    double ratio = index / points.length;

    // Calculate the distance this point is from the transmitter using the ratio
    double distanceFromTransmitter = radioStationDistance * miToKm * ratio;

    // Return the curvature drop for this point
    return _curvatureDrop(distanceFromTransmitter);
  }

  double? _getPointPosition(lg.LatLng point) {
    print('Baby');
    print(point.longitude);
    for (int i = 0; i < points.length - 1; i++) {
      if ((points[i].longitude <= point.longitude && points[i + 1].longitude >= point.longitude) ||
          (points[i].longitude >= point.longitude && points[i + 1].longitude <= point.longitude)) {
        return (i + 0.5) * widthOffset + lbPadding.dx;
      }
    }
    return null;
  }

  double _curvatureDrop(double distance) {
    const double earthRadius = 6371; // in kilometers
    return (distance * distance) / (2 * earthRadius);
  }



  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);



    final paint = Paint()
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.src
      ..style = PaintingStyle.fill
      ..color = paintColor;
    final axisPaint = Paint()
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..blendMode = BlendMode.src
      ..style = PaintingStyle.stroke;



    if (elevationGradientColors != null) {
      List<Color> gradientColors = [paintColor];
      for (int i = 1; i < points.length; i++) {
        double dX = lg.Distance().distance(points[i], points[i - 1]);
        double dZ = (points[i].altitude - points[i - 1].altitude);

        double gradient = 100 * dZ / dX;
        if (gradient > 30) {
          gradientColors.add(elevationGradientColors!.gt30);
        } else if (gradient > 20) {
          gradientColors.add(elevationGradientColors!.gt20);
        } else if (gradient > 10) {
          gradientColors.add(elevationGradientColors!.gt10);
        } else {
          gradientColors.add(paintColor);
        }
      }

      paint.shader = ui.Gradient.linear(
          Offset(lbPadding.dx, 0),
          Offset(size.width, 0),
          gradientColors,
          _calculateColorsStop(gradientColors));
    }

    canvas.saveLayer(rect, Paint());

    widthOffset = (size.width - lbPadding.dx) / _relativeAltitudes.length;

    final path = Path()
      ..moveTo(lbPadding.dx, _getYForAltitude(_relativeAltitudes[0], size));
    _relativeAltitudes.asMap().forEach((int index, double altitude) {
      // Deduct the curvature drop from the altitude of each point
      double drop = _getCurvatureDropForPoint(index);
      double adjustedAltitude = altitude + (drop / (_max - _min));

      path.lineTo(
          index * widthOffset + lbPadding.dx, _getYForAltitude(adjustedAltitude, size));
    });
    path.lineTo(size.width, size.height - lbPadding.dy);
    path.lineTo(lbPadding.dx, size.height - lbPadding.dy);


    canvas.drawPath(path, paint);
    canvas.drawLine(Offset(lbPadding.dx, 0),
        Offset(lbPadding.dx, size.height - lbPadding.dy), axisPaint);

    int roundedAltitudeDiff = _max.ceil() - _min.floor();
    int axisStep = max(100, (roundedAltitudeDiff / 5).round());

    List<double>.generate((roundedAltitudeDiff / axisStep).round(),
        (i) => (axisStep * i + _min).toDouble()).forEach((altitude) {
      double relativeAltitude = (altitude - _min) / (_max - _min);
      canvas.drawLine(
          Offset(lbPadding.dx, _getYForAltitude(relativeAltitude, size)),
          Offset(lbPadding.dx + 10, _getYForAltitude(relativeAltitude, size)),
          axisPaint);
      TextPainter(
          text: TextSpan(
              style: TextStyle(color: Colors.black, fontSize: 10),
              text: unitOfMeasurement==UnitOfMeasurement.metric?(altitude*convertFtToM).round().toString():altitude.toInt().toString()),
          textDirection: TextDirection.ltr)
        ..layout()
        ..paint(
            canvas, Offset(5, _getYForAltitude(relativeAltitude, size) - 5));
    });

    transmitterPosition = _getPointPosition(transmitter);
    receiverPosition = _getPointPosition(receiver);
    double distanceFromTransmitter = radioStationDistance*miToKm; // Assuming distanceTo is the method to get distance
    double transmitterCurvatureDrop = _curvatureDrop(distanceFromTransmitter);

    double transmitterAdjustedAltitude = points.first.altitude - transmitterCurvatureDrop;
    double relativeTransmitterAltitude = (transmitterAdjustedAltitude - _min) / (_max - _min);
    double transmitterY = _getYForAltitude(relativeTransmitterAltitude, size);

    double receiverCurvatureDrop = _curvatureDrop(0);  // Receiver is the reference, so curvature drop is 0
    double receiverAdjustedAltitude = points.elementAt(points.length-1).altitude - receiverCurvatureDrop;
    double relativeReceiverAltitude = (receiverAdjustedAltitude - _min) / (_max - _min);
    double receiverY = _getYForAltitude(relativeReceiverAltitude, size);



    if (transmitterPosition != null && receiverPosition != null) {

      final linePaint = Paint()
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.red;

      double startY = size.height - lbPadding.dy;
      double endY = _getYForAltitude(1, size);

      canvas.drawLine(Offset(receiverPosition!, receiverY), Offset(transmitterPosition!, transmitterY), linePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;

  double _getYForAltitude(double altitude, Size size) {
    final double maxAltitude = _relativeAltitudes.reduce(max);
    final double minAltitude = _relativeAltitudes.reduce(min);
    final double range = maxAltitude - minAltitude;

    if (range == 0) { // Avoid division by zero
      return size.height / 2; // Or any default position you prefer
    }

    double relativePosition = (altitude - minAltitude) / range;
    return size.height - (relativePosition * (size.height - 2 * lbPadding.dy) + lbPadding.dy);
  }


  ElevationPoint? getPointFromPosition(double position) {
    int index = ((position - lbPadding.dx) / widthOffset).round();

    if (index >= points.length || index < 0) return null;

    return points[index];
  }

  List<double> _calculateColorsStop(List gradientColors) {
    final colorsStopInterval = 1.0 / gradientColors.length;
    return List.generate(
        gradientColors.length, (index) => index * colorsStopInterval);
  }
}

/// [Notification] emitted when graph is hovered
class ElevationHoverNotification extends Notification {
  /// Hovered point coordinates
  final ElevationPoint? position;

  ElevationHoverNotification(this.position);
}

/// Elevation gradient colors
/// Not color is used when gradient is < 10% (graph background color is used [Elevation.color])
class ElevationGradientColors {
  /// Used when elevation gradient is > 10%
  final Color gt10;

  /// Used when elevation gradient is > 20%
  final Color gt20;

  /// Used when elevation gradient is > 30%
  final Color gt30;

  ElevationGradientColors(
      {required this.gt10, required this.gt20, required this.gt30});
}

/// Geographic point with elevation
class ElevationPoint extends lg.LatLng {
  /// Altitude (in meters)
  double altitude;

  ElevationPoint(double latitude, double longitude, this.altitude)
      : super(latitude, longitude);

  lg.LatLng get latLng => this;
}
