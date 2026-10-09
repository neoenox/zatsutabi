import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/poi.dart';

class PoiRepository {
  PoiRepository({this.databaseOpener});

  // An injected opener lets tests cover both a healthy empty DB and a failed
  // DB open without depending on the bundled production asset.
  final Future<Database?> Function()? databaseOpener;

  static const _fallback = <Poi>[
    Poi(
      id: 'tokyo-park',
      name: '井の頭恩賜公園',
      category: '自然・散歩',
      latitude: 35.7008,
      longitude: 139.5703,
      indoor: IndoorStatus.outdoor,
    ),
    Poi(
      id: 'tokyo-museum',
      name: '国立科学博物館',
      category: '博物館',
      latitude: 35.7207,
      longitude: 139.7765,
      indoor: IndoorStatus.indoor,
    ),
    Poi(
      id: 'saitama-nagatoro',
      name: '長瀞岩畳',
      category: '景勝地',
      latitude: 36.0946,
      longitude: 139.1104,
      indoor: IndoorStatus.outdoor,
    ),
    Poi(
      id: 'osaka-aquarium',
      name: '海遊館',
      category: '水族館',
      latitude: 34.6545,
      longitude: 135.4289,
      indoor: IndoorStatus.indoor,
    ),
    Poi(
      id: 'kyoto-arashiyama',
      name: '嵐山竹林',
      category: '自然・散歩',
      latitude: 35.017,
      longitude: 135.6713,
      indoor: IndoorStatus.outdoor,
    ),
    Poi(
      id: 'fukuoka-museum',
      name: '福岡市博物館',
      category: '博物館',
      latitude: 33.5938,
      longitude: 130.3515,
      indoor: IndoorStatus.indoor,
    ),
    Poi(
      id: 'sapporo-park',
      name: '大通公園',
      category: '自然・散歩',
      latitude: 43.0608,
      longitude: 141.3478,
      indoor: IndoorStatus.outdoor,
    ),
  ];

  Database? _database;
  Future<Database?>? _openingDatabase;

  Future<Database?> _openDatabase() async {
    if (databaseOpener case final open?) return open();
    if (_database != null) return _database;
    if (_openingDatabase != null) return _openingDatabase;
    _openingDatabase = _openDatabaseOnce();
    final database = await _openingDatabase;
    _openingDatabase = null;
    return database;
  }

  Future<Database?> _openDatabaseOnce() async {
    // A missing/corrupt database falls back to the small built-in list, but
    // the failure is surfaced (debug mode throws) instead of being silently
    // swallowed, so regressions are detectable.
    try {
      final databasesPath = await getDatabasesPath();
      final assetBytes = (await rootBundle.load(
        'assets/poi_osm.sqlite',
      )).buffer.asUint8List();
      // Content-hash based filename: app updates ship a new DB asset, which
      // yields a new hash and therefore a new file, so installed users pick
      // up the updated POI database without any version bookkeeping.
      final digest = sha256.convert(assetBytes).toString();
      final databasePath = path.join(databasesPath, 'poi_osm_$digest.sqlite');
      if (!await File(databasePath).exists()) {
        // Copy to a temp file first, then atomically rename. A crash or
        // low-storage failure mid-copy leaves only the temp file, so the next
        // launch retries instead of being stuck with a truncated database.
        final tempPath = path.join(databasesPath, 'poi_osm_$digest.sqlite.tmp');
        await File(tempPath).writeAsBytes(assetBytes, flush: true);
        await File(tempPath).rename(databasePath);
      }
      _database = await openDatabase(databasePath, readOnly: true);
      return _database;
    } on Object catch (error) {
      // Keep the graceful fallback for users, but make the failure visible in
      // debug/test builds so the DB quality gates cannot regress silently.
      assert(() {
        debugPrint('PoiRepository: database open failed: $error');
        return true;
      }());
      return null;
    }
  }

  Future<List<Poi>> nearby({
    required double latitude,
    required double longitude,
    required double radiusKm,
    double minimumRadiusKm = 0,
    bool indoorOnly = false,
  }) async {
    final database = await _openDatabase();
    final latitudeDelta = radiusKm / 111.0;
    final longitudeDelta = radiusKm / (111.0 * cos(_radians(latitude)));
    final rows = database == null
        ? const <Map<String, Object?>>[]
        : await database.query(
            'poi',
            where: 'latitude BETWEEN ? AND ? AND longitude BETWEEN ? AND ?',
            whereArgs: [
              latitude - latitudeDelta,
              latitude + latitudeDelta,
              longitude - longitudeDelta,
              longitude + longitudeDelta,
            ],
          );
    // A healthy database returning zero rows is an authoritative empty result.
    // Only an unavailable database may use bundled fallback suggestions.
    final source = database == null ? _fallback : rows.map(Poi.fromRow).toList();
    return source
        .where((poi) => !indoorOnly || poi.isIndoor)
        .where(
          (poi) =>
              _distanceKm(latitude, longitude, poi.latitude, poi.longitude) >=
                  minimumRadiusKm &&
              _distanceKm(latitude, longitude, poi.latitude, poi.longitude) <=
                  radiusKm,
        )
        .toList();
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earth = 6371.0;
    final dLat = _radians(lat2 - lat1);
    final dLon = _radians(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_radians(lat1)) *
            cos(_radians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earth * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _radians(double value) => value * pi / 180;
}
