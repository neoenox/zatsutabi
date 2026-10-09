import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:zatsutabi/data/poi_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> createPoiDatabase() async {
    final db = await openDatabase(inMemoryDatabasePath);
    await db.execute('''
      CREATE TABLE poi (
        id TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        indoor INTEGER NOT NULL
      )
    ''');
    addTearDown(db.close);
    return db;
  }

  test('healthy DB with zero nearby rows does not leak static fallback POIs', () async {
    final db = await createPoiDatabase();
    final repository = PoiRepository(databaseOpener: () async => db);

    final nearby = await repository.nearby(
      latitude: 35.7008,
      longitude: 139.5703,
      radiusKm: 1,
    );

    expect(nearby, isEmpty);
  });

  test('healthy DB returns only its own nearby rows', () async {
    final db = await createPoiDatabase();
    await db.insert('poi', {
      'id': 'from-db',
      'name': 'DBの公園',
      'category': '自然・散歩',
      'latitude': 35.7008,
      'longitude': 139.5703,
      'indoor': 0,
    });
    final repository = PoiRepository(databaseOpener: () async => db);

    final nearby = await repository.nearby(
      latitude: 35.7008,
      longitude: 139.5703,
      radiusKm: 1,
    );

    expect(nearby.map((poi) => poi.id), ['from-db']);
  });

  test('unavailable DB still uses static fallback POIs', () async {
    final repository = PoiRepository(databaseOpener: () async => null);

    final nearby = await repository.nearby(
      latitude: 35.7008,
      longitude: 139.5703,
      radiusKm: 1,
    );

    expect(nearby.map((poi) => poi.id), contains('tokyo-park'));
  });
}
