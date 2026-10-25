import 'package:drift/drift.dart';

/// Every table that syncs between devices extends this: a random UUID primary key, a
/// hybrid-logical-clock stamp of the last edit, and a tombstone flag so deletes propagate.
mixin SyncColumns on Table {
  TextColumn get id => text()();
  TextColumn get hlc => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A person whose use is tracked. Curves, tolerance and warnings are always per person.
@DataClassName('Person')
class People extends Table with SyncColumns {
  TextColumn get name => text()();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF6750A4))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

/// A session ("experience") with a title and notes, owned by one person.
class Experiences extends Table with SyncColumns {
  TextColumn get personId => text().references(People, #id)();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get sortDate => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get locationName => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
}

/// One logged dose.
class Ingestions extends Table with SyncColumns {
  TextColumn get experienceId => text().references(Experiences, #id)();
  // Denormalised from the experience so a per-person query never needs a join.
  TextColumn get personId => text().references(People, #id)();
  TextColumn get substanceKey => text()();
  TextColumn get route => text()();
  DateTimeColumn get time => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  RealColumn get dose => real().nullable()();
  TextColumn get unit => text().nullable()();
  BoolColumn get doseIsEstimate => boolean().withDefault(const Constant(false))();
  RealColumn get doseStdDev => real().nullable()();
  TextColumn get stomachFullness => text().nullable()();
  TextColumn get customUnitId => text().nullable()();
  TextColumn get productId => text().nullable()();
  RealColumn get absorbedMg => real().nullable()();
  TextColumn get method => text().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
}

class TimedNotes extends Table with SyncColumns {
  TextColumn get experienceId => text().references(Experiences, #id)();
  DateTimeColumn get time => dateTime()();
  TextColumn get note => text()();
  IntColumn get colorValue => integer().withDefault(const Constant(0xFF6750A4))();
  BoolColumn get showOnTimeline => boolean().withDefault(const Constant(true))();
}

class Ratings extends Table with SyncColumns {
  TextColumn get experienceId => text().references(Experiences, #id)();
  DateTimeColumn get time => dateTime().nullable()();
  // Shulgin scale: minus, plusMinus, plus1, plus2, plus3, plus4.
  TextColumn get shulgin => text().nullable()();
  // Optional 0-10 sliders, stored as JSON, e.g. {"mood":7,"pain":2}.
  TextColumn get scoresJson => text().withDefault(const Constant('{}'))();
}

/// "1 pill = 120 mg MDMA".
class CustomUnits extends Table with SyncColumns {
  TextColumn get substanceKey => text()();
  TextColumn get route => text()();
  TextColumn get name => text()();
  TextColumn get unitSingular => text()();
  TextColumn get unitPlural => text().nullable()();
  RealColumn get doseOfOneUnit => real().nullable()();
  RealColumn get doseStdDev => real().nullable()();
  TextColumn get originalUnit => text()();
  BoolColumn get isEstimate => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// A substance the reference data does not know.
class CustomSubstances extends Table with SyncColumns {
  TextColumn get name => text()();
  TextColumn get units => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
}

/// A specific product, e.g. a cannabis strain/batch with THC and CBD percentages.
class Products extends Table with SyncColumns {
  TextColumn get substanceKey => text()();
  TextColumn get name => text()();
  RealColumn get thcPercent => real().nullable()();
  RealColumn get cbdPercent => real().nullable()();
  TextColumn get detailsJson => text().withDefault(const Constant('{}'))();
}

/// Quick-add presets (a favourite drink, a usual dose).
class Presets extends Table with SyncColumns {
  TextColumn get substanceKey => text()();
  TextColumn get route => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  TextColumn get unit => text()();
  TextColumn get detailsJson => text().withDefault(const Constant('{}'))();
}

/// Key/value settings. Only rows with `shared = true` sync to other devices.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get hlc => text()();
  BoolColumn get shared => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {key};
}

/// Devices this one has paired with.
class Peers extends Table {
  TextColumn get deviceId => text()();
  TextColumn get name => text()();
  TextColumn get publicKey => text()();
  TextColumn get lastKnownAddress => text().nullable()();
  // Highest clock of this peer's changes we have already applied.
  TextColumn get lastSyncedHlc => text().withDefault(const Constant(''))();
  DateTimeColumn get pairedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {deviceId};
}
