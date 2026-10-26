// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $PeopleTable extends People with TableInfo<$PeopleTable, Person> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeopleTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFF6750A4),
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    name,
    colorValue,
    isDefault,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'people';
  @override
  VerificationContext validateIntegrity(
    Insertable<Person> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Person map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Person(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
    );
  }

  @override
  $PeopleTable createAlias(String alias) {
    return $PeopleTable(attachedDatabase, alias);
  }
}

class Person extends DataClass implements Insertable<Person> {
  final String id;
  final String hlc;
  final bool deleted;
  final String name;
  final int colorValue;
  final bool isDefault;
  const Person({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.name,
    required this.colorValue,
    required this.isDefault,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    map['is_default'] = Variable<bool>(isDefault);
    return map;
  }

  PeopleCompanion toCompanion(bool nullToAbsent) {
    return PeopleCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      name: Value(name),
      colorValue: Value(colorValue),
      isDefault: Value(isDefault),
    );
  }

  factory Person.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Person(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
      'isDefault': serializer.toJson<bool>(isDefault),
    };
  }

  Person copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? name,
    int? colorValue,
    bool? isDefault,
  }) => Person(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    isDefault: isDefault ?? this.isDefault,
  );
  Person copyWithCompanion(PeopleCompanion data) {
    return Person(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      name: data.name.present ? data.name.value : this.name,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Person(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('isDefault: $isDefault')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, hlc, deleted, name, colorValue, isDefault);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Person &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.name == this.name &&
          other.colorValue == this.colorValue &&
          other.isDefault == this.isDefault);
}

class PeopleCompanion extends UpdateCompanion<Person> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> name;
  final Value<int> colorValue;
  final Value<bool> isDefault;
  final Value<int> rowid;
  const PeopleCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeopleCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String name,
    this.colorValue = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       name = Value(name);
  static Insertable<Person> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? name,
    Expression<int>? colorValue,
    Expression<bool>? isDefault,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
      if (isDefault != null) 'is_default': isDefault,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeopleCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? name,
    Value<int>? colorValue,
    Value<bool>? isDefault,
    Value<int>? rowid,
  }) {
    return PeopleCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      isDefault: isDefault ?? this.isDefault,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeopleCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('isDefault: $isDefault, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExperiencesTable extends Experiences
    with TableInfo<$ExperiencesTable, Experience> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExperiencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<String> personId = GeneratedColumn<String>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES people (id)',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sortDateMeta = const VerificationMeta(
    'sortDate',
  );
  @override
  late final GeneratedColumn<DateTime> sortDate = GeneratedColumn<DateTime>(
    'sort_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _locationNameMeta = const VerificationMeta(
    'locationName',
  );
  @override
  late final GeneratedColumn<String> locationName = GeneratedColumn<String>(
    'location_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    personId,
    title,
    notes,
    sortDate,
    createdAt,
    isFavorite,
    locationName,
    latitude,
    longitude,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'experiences';
  @override
  VerificationContext validateIntegrity(
    Insertable<Experience> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('sort_date')) {
      context.handle(
        _sortDateMeta,
        sortDate.isAcceptableOrUnknown(data['sort_date']!, _sortDateMeta),
      );
    } else if (isInserting) {
      context.missing(_sortDateMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    }
    if (data.containsKey('location_name')) {
      context.handle(
        _locationNameMeta,
        locationName.isAcceptableOrUnknown(
          data['location_name']!,
          _locationNameMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Experience map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Experience(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      sortDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}sort_date'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      locationName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_name'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
    );
  }

  @override
  $ExperiencesTable createAlias(String alias) {
    return $ExperiencesTable(attachedDatabase, alias);
  }
}

class Experience extends DataClass implements Insertable<Experience> {
  final String id;
  final String hlc;
  final bool deleted;
  final String personId;
  final String title;
  final String notes;
  final DateTime sortDate;
  final DateTime createdAt;
  final bool isFavorite;
  final String? locationName;
  final double? latitude;
  final double? longitude;
  const Experience({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.personId,
    required this.title,
    required this.notes,
    required this.sortDate,
    required this.createdAt,
    required this.isFavorite,
    this.locationName,
    this.latitude,
    this.longitude,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['person_id'] = Variable<String>(personId);
    map['title'] = Variable<String>(title);
    map['notes'] = Variable<String>(notes);
    map['sort_date'] = Variable<DateTime>(sortDate);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['is_favorite'] = Variable<bool>(isFavorite);
    if (!nullToAbsent || locationName != null) {
      map['location_name'] = Variable<String>(locationName);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    return map;
  }

  ExperiencesCompanion toCompanion(bool nullToAbsent) {
    return ExperiencesCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      personId: Value(personId),
      title: Value(title),
      notes: Value(notes),
      sortDate: Value(sortDate),
      createdAt: Value(createdAt),
      isFavorite: Value(isFavorite),
      locationName: locationName == null && nullToAbsent
          ? const Value.absent()
          : Value(locationName),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
    );
  }

  factory Experience.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Experience(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      personId: serializer.fromJson<String>(json['personId']),
      title: serializer.fromJson<String>(json['title']),
      notes: serializer.fromJson<String>(json['notes']),
      sortDate: serializer.fromJson<DateTime>(json['sortDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      locationName: serializer.fromJson<String?>(json['locationName']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'personId': serializer.toJson<String>(personId),
      'title': serializer.toJson<String>(title),
      'notes': serializer.toJson<String>(notes),
      'sortDate': serializer.toJson<DateTime>(sortDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'locationName': serializer.toJson<String?>(locationName),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
    };
  }

  Experience copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? personId,
    String? title,
    String? notes,
    DateTime? sortDate,
    DateTime? createdAt,
    bool? isFavorite,
    Value<String?> locationName = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
  }) => Experience(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    personId: personId ?? this.personId,
    title: title ?? this.title,
    notes: notes ?? this.notes,
    sortDate: sortDate ?? this.sortDate,
    createdAt: createdAt ?? this.createdAt,
    isFavorite: isFavorite ?? this.isFavorite,
    locationName: locationName.present ? locationName.value : this.locationName,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
  );
  Experience copyWithCompanion(ExperiencesCompanion data) {
    return Experience(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      personId: data.personId.present ? data.personId.value : this.personId,
      title: data.title.present ? data.title.value : this.title,
      notes: data.notes.present ? data.notes.value : this.notes,
      sortDate: data.sortDate.present ? data.sortDate.value : this.sortDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      locationName: data.locationName.present
          ? data.locationName.value
          : this.locationName,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Experience(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('personId: $personId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('sortDate: $sortDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('locationName: $locationName, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hlc,
    deleted,
    personId,
    title,
    notes,
    sortDate,
    createdAt,
    isFavorite,
    locationName,
    latitude,
    longitude,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Experience &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.personId == this.personId &&
          other.title == this.title &&
          other.notes == this.notes &&
          other.sortDate == this.sortDate &&
          other.createdAt == this.createdAt &&
          other.isFavorite == this.isFavorite &&
          other.locationName == this.locationName &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude);
}

class ExperiencesCompanion extends UpdateCompanion<Experience> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> personId;
  final Value<String> title;
  final Value<String> notes;
  final Value<DateTime> sortDate;
  final Value<DateTime> createdAt;
  final Value<bool> isFavorite;
  final Value<String?> locationName;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<int> rowid;
  const ExperiencesCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.personId = const Value.absent(),
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    this.sortDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.locationName = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExperiencesCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String personId,
    this.title = const Value.absent(),
    this.notes = const Value.absent(),
    required DateTime sortDate,
    required DateTime createdAt,
    this.isFavorite = const Value.absent(),
    this.locationName = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       personId = Value(personId),
       sortDate = Value(sortDate),
       createdAt = Value(createdAt);
  static Insertable<Experience> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? personId,
    Expression<String>? title,
    Expression<String>? notes,
    Expression<DateTime>? sortDate,
    Expression<DateTime>? createdAt,
    Expression<bool>? isFavorite,
    Expression<String>? locationName,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (personId != null) 'person_id': personId,
      if (title != null) 'title': title,
      if (notes != null) 'notes': notes,
      if (sortDate != null) 'sort_date': sortDate,
      if (createdAt != null) 'created_at': createdAt,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (locationName != null) 'location_name': locationName,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExperiencesCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? personId,
    Value<String>? title,
    Value<String>? notes,
    Value<DateTime>? sortDate,
    Value<DateTime>? createdAt,
    Value<bool>? isFavorite,
    Value<String?>? locationName,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<int>? rowid,
  }) {
    return ExperiencesCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      personId: personId ?? this.personId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      sortDate: sortDate ?? this.sortDate,
      createdAt: createdAt ?? this.createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
      locationName: locationName ?? this.locationName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<String>(personId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (sortDate.present) {
      map['sort_date'] = Variable<DateTime>(sortDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (locationName.present) {
      map['location_name'] = Variable<String>(locationName.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExperiencesCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('personId: $personId, ')
          ..write('title: $title, ')
          ..write('notes: $notes, ')
          ..write('sortDate: $sortDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('locationName: $locationName, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IngestionsTable extends Ingestions
    with TableInfo<$IngestionsTable, Ingestion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IngestionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _experienceIdMeta = const VerificationMeta(
    'experienceId',
  );
  @override
  late final GeneratedColumn<String> experienceId = GeneratedColumn<String>(
    'experience_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES experiences (id)',
    ),
  );
  static const VerificationMeta _personIdMeta = const VerificationMeta(
    'personId',
  );
  @override
  late final GeneratedColumn<String> personId = GeneratedColumn<String>(
    'person_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES people (id)',
    ),
  );
  static const VerificationMeta _substanceKeyMeta = const VerificationMeta(
    'substanceKey',
  );
  @override
  late final GeneratedColumn<String> substanceKey = GeneratedColumn<String>(
    'substance_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routeMeta = const VerificationMeta('route');
  @override
  late final GeneratedColumn<String> route = GeneratedColumn<String>(
    'route',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<DateTime> time = GeneratedColumn<DateTime>(
    'time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endTimeMeta = const VerificationMeta(
    'endTime',
  );
  @override
  late final GeneratedColumn<DateTime> endTime = GeneratedColumn<DateTime>(
    'end_time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doseMeta = const VerificationMeta('dose');
  @override
  late final GeneratedColumn<double> dose = GeneratedColumn<double>(
    'dose',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doseIsEstimateMeta = const VerificationMeta(
    'doseIsEstimate',
  );
  @override
  late final GeneratedColumn<bool> doseIsEstimate = GeneratedColumn<bool>(
    'dose_is_estimate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("dose_is_estimate" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _doseStdDevMeta = const VerificationMeta(
    'doseStdDev',
  );
  @override
  late final GeneratedColumn<double> doseStdDev = GeneratedColumn<double>(
    'dose_std_dev',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stomachFullnessMeta = const VerificationMeta(
    'stomachFullness',
  );
  @override
  late final GeneratedColumn<String> stomachFullness = GeneratedColumn<String>(
    'stomach_fullness',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customUnitIdMeta = const VerificationMeta(
    'customUnitId',
  );
  @override
  late final GeneratedColumn<String> customUnitId = GeneratedColumn<String>(
    'custom_unit_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _productIdMeta = const VerificationMeta(
    'productId',
  );
  @override
  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
    'product_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _absorbedMgMeta = const VerificationMeta(
    'absorbedMg',
  );
  @override
  late final GeneratedColumn<double> absorbedMg = GeneratedColumn<double>(
    'absorbed_mg',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _methodMeta = const VerificationMeta('method');
  @override
  late final GeneratedColumn<String> method = GeneratedColumn<String>(
    'method',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _detailsJsonMeta = const VerificationMeta(
    'detailsJson',
  );
  @override
  late final GeneratedColumn<String> detailsJson = GeneratedColumn<String>(
    'details_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    experienceId,
    personId,
    substanceKey,
    route,
    time,
    endTime,
    dose,
    unit,
    doseIsEstimate,
    doseStdDev,
    stomachFullness,
    customUnitId,
    productId,
    absorbedMg,
    method,
    notes,
    detailsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ingestions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Ingestion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('experience_id')) {
      context.handle(
        _experienceIdMeta,
        experienceId.isAcceptableOrUnknown(
          data['experience_id']!,
          _experienceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_experienceIdMeta);
    }
    if (data.containsKey('person_id')) {
      context.handle(
        _personIdMeta,
        personId.isAcceptableOrUnknown(data['person_id']!, _personIdMeta),
      );
    } else if (isInserting) {
      context.missing(_personIdMeta);
    }
    if (data.containsKey('substance_key')) {
      context.handle(
        _substanceKeyMeta,
        substanceKey.isAcceptableOrUnknown(
          data['substance_key']!,
          _substanceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_substanceKeyMeta);
    }
    if (data.containsKey('route')) {
      context.handle(
        _routeMeta,
        route.isAcceptableOrUnknown(data['route']!, _routeMeta),
      );
    } else if (isInserting) {
      context.missing(_routeMeta);
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('end_time')) {
      context.handle(
        _endTimeMeta,
        endTime.isAcceptableOrUnknown(data['end_time']!, _endTimeMeta),
      );
    }
    if (data.containsKey('dose')) {
      context.handle(
        _doseMeta,
        dose.isAcceptableOrUnknown(data['dose']!, _doseMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('dose_is_estimate')) {
      context.handle(
        _doseIsEstimateMeta,
        doseIsEstimate.isAcceptableOrUnknown(
          data['dose_is_estimate']!,
          _doseIsEstimateMeta,
        ),
      );
    }
    if (data.containsKey('dose_std_dev')) {
      context.handle(
        _doseStdDevMeta,
        doseStdDev.isAcceptableOrUnknown(
          data['dose_std_dev']!,
          _doseStdDevMeta,
        ),
      );
    }
    if (data.containsKey('stomach_fullness')) {
      context.handle(
        _stomachFullnessMeta,
        stomachFullness.isAcceptableOrUnknown(
          data['stomach_fullness']!,
          _stomachFullnessMeta,
        ),
      );
    }
    if (data.containsKey('custom_unit_id')) {
      context.handle(
        _customUnitIdMeta,
        customUnitId.isAcceptableOrUnknown(
          data['custom_unit_id']!,
          _customUnitIdMeta,
        ),
      );
    }
    if (data.containsKey('product_id')) {
      context.handle(
        _productIdMeta,
        productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta),
      );
    }
    if (data.containsKey('absorbed_mg')) {
      context.handle(
        _absorbedMgMeta,
        absorbedMg.isAcceptableOrUnknown(data['absorbed_mg']!, _absorbedMgMeta),
      );
    }
    if (data.containsKey('method')) {
      context.handle(
        _methodMeta,
        method.isAcceptableOrUnknown(data['method']!, _methodMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('details_json')) {
      context.handle(
        _detailsJsonMeta,
        detailsJson.isAcceptableOrUnknown(
          data['details_json']!,
          _detailsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Ingestion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Ingestion(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      experienceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}experience_id'],
      )!,
      personId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_id'],
      )!,
      substanceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}substance_key'],
      )!,
      route: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route'],
      )!,
      time: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}time'],
      )!,
      endTime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_time'],
      ),
      dose: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dose'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      doseIsEstimate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}dose_is_estimate'],
      )!,
      doseStdDev: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dose_std_dev'],
      ),
      stomachFullness: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}stomach_fullness'],
      ),
      customUnitId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_unit_id'],
      ),
      productId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}product_id'],
      ),
      absorbedMg: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}absorbed_mg'],
      ),
      method: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}method'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      detailsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details_json'],
      )!,
    );
  }

  @override
  $IngestionsTable createAlias(String alias) {
    return $IngestionsTable(attachedDatabase, alias);
  }
}

class Ingestion extends DataClass implements Insertable<Ingestion> {
  final String id;
  final String hlc;
  final bool deleted;
  final String experienceId;
  final String personId;
  final String substanceKey;
  final String route;
  final DateTime time;
  final DateTime? endTime;
  final double? dose;
  final String? unit;
  final bool doseIsEstimate;
  final double? doseStdDev;
  final String? stomachFullness;
  final String? customUnitId;
  final String? productId;
  final double? absorbedMg;
  final String? method;
  final String notes;
  final String detailsJson;
  const Ingestion({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.experienceId,
    required this.personId,
    required this.substanceKey,
    required this.route,
    required this.time,
    this.endTime,
    this.dose,
    this.unit,
    required this.doseIsEstimate,
    this.doseStdDev,
    this.stomachFullness,
    this.customUnitId,
    this.productId,
    this.absorbedMg,
    this.method,
    required this.notes,
    required this.detailsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['experience_id'] = Variable<String>(experienceId);
    map['person_id'] = Variable<String>(personId);
    map['substance_key'] = Variable<String>(substanceKey);
    map['route'] = Variable<String>(route);
    map['time'] = Variable<DateTime>(time);
    if (!nullToAbsent || endTime != null) {
      map['end_time'] = Variable<DateTime>(endTime);
    }
    if (!nullToAbsent || dose != null) {
      map['dose'] = Variable<double>(dose);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    map['dose_is_estimate'] = Variable<bool>(doseIsEstimate);
    if (!nullToAbsent || doseStdDev != null) {
      map['dose_std_dev'] = Variable<double>(doseStdDev);
    }
    if (!nullToAbsent || stomachFullness != null) {
      map['stomach_fullness'] = Variable<String>(stomachFullness);
    }
    if (!nullToAbsent || customUnitId != null) {
      map['custom_unit_id'] = Variable<String>(customUnitId);
    }
    if (!nullToAbsent || productId != null) {
      map['product_id'] = Variable<String>(productId);
    }
    if (!nullToAbsent || absorbedMg != null) {
      map['absorbed_mg'] = Variable<double>(absorbedMg);
    }
    if (!nullToAbsent || method != null) {
      map['method'] = Variable<String>(method);
    }
    map['notes'] = Variable<String>(notes);
    map['details_json'] = Variable<String>(detailsJson);
    return map;
  }

  IngestionsCompanion toCompanion(bool nullToAbsent) {
    return IngestionsCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      experienceId: Value(experienceId),
      personId: Value(personId),
      substanceKey: Value(substanceKey),
      route: Value(route),
      time: Value(time),
      endTime: endTime == null && nullToAbsent
          ? const Value.absent()
          : Value(endTime),
      dose: dose == null && nullToAbsent ? const Value.absent() : Value(dose),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      doseIsEstimate: Value(doseIsEstimate),
      doseStdDev: doseStdDev == null && nullToAbsent
          ? const Value.absent()
          : Value(doseStdDev),
      stomachFullness: stomachFullness == null && nullToAbsent
          ? const Value.absent()
          : Value(stomachFullness),
      customUnitId: customUnitId == null && nullToAbsent
          ? const Value.absent()
          : Value(customUnitId),
      productId: productId == null && nullToAbsent
          ? const Value.absent()
          : Value(productId),
      absorbedMg: absorbedMg == null && nullToAbsent
          ? const Value.absent()
          : Value(absorbedMg),
      method: method == null && nullToAbsent
          ? const Value.absent()
          : Value(method),
      notes: Value(notes),
      detailsJson: Value(detailsJson),
    );
  }

  factory Ingestion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Ingestion(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      experienceId: serializer.fromJson<String>(json['experienceId']),
      personId: serializer.fromJson<String>(json['personId']),
      substanceKey: serializer.fromJson<String>(json['substanceKey']),
      route: serializer.fromJson<String>(json['route']),
      time: serializer.fromJson<DateTime>(json['time']),
      endTime: serializer.fromJson<DateTime?>(json['endTime']),
      dose: serializer.fromJson<double?>(json['dose']),
      unit: serializer.fromJson<String?>(json['unit']),
      doseIsEstimate: serializer.fromJson<bool>(json['doseIsEstimate']),
      doseStdDev: serializer.fromJson<double?>(json['doseStdDev']),
      stomachFullness: serializer.fromJson<String?>(json['stomachFullness']),
      customUnitId: serializer.fromJson<String?>(json['customUnitId']),
      productId: serializer.fromJson<String?>(json['productId']),
      absorbedMg: serializer.fromJson<double?>(json['absorbedMg']),
      method: serializer.fromJson<String?>(json['method']),
      notes: serializer.fromJson<String>(json['notes']),
      detailsJson: serializer.fromJson<String>(json['detailsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'experienceId': serializer.toJson<String>(experienceId),
      'personId': serializer.toJson<String>(personId),
      'substanceKey': serializer.toJson<String>(substanceKey),
      'route': serializer.toJson<String>(route),
      'time': serializer.toJson<DateTime>(time),
      'endTime': serializer.toJson<DateTime?>(endTime),
      'dose': serializer.toJson<double?>(dose),
      'unit': serializer.toJson<String?>(unit),
      'doseIsEstimate': serializer.toJson<bool>(doseIsEstimate),
      'doseStdDev': serializer.toJson<double?>(doseStdDev),
      'stomachFullness': serializer.toJson<String?>(stomachFullness),
      'customUnitId': serializer.toJson<String?>(customUnitId),
      'productId': serializer.toJson<String?>(productId),
      'absorbedMg': serializer.toJson<double?>(absorbedMg),
      'method': serializer.toJson<String?>(method),
      'notes': serializer.toJson<String>(notes),
      'detailsJson': serializer.toJson<String>(detailsJson),
    };
  }

  Ingestion copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? experienceId,
    String? personId,
    String? substanceKey,
    String? route,
    DateTime? time,
    Value<DateTime?> endTime = const Value.absent(),
    Value<double?> dose = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    bool? doseIsEstimate,
    Value<double?> doseStdDev = const Value.absent(),
    Value<String?> stomachFullness = const Value.absent(),
    Value<String?> customUnitId = const Value.absent(),
    Value<String?> productId = const Value.absent(),
    Value<double?> absorbedMg = const Value.absent(),
    Value<String?> method = const Value.absent(),
    String? notes,
    String? detailsJson,
  }) => Ingestion(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    experienceId: experienceId ?? this.experienceId,
    personId: personId ?? this.personId,
    substanceKey: substanceKey ?? this.substanceKey,
    route: route ?? this.route,
    time: time ?? this.time,
    endTime: endTime.present ? endTime.value : this.endTime,
    dose: dose.present ? dose.value : this.dose,
    unit: unit.present ? unit.value : this.unit,
    doseIsEstimate: doseIsEstimate ?? this.doseIsEstimate,
    doseStdDev: doseStdDev.present ? doseStdDev.value : this.doseStdDev,
    stomachFullness: stomachFullness.present
        ? stomachFullness.value
        : this.stomachFullness,
    customUnitId: customUnitId.present ? customUnitId.value : this.customUnitId,
    productId: productId.present ? productId.value : this.productId,
    absorbedMg: absorbedMg.present ? absorbedMg.value : this.absorbedMg,
    method: method.present ? method.value : this.method,
    notes: notes ?? this.notes,
    detailsJson: detailsJson ?? this.detailsJson,
  );
  Ingestion copyWithCompanion(IngestionsCompanion data) {
    return Ingestion(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      experienceId: data.experienceId.present
          ? data.experienceId.value
          : this.experienceId,
      personId: data.personId.present ? data.personId.value : this.personId,
      substanceKey: data.substanceKey.present
          ? data.substanceKey.value
          : this.substanceKey,
      route: data.route.present ? data.route.value : this.route,
      time: data.time.present ? data.time.value : this.time,
      endTime: data.endTime.present ? data.endTime.value : this.endTime,
      dose: data.dose.present ? data.dose.value : this.dose,
      unit: data.unit.present ? data.unit.value : this.unit,
      doseIsEstimate: data.doseIsEstimate.present
          ? data.doseIsEstimate.value
          : this.doseIsEstimate,
      doseStdDev: data.doseStdDev.present
          ? data.doseStdDev.value
          : this.doseStdDev,
      stomachFullness: data.stomachFullness.present
          ? data.stomachFullness.value
          : this.stomachFullness,
      customUnitId: data.customUnitId.present
          ? data.customUnitId.value
          : this.customUnitId,
      productId: data.productId.present ? data.productId.value : this.productId,
      absorbedMg: data.absorbedMg.present
          ? data.absorbedMg.value
          : this.absorbedMg,
      method: data.method.present ? data.method.value : this.method,
      notes: data.notes.present ? data.notes.value : this.notes,
      detailsJson: data.detailsJson.present
          ? data.detailsJson.value
          : this.detailsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Ingestion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('experienceId: $experienceId, ')
          ..write('personId: $personId, ')
          ..write('substanceKey: $substanceKey, ')
          ..write('route: $route, ')
          ..write('time: $time, ')
          ..write('endTime: $endTime, ')
          ..write('dose: $dose, ')
          ..write('unit: $unit, ')
          ..write('doseIsEstimate: $doseIsEstimate, ')
          ..write('doseStdDev: $doseStdDev, ')
          ..write('stomachFullness: $stomachFullness, ')
          ..write('customUnitId: $customUnitId, ')
          ..write('productId: $productId, ')
          ..write('absorbedMg: $absorbedMg, ')
          ..write('method: $method, ')
          ..write('notes: $notes, ')
          ..write('detailsJson: $detailsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hlc,
    deleted,
    experienceId,
    personId,
    substanceKey,
    route,
    time,
    endTime,
    dose,
    unit,
    doseIsEstimate,
    doseStdDev,
    stomachFullness,
    customUnitId,
    productId,
    absorbedMg,
    method,
    notes,
    detailsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Ingestion &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.experienceId == this.experienceId &&
          other.personId == this.personId &&
          other.substanceKey == this.substanceKey &&
          other.route == this.route &&
          other.time == this.time &&
          other.endTime == this.endTime &&
          other.dose == this.dose &&
          other.unit == this.unit &&
          other.doseIsEstimate == this.doseIsEstimate &&
          other.doseStdDev == this.doseStdDev &&
          other.stomachFullness == this.stomachFullness &&
          other.customUnitId == this.customUnitId &&
          other.productId == this.productId &&
          other.absorbedMg == this.absorbedMg &&
          other.method == this.method &&
          other.notes == this.notes &&
          other.detailsJson == this.detailsJson);
}

class IngestionsCompanion extends UpdateCompanion<Ingestion> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> experienceId;
  final Value<String> personId;
  final Value<String> substanceKey;
  final Value<String> route;
  final Value<DateTime> time;
  final Value<DateTime?> endTime;
  final Value<double?> dose;
  final Value<String?> unit;
  final Value<bool> doseIsEstimate;
  final Value<double?> doseStdDev;
  final Value<String?> stomachFullness;
  final Value<String?> customUnitId;
  final Value<String?> productId;
  final Value<double?> absorbedMg;
  final Value<String?> method;
  final Value<String> notes;
  final Value<String> detailsJson;
  final Value<int> rowid;
  const IngestionsCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.experienceId = const Value.absent(),
    this.personId = const Value.absent(),
    this.substanceKey = const Value.absent(),
    this.route = const Value.absent(),
    this.time = const Value.absent(),
    this.endTime = const Value.absent(),
    this.dose = const Value.absent(),
    this.unit = const Value.absent(),
    this.doseIsEstimate = const Value.absent(),
    this.doseStdDev = const Value.absent(),
    this.stomachFullness = const Value.absent(),
    this.customUnitId = const Value.absent(),
    this.productId = const Value.absent(),
    this.absorbedMg = const Value.absent(),
    this.method = const Value.absent(),
    this.notes = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IngestionsCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String experienceId,
    required String personId,
    required String substanceKey,
    required String route,
    required DateTime time,
    this.endTime = const Value.absent(),
    this.dose = const Value.absent(),
    this.unit = const Value.absent(),
    this.doseIsEstimate = const Value.absent(),
    this.doseStdDev = const Value.absent(),
    this.stomachFullness = const Value.absent(),
    this.customUnitId = const Value.absent(),
    this.productId = const Value.absent(),
    this.absorbedMg = const Value.absent(),
    this.method = const Value.absent(),
    this.notes = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       experienceId = Value(experienceId),
       personId = Value(personId),
       substanceKey = Value(substanceKey),
       route = Value(route),
       time = Value(time);
  static Insertable<Ingestion> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? experienceId,
    Expression<String>? personId,
    Expression<String>? substanceKey,
    Expression<String>? route,
    Expression<DateTime>? time,
    Expression<DateTime>? endTime,
    Expression<double>? dose,
    Expression<String>? unit,
    Expression<bool>? doseIsEstimate,
    Expression<double>? doseStdDev,
    Expression<String>? stomachFullness,
    Expression<String>? customUnitId,
    Expression<String>? productId,
    Expression<double>? absorbedMg,
    Expression<String>? method,
    Expression<String>? notes,
    Expression<String>? detailsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (experienceId != null) 'experience_id': experienceId,
      if (personId != null) 'person_id': personId,
      if (substanceKey != null) 'substance_key': substanceKey,
      if (route != null) 'route': route,
      if (time != null) 'time': time,
      if (endTime != null) 'end_time': endTime,
      if (dose != null) 'dose': dose,
      if (unit != null) 'unit': unit,
      if (doseIsEstimate != null) 'dose_is_estimate': doseIsEstimate,
      if (doseStdDev != null) 'dose_std_dev': doseStdDev,
      if (stomachFullness != null) 'stomach_fullness': stomachFullness,
      if (customUnitId != null) 'custom_unit_id': customUnitId,
      if (productId != null) 'product_id': productId,
      if (absorbedMg != null) 'absorbed_mg': absorbedMg,
      if (method != null) 'method': method,
      if (notes != null) 'notes': notes,
      if (detailsJson != null) 'details_json': detailsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IngestionsCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? experienceId,
    Value<String>? personId,
    Value<String>? substanceKey,
    Value<String>? route,
    Value<DateTime>? time,
    Value<DateTime?>? endTime,
    Value<double?>? dose,
    Value<String?>? unit,
    Value<bool>? doseIsEstimate,
    Value<double?>? doseStdDev,
    Value<String?>? stomachFullness,
    Value<String?>? customUnitId,
    Value<String?>? productId,
    Value<double?>? absorbedMg,
    Value<String?>? method,
    Value<String>? notes,
    Value<String>? detailsJson,
    Value<int>? rowid,
  }) {
    return IngestionsCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      experienceId: experienceId ?? this.experienceId,
      personId: personId ?? this.personId,
      substanceKey: substanceKey ?? this.substanceKey,
      route: route ?? this.route,
      time: time ?? this.time,
      endTime: endTime ?? this.endTime,
      dose: dose ?? this.dose,
      unit: unit ?? this.unit,
      doseIsEstimate: doseIsEstimate ?? this.doseIsEstimate,
      doseStdDev: doseStdDev ?? this.doseStdDev,
      stomachFullness: stomachFullness ?? this.stomachFullness,
      customUnitId: customUnitId ?? this.customUnitId,
      productId: productId ?? this.productId,
      absorbedMg: absorbedMg ?? this.absorbedMg,
      method: method ?? this.method,
      notes: notes ?? this.notes,
      detailsJson: detailsJson ?? this.detailsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (experienceId.present) {
      map['experience_id'] = Variable<String>(experienceId.value);
    }
    if (personId.present) {
      map['person_id'] = Variable<String>(personId.value);
    }
    if (substanceKey.present) {
      map['substance_key'] = Variable<String>(substanceKey.value);
    }
    if (route.present) {
      map['route'] = Variable<String>(route.value);
    }
    if (time.present) {
      map['time'] = Variable<DateTime>(time.value);
    }
    if (endTime.present) {
      map['end_time'] = Variable<DateTime>(endTime.value);
    }
    if (dose.present) {
      map['dose'] = Variable<double>(dose.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (doseIsEstimate.present) {
      map['dose_is_estimate'] = Variable<bool>(doseIsEstimate.value);
    }
    if (doseStdDev.present) {
      map['dose_std_dev'] = Variable<double>(doseStdDev.value);
    }
    if (stomachFullness.present) {
      map['stomach_fullness'] = Variable<String>(stomachFullness.value);
    }
    if (customUnitId.present) {
      map['custom_unit_id'] = Variable<String>(customUnitId.value);
    }
    if (productId.present) {
      map['product_id'] = Variable<String>(productId.value);
    }
    if (absorbedMg.present) {
      map['absorbed_mg'] = Variable<double>(absorbedMg.value);
    }
    if (method.present) {
      map['method'] = Variable<String>(method.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (detailsJson.present) {
      map['details_json'] = Variable<String>(detailsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IngestionsCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('experienceId: $experienceId, ')
          ..write('personId: $personId, ')
          ..write('substanceKey: $substanceKey, ')
          ..write('route: $route, ')
          ..write('time: $time, ')
          ..write('endTime: $endTime, ')
          ..write('dose: $dose, ')
          ..write('unit: $unit, ')
          ..write('doseIsEstimate: $doseIsEstimate, ')
          ..write('doseStdDev: $doseStdDev, ')
          ..write('stomachFullness: $stomachFullness, ')
          ..write('customUnitId: $customUnitId, ')
          ..write('productId: $productId, ')
          ..write('absorbedMg: $absorbedMg, ')
          ..write('method: $method, ')
          ..write('notes: $notes, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimedNotesTable extends TimedNotes
    with TableInfo<$TimedNotesTable, TimedNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimedNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _experienceIdMeta = const VerificationMeta(
    'experienceId',
  );
  @override
  late final GeneratedColumn<String> experienceId = GeneratedColumn<String>(
    'experience_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES experiences (id)',
    ),
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<DateTime> time = GeneratedColumn<DateTime>(
    'time',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0xFF6750A4),
  );
  static const VerificationMeta _showOnTimelineMeta = const VerificationMeta(
    'showOnTimeline',
  );
  @override
  late final GeneratedColumn<bool> showOnTimeline = GeneratedColumn<bool>(
    'show_on_timeline',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("show_on_timeline" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    experienceId,
    time,
    note,
    colorValue,
    showOnTimeline,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'timed_notes';
  @override
  VerificationContext validateIntegrity(
    Insertable<TimedNote> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('experience_id')) {
      context.handle(
        _experienceIdMeta,
        experienceId.isAcceptableOrUnknown(
          data['experience_id']!,
          _experienceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_experienceIdMeta);
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    } else if (isInserting) {
      context.missing(_noteMeta);
    }
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    }
    if (data.containsKey('show_on_timeline')) {
      context.handle(
        _showOnTimelineMeta,
        showOnTimeline.isAcceptableOrUnknown(
          data['show_on_timeline']!,
          _showOnTimelineMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimedNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimedNote(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      experienceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}experience_id'],
      )!,
      time: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}time'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      showOnTimeline: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}show_on_timeline'],
      )!,
    );
  }

  @override
  $TimedNotesTable createAlias(String alias) {
    return $TimedNotesTable(attachedDatabase, alias);
  }
}

class TimedNote extends DataClass implements Insertable<TimedNote> {
  final String id;
  final String hlc;
  final bool deleted;
  final String experienceId;
  final DateTime time;
  final String note;
  final int colorValue;
  final bool showOnTimeline;
  const TimedNote({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.experienceId,
    required this.time,
    required this.note,
    required this.colorValue,
    required this.showOnTimeline,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['experience_id'] = Variable<String>(experienceId);
    map['time'] = Variable<DateTime>(time);
    map['note'] = Variable<String>(note);
    map['color_value'] = Variable<int>(colorValue);
    map['show_on_timeline'] = Variable<bool>(showOnTimeline);
    return map;
  }

  TimedNotesCompanion toCompanion(bool nullToAbsent) {
    return TimedNotesCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      experienceId: Value(experienceId),
      time: Value(time),
      note: Value(note),
      colorValue: Value(colorValue),
      showOnTimeline: Value(showOnTimeline),
    );
  }

  factory TimedNote.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimedNote(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      experienceId: serializer.fromJson<String>(json['experienceId']),
      time: serializer.fromJson<DateTime>(json['time']),
      note: serializer.fromJson<String>(json['note']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      showOnTimeline: serializer.fromJson<bool>(json['showOnTimeline']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'experienceId': serializer.toJson<String>(experienceId),
      'time': serializer.toJson<DateTime>(time),
      'note': serializer.toJson<String>(note),
      'colorValue': serializer.toJson<int>(colorValue),
      'showOnTimeline': serializer.toJson<bool>(showOnTimeline),
    };
  }

  TimedNote copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? experienceId,
    DateTime? time,
    String? note,
    int? colorValue,
    bool? showOnTimeline,
  }) => TimedNote(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    experienceId: experienceId ?? this.experienceId,
    time: time ?? this.time,
    note: note ?? this.note,
    colorValue: colorValue ?? this.colorValue,
    showOnTimeline: showOnTimeline ?? this.showOnTimeline,
  );
  TimedNote copyWithCompanion(TimedNotesCompanion data) {
    return TimedNote(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      experienceId: data.experienceId.present
          ? data.experienceId.value
          : this.experienceId,
      time: data.time.present ? data.time.value : this.time,
      note: data.note.present ? data.note.value : this.note,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      showOnTimeline: data.showOnTimeline.present
          ? data.showOnTimeline.value
          : this.showOnTimeline,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimedNote(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('experienceId: $experienceId, ')
          ..write('time: $time, ')
          ..write('note: $note, ')
          ..write('colorValue: $colorValue, ')
          ..write('showOnTimeline: $showOnTimeline')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hlc,
    deleted,
    experienceId,
    time,
    note,
    colorValue,
    showOnTimeline,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimedNote &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.experienceId == this.experienceId &&
          other.time == this.time &&
          other.note == this.note &&
          other.colorValue == this.colorValue &&
          other.showOnTimeline == this.showOnTimeline);
}

class TimedNotesCompanion extends UpdateCompanion<TimedNote> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> experienceId;
  final Value<DateTime> time;
  final Value<String> note;
  final Value<int> colorValue;
  final Value<bool> showOnTimeline;
  final Value<int> rowid;
  const TimedNotesCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.experienceId = const Value.absent(),
    this.time = const Value.absent(),
    this.note = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.showOnTimeline = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimedNotesCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String experienceId,
    required DateTime time,
    required String note,
    this.colorValue = const Value.absent(),
    this.showOnTimeline = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       experienceId = Value(experienceId),
       time = Value(time),
       note = Value(note);
  static Insertable<TimedNote> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? experienceId,
    Expression<DateTime>? time,
    Expression<String>? note,
    Expression<int>? colorValue,
    Expression<bool>? showOnTimeline,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (experienceId != null) 'experience_id': experienceId,
      if (time != null) 'time': time,
      if (note != null) 'note': note,
      if (colorValue != null) 'color_value': colorValue,
      if (showOnTimeline != null) 'show_on_timeline': showOnTimeline,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TimedNotesCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? experienceId,
    Value<DateTime>? time,
    Value<String>? note,
    Value<int>? colorValue,
    Value<bool>? showOnTimeline,
    Value<int>? rowid,
  }) {
    return TimedNotesCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      experienceId: experienceId ?? this.experienceId,
      time: time ?? this.time,
      note: note ?? this.note,
      colorValue: colorValue ?? this.colorValue,
      showOnTimeline: showOnTimeline ?? this.showOnTimeline,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (experienceId.present) {
      map['experience_id'] = Variable<String>(experienceId.value);
    }
    if (time.present) {
      map['time'] = Variable<DateTime>(time.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (showOnTimeline.present) {
      map['show_on_timeline'] = Variable<bool>(showOnTimeline.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimedNotesCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('experienceId: $experienceId, ')
          ..write('time: $time, ')
          ..write('note: $note, ')
          ..write('colorValue: $colorValue, ')
          ..write('showOnTimeline: $showOnTimeline, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RatingsTable extends Ratings with TableInfo<$RatingsTable, Rating> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RatingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _experienceIdMeta = const VerificationMeta(
    'experienceId',
  );
  @override
  late final GeneratedColumn<String> experienceId = GeneratedColumn<String>(
    'experience_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES experiences (id)',
    ),
  );
  static const VerificationMeta _timeMeta = const VerificationMeta('time');
  @override
  late final GeneratedColumn<DateTime> time = GeneratedColumn<DateTime>(
    'time',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _shulginMeta = const VerificationMeta(
    'shulgin',
  );
  @override
  late final GeneratedColumn<String> shulgin = GeneratedColumn<String>(
    'shulgin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scoresJsonMeta = const VerificationMeta(
    'scoresJson',
  );
  @override
  late final GeneratedColumn<String> scoresJson = GeneratedColumn<String>(
    'scores_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    experienceId,
    time,
    shulgin,
    scoresJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ratings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Rating> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('experience_id')) {
      context.handle(
        _experienceIdMeta,
        experienceId.isAcceptableOrUnknown(
          data['experience_id']!,
          _experienceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_experienceIdMeta);
    }
    if (data.containsKey('time')) {
      context.handle(
        _timeMeta,
        time.isAcceptableOrUnknown(data['time']!, _timeMeta),
      );
    }
    if (data.containsKey('shulgin')) {
      context.handle(
        _shulginMeta,
        shulgin.isAcceptableOrUnknown(data['shulgin']!, _shulginMeta),
      );
    }
    if (data.containsKey('scores_json')) {
      context.handle(
        _scoresJsonMeta,
        scoresJson.isAcceptableOrUnknown(data['scores_json']!, _scoresJsonMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Rating map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Rating(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      experienceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}experience_id'],
      )!,
      time: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}time'],
      ),
      shulgin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shulgin'],
      ),
      scoresJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scores_json'],
      )!,
    );
  }

  @override
  $RatingsTable createAlias(String alias) {
    return $RatingsTable(attachedDatabase, alias);
  }
}

class Rating extends DataClass implements Insertable<Rating> {
  final String id;
  final String hlc;
  final bool deleted;
  final String experienceId;
  final DateTime? time;
  final String? shulgin;
  final String scoresJson;
  const Rating({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.experienceId,
    this.time,
    this.shulgin,
    required this.scoresJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['experience_id'] = Variable<String>(experienceId);
    if (!nullToAbsent || time != null) {
      map['time'] = Variable<DateTime>(time);
    }
    if (!nullToAbsent || shulgin != null) {
      map['shulgin'] = Variable<String>(shulgin);
    }
    map['scores_json'] = Variable<String>(scoresJson);
    return map;
  }

  RatingsCompanion toCompanion(bool nullToAbsent) {
    return RatingsCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      experienceId: Value(experienceId),
      time: time == null && nullToAbsent ? const Value.absent() : Value(time),
      shulgin: shulgin == null && nullToAbsent
          ? const Value.absent()
          : Value(shulgin),
      scoresJson: Value(scoresJson),
    );
  }

  factory Rating.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Rating(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      experienceId: serializer.fromJson<String>(json['experienceId']),
      time: serializer.fromJson<DateTime?>(json['time']),
      shulgin: serializer.fromJson<String?>(json['shulgin']),
      scoresJson: serializer.fromJson<String>(json['scoresJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'experienceId': serializer.toJson<String>(experienceId),
      'time': serializer.toJson<DateTime?>(time),
      'shulgin': serializer.toJson<String?>(shulgin),
      'scoresJson': serializer.toJson<String>(scoresJson),
    };
  }

  Rating copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? experienceId,
    Value<DateTime?> time = const Value.absent(),
    Value<String?> shulgin = const Value.absent(),
    String? scoresJson,
  }) => Rating(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    experienceId: experienceId ?? this.experienceId,
    time: time.present ? time.value : this.time,
    shulgin: shulgin.present ? shulgin.value : this.shulgin,
    scoresJson: scoresJson ?? this.scoresJson,
  );
  Rating copyWithCompanion(RatingsCompanion data) {
    return Rating(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      experienceId: data.experienceId.present
          ? data.experienceId.value
          : this.experienceId,
      time: data.time.present ? data.time.value : this.time,
      shulgin: data.shulgin.present ? data.shulgin.value : this.shulgin,
      scoresJson: data.scoresJson.present
          ? data.scoresJson.value
          : this.scoresJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Rating(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('experienceId: $experienceId, ')
          ..write('time: $time, ')
          ..write('shulgin: $shulgin, ')
          ..write('scoresJson: $scoresJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, hlc, deleted, experienceId, time, shulgin, scoresJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Rating &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.experienceId == this.experienceId &&
          other.time == this.time &&
          other.shulgin == this.shulgin &&
          other.scoresJson == this.scoresJson);
}

class RatingsCompanion extends UpdateCompanion<Rating> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> experienceId;
  final Value<DateTime?> time;
  final Value<String?> shulgin;
  final Value<String> scoresJson;
  final Value<int> rowid;
  const RatingsCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.experienceId = const Value.absent(),
    this.time = const Value.absent(),
    this.shulgin = const Value.absent(),
    this.scoresJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RatingsCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String experienceId,
    this.time = const Value.absent(),
    this.shulgin = const Value.absent(),
    this.scoresJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       experienceId = Value(experienceId);
  static Insertable<Rating> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? experienceId,
    Expression<DateTime>? time,
    Expression<String>? shulgin,
    Expression<String>? scoresJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (experienceId != null) 'experience_id': experienceId,
      if (time != null) 'time': time,
      if (shulgin != null) 'shulgin': shulgin,
      if (scoresJson != null) 'scores_json': scoresJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RatingsCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? experienceId,
    Value<DateTime?>? time,
    Value<String?>? shulgin,
    Value<String>? scoresJson,
    Value<int>? rowid,
  }) {
    return RatingsCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      experienceId: experienceId ?? this.experienceId,
      time: time ?? this.time,
      shulgin: shulgin ?? this.shulgin,
      scoresJson: scoresJson ?? this.scoresJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (experienceId.present) {
      map['experience_id'] = Variable<String>(experienceId.value);
    }
    if (time.present) {
      map['time'] = Variable<DateTime>(time.value);
    }
    if (shulgin.present) {
      map['shulgin'] = Variable<String>(shulgin.value);
    }
    if (scoresJson.present) {
      map['scores_json'] = Variable<String>(scoresJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RatingsCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('experienceId: $experienceId, ')
          ..write('time: $time, ')
          ..write('shulgin: $shulgin, ')
          ..write('scoresJson: $scoresJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomUnitsTable extends CustomUnits
    with TableInfo<$CustomUnitsTable, CustomUnit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomUnitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _substanceKeyMeta = const VerificationMeta(
    'substanceKey',
  );
  @override
  late final GeneratedColumn<String> substanceKey = GeneratedColumn<String>(
    'substance_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routeMeta = const VerificationMeta('route');
  @override
  late final GeneratedColumn<String> route = GeneratedColumn<String>(
    'route',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitSingularMeta = const VerificationMeta(
    'unitSingular',
  );
  @override
  late final GeneratedColumn<String> unitSingular = GeneratedColumn<String>(
    'unit_singular',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitPluralMeta = const VerificationMeta(
    'unitPlural',
  );
  @override
  late final GeneratedColumn<String> unitPlural = GeneratedColumn<String>(
    'unit_plural',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doseOfOneUnitMeta = const VerificationMeta(
    'doseOfOneUnit',
  );
  @override
  late final GeneratedColumn<double> doseOfOneUnit = GeneratedColumn<double>(
    'dose_of_one_unit',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _doseStdDevMeta = const VerificationMeta(
    'doseStdDev',
  );
  @override
  late final GeneratedColumn<double> doseStdDev = GeneratedColumn<double>(
    'dose_std_dev',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originalUnitMeta = const VerificationMeta(
    'originalUnit',
  );
  @override
  late final GeneratedColumn<String> originalUnit = GeneratedColumn<String>(
    'original_unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isEstimateMeta = const VerificationMeta(
    'isEstimate',
  );
  @override
  late final GeneratedColumn<bool> isEstimate = GeneratedColumn<bool>(
    'is_estimate',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_estimate" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isArchivedMeta = const VerificationMeta(
    'isArchived',
  );
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
    'is_archived',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_archived" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    substanceKey,
    route,
    name,
    unitSingular,
    unitPlural,
    doseOfOneUnit,
    doseStdDev,
    originalUnit,
    isEstimate,
    isArchived,
    note,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_units';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomUnit> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('substance_key')) {
      context.handle(
        _substanceKeyMeta,
        substanceKey.isAcceptableOrUnknown(
          data['substance_key']!,
          _substanceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_substanceKeyMeta);
    }
    if (data.containsKey('route')) {
      context.handle(
        _routeMeta,
        route.isAcceptableOrUnknown(data['route']!, _routeMeta),
      );
    } else if (isInserting) {
      context.missing(_routeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('unit_singular')) {
      context.handle(
        _unitSingularMeta,
        unitSingular.isAcceptableOrUnknown(
          data['unit_singular']!,
          _unitSingularMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_unitSingularMeta);
    }
    if (data.containsKey('unit_plural')) {
      context.handle(
        _unitPluralMeta,
        unitPlural.isAcceptableOrUnknown(data['unit_plural']!, _unitPluralMeta),
      );
    }
    if (data.containsKey('dose_of_one_unit')) {
      context.handle(
        _doseOfOneUnitMeta,
        doseOfOneUnit.isAcceptableOrUnknown(
          data['dose_of_one_unit']!,
          _doseOfOneUnitMeta,
        ),
      );
    }
    if (data.containsKey('dose_std_dev')) {
      context.handle(
        _doseStdDevMeta,
        doseStdDev.isAcceptableOrUnknown(
          data['dose_std_dev']!,
          _doseStdDevMeta,
        ),
      );
    }
    if (data.containsKey('original_unit')) {
      context.handle(
        _originalUnitMeta,
        originalUnit.isAcceptableOrUnknown(
          data['original_unit']!,
          _originalUnitMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_originalUnitMeta);
    }
    if (data.containsKey('is_estimate')) {
      context.handle(
        _isEstimateMeta,
        isEstimate.isAcceptableOrUnknown(data['is_estimate']!, _isEstimateMeta),
      );
    }
    if (data.containsKey('is_archived')) {
      context.handle(
        _isArchivedMeta,
        isArchived.isAcceptableOrUnknown(data['is_archived']!, _isArchivedMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomUnit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomUnit(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      substanceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}substance_key'],
      )!,
      route: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      unitSingular: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit_singular'],
      )!,
      unitPlural: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit_plural'],
      ),
      doseOfOneUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dose_of_one_unit'],
      ),
      doseStdDev: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}dose_std_dev'],
      ),
      originalUnit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}original_unit'],
      )!,
      isEstimate: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_estimate'],
      )!,
      isArchived: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_archived'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
    );
  }

  @override
  $CustomUnitsTable createAlias(String alias) {
    return $CustomUnitsTable(attachedDatabase, alias);
  }
}

class CustomUnit extends DataClass implements Insertable<CustomUnit> {
  final String id;
  final String hlc;
  final bool deleted;
  final String substanceKey;
  final String route;
  final String name;
  final String unitSingular;
  final String? unitPlural;
  final double? doseOfOneUnit;
  final double? doseStdDev;
  final String originalUnit;
  final bool isEstimate;
  final bool isArchived;
  final String note;
  const CustomUnit({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.substanceKey,
    required this.route,
    required this.name,
    required this.unitSingular,
    this.unitPlural,
    this.doseOfOneUnit,
    this.doseStdDev,
    required this.originalUnit,
    required this.isEstimate,
    required this.isArchived,
    required this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['substance_key'] = Variable<String>(substanceKey);
    map['route'] = Variable<String>(route);
    map['name'] = Variable<String>(name);
    map['unit_singular'] = Variable<String>(unitSingular);
    if (!nullToAbsent || unitPlural != null) {
      map['unit_plural'] = Variable<String>(unitPlural);
    }
    if (!nullToAbsent || doseOfOneUnit != null) {
      map['dose_of_one_unit'] = Variable<double>(doseOfOneUnit);
    }
    if (!nullToAbsent || doseStdDev != null) {
      map['dose_std_dev'] = Variable<double>(doseStdDev);
    }
    map['original_unit'] = Variable<String>(originalUnit);
    map['is_estimate'] = Variable<bool>(isEstimate);
    map['is_archived'] = Variable<bool>(isArchived);
    map['note'] = Variable<String>(note);
    return map;
  }

  CustomUnitsCompanion toCompanion(bool nullToAbsent) {
    return CustomUnitsCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      substanceKey: Value(substanceKey),
      route: Value(route),
      name: Value(name),
      unitSingular: Value(unitSingular),
      unitPlural: unitPlural == null && nullToAbsent
          ? const Value.absent()
          : Value(unitPlural),
      doseOfOneUnit: doseOfOneUnit == null && nullToAbsent
          ? const Value.absent()
          : Value(doseOfOneUnit),
      doseStdDev: doseStdDev == null && nullToAbsent
          ? const Value.absent()
          : Value(doseStdDev),
      originalUnit: Value(originalUnit),
      isEstimate: Value(isEstimate),
      isArchived: Value(isArchived),
      note: Value(note),
    );
  }

  factory CustomUnit.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomUnit(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      substanceKey: serializer.fromJson<String>(json['substanceKey']),
      route: serializer.fromJson<String>(json['route']),
      name: serializer.fromJson<String>(json['name']),
      unitSingular: serializer.fromJson<String>(json['unitSingular']),
      unitPlural: serializer.fromJson<String?>(json['unitPlural']),
      doseOfOneUnit: serializer.fromJson<double?>(json['doseOfOneUnit']),
      doseStdDev: serializer.fromJson<double?>(json['doseStdDev']),
      originalUnit: serializer.fromJson<String>(json['originalUnit']),
      isEstimate: serializer.fromJson<bool>(json['isEstimate']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      note: serializer.fromJson<String>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'substanceKey': serializer.toJson<String>(substanceKey),
      'route': serializer.toJson<String>(route),
      'name': serializer.toJson<String>(name),
      'unitSingular': serializer.toJson<String>(unitSingular),
      'unitPlural': serializer.toJson<String?>(unitPlural),
      'doseOfOneUnit': serializer.toJson<double?>(doseOfOneUnit),
      'doseStdDev': serializer.toJson<double?>(doseStdDev),
      'originalUnit': serializer.toJson<String>(originalUnit),
      'isEstimate': serializer.toJson<bool>(isEstimate),
      'isArchived': serializer.toJson<bool>(isArchived),
      'note': serializer.toJson<String>(note),
    };
  }

  CustomUnit copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? substanceKey,
    String? route,
    String? name,
    String? unitSingular,
    Value<String?> unitPlural = const Value.absent(),
    Value<double?> doseOfOneUnit = const Value.absent(),
    Value<double?> doseStdDev = const Value.absent(),
    String? originalUnit,
    bool? isEstimate,
    bool? isArchived,
    String? note,
  }) => CustomUnit(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    substanceKey: substanceKey ?? this.substanceKey,
    route: route ?? this.route,
    name: name ?? this.name,
    unitSingular: unitSingular ?? this.unitSingular,
    unitPlural: unitPlural.present ? unitPlural.value : this.unitPlural,
    doseOfOneUnit: doseOfOneUnit.present
        ? doseOfOneUnit.value
        : this.doseOfOneUnit,
    doseStdDev: doseStdDev.present ? doseStdDev.value : this.doseStdDev,
    originalUnit: originalUnit ?? this.originalUnit,
    isEstimate: isEstimate ?? this.isEstimate,
    isArchived: isArchived ?? this.isArchived,
    note: note ?? this.note,
  );
  CustomUnit copyWithCompanion(CustomUnitsCompanion data) {
    return CustomUnit(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      substanceKey: data.substanceKey.present
          ? data.substanceKey.value
          : this.substanceKey,
      route: data.route.present ? data.route.value : this.route,
      name: data.name.present ? data.name.value : this.name,
      unitSingular: data.unitSingular.present
          ? data.unitSingular.value
          : this.unitSingular,
      unitPlural: data.unitPlural.present
          ? data.unitPlural.value
          : this.unitPlural,
      doseOfOneUnit: data.doseOfOneUnit.present
          ? data.doseOfOneUnit.value
          : this.doseOfOneUnit,
      doseStdDev: data.doseStdDev.present
          ? data.doseStdDev.value
          : this.doseStdDev,
      originalUnit: data.originalUnit.present
          ? data.originalUnit.value
          : this.originalUnit,
      isEstimate: data.isEstimate.present
          ? data.isEstimate.value
          : this.isEstimate,
      isArchived: data.isArchived.present
          ? data.isArchived.value
          : this.isArchived,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomUnit(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('substanceKey: $substanceKey, ')
          ..write('route: $route, ')
          ..write('name: $name, ')
          ..write('unitSingular: $unitSingular, ')
          ..write('unitPlural: $unitPlural, ')
          ..write('doseOfOneUnit: $doseOfOneUnit, ')
          ..write('doseStdDev: $doseStdDev, ')
          ..write('originalUnit: $originalUnit, ')
          ..write('isEstimate: $isEstimate, ')
          ..write('isArchived: $isArchived, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hlc,
    deleted,
    substanceKey,
    route,
    name,
    unitSingular,
    unitPlural,
    doseOfOneUnit,
    doseStdDev,
    originalUnit,
    isEstimate,
    isArchived,
    note,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomUnit &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.substanceKey == this.substanceKey &&
          other.route == this.route &&
          other.name == this.name &&
          other.unitSingular == this.unitSingular &&
          other.unitPlural == this.unitPlural &&
          other.doseOfOneUnit == this.doseOfOneUnit &&
          other.doseStdDev == this.doseStdDev &&
          other.originalUnit == this.originalUnit &&
          other.isEstimate == this.isEstimate &&
          other.isArchived == this.isArchived &&
          other.note == this.note);
}

class CustomUnitsCompanion extends UpdateCompanion<CustomUnit> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> substanceKey;
  final Value<String> route;
  final Value<String> name;
  final Value<String> unitSingular;
  final Value<String?> unitPlural;
  final Value<double?> doseOfOneUnit;
  final Value<double?> doseStdDev;
  final Value<String> originalUnit;
  final Value<bool> isEstimate;
  final Value<bool> isArchived;
  final Value<String> note;
  final Value<int> rowid;
  const CustomUnitsCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.substanceKey = const Value.absent(),
    this.route = const Value.absent(),
    this.name = const Value.absent(),
    this.unitSingular = const Value.absent(),
    this.unitPlural = const Value.absent(),
    this.doseOfOneUnit = const Value.absent(),
    this.doseStdDev = const Value.absent(),
    this.originalUnit = const Value.absent(),
    this.isEstimate = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomUnitsCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String substanceKey,
    required String route,
    required String name,
    required String unitSingular,
    this.unitPlural = const Value.absent(),
    this.doseOfOneUnit = const Value.absent(),
    this.doseStdDev = const Value.absent(),
    required String originalUnit,
    this.isEstimate = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       substanceKey = Value(substanceKey),
       route = Value(route),
       name = Value(name),
       unitSingular = Value(unitSingular),
       originalUnit = Value(originalUnit);
  static Insertable<CustomUnit> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? substanceKey,
    Expression<String>? route,
    Expression<String>? name,
    Expression<String>? unitSingular,
    Expression<String>? unitPlural,
    Expression<double>? doseOfOneUnit,
    Expression<double>? doseStdDev,
    Expression<String>? originalUnit,
    Expression<bool>? isEstimate,
    Expression<bool>? isArchived,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (substanceKey != null) 'substance_key': substanceKey,
      if (route != null) 'route': route,
      if (name != null) 'name': name,
      if (unitSingular != null) 'unit_singular': unitSingular,
      if (unitPlural != null) 'unit_plural': unitPlural,
      if (doseOfOneUnit != null) 'dose_of_one_unit': doseOfOneUnit,
      if (doseStdDev != null) 'dose_std_dev': doseStdDev,
      if (originalUnit != null) 'original_unit': originalUnit,
      if (isEstimate != null) 'is_estimate': isEstimate,
      if (isArchived != null) 'is_archived': isArchived,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomUnitsCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? substanceKey,
    Value<String>? route,
    Value<String>? name,
    Value<String>? unitSingular,
    Value<String?>? unitPlural,
    Value<double?>? doseOfOneUnit,
    Value<double?>? doseStdDev,
    Value<String>? originalUnit,
    Value<bool>? isEstimate,
    Value<bool>? isArchived,
    Value<String>? note,
    Value<int>? rowid,
  }) {
    return CustomUnitsCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      substanceKey: substanceKey ?? this.substanceKey,
      route: route ?? this.route,
      name: name ?? this.name,
      unitSingular: unitSingular ?? this.unitSingular,
      unitPlural: unitPlural ?? this.unitPlural,
      doseOfOneUnit: doseOfOneUnit ?? this.doseOfOneUnit,
      doseStdDev: doseStdDev ?? this.doseStdDev,
      originalUnit: originalUnit ?? this.originalUnit,
      isEstimate: isEstimate ?? this.isEstimate,
      isArchived: isArchived ?? this.isArchived,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (substanceKey.present) {
      map['substance_key'] = Variable<String>(substanceKey.value);
    }
    if (route.present) {
      map['route'] = Variable<String>(route.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (unitSingular.present) {
      map['unit_singular'] = Variable<String>(unitSingular.value);
    }
    if (unitPlural.present) {
      map['unit_plural'] = Variable<String>(unitPlural.value);
    }
    if (doseOfOneUnit.present) {
      map['dose_of_one_unit'] = Variable<double>(doseOfOneUnit.value);
    }
    if (doseStdDev.present) {
      map['dose_std_dev'] = Variable<double>(doseStdDev.value);
    }
    if (originalUnit.present) {
      map['original_unit'] = Variable<String>(originalUnit.value);
    }
    if (isEstimate.present) {
      map['is_estimate'] = Variable<bool>(isEstimate.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomUnitsCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('substanceKey: $substanceKey, ')
          ..write('route: $route, ')
          ..write('name: $name, ')
          ..write('unitSingular: $unitSingular, ')
          ..write('unitPlural: $unitPlural, ')
          ..write('doseOfOneUnit: $doseOfOneUnit, ')
          ..write('doseStdDev: $doseStdDev, ')
          ..write('originalUnit: $originalUnit, ')
          ..write('isEstimate: $isEstimate, ')
          ..write('isArchived: $isArchived, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CustomSubstancesTable extends CustomSubstances
    with TableInfo<$CustomSubstancesTable, CustomSubstance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CustomSubstancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitsMeta = const VerificationMeta('units');
  @override
  late final GeneratedColumn<String> units = GeneratedColumn<String>(
    'units',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    name,
    units,
    description,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'custom_substances';
  @override
  VerificationContext validateIntegrity(
    Insertable<CustomSubstance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('units')) {
      context.handle(
        _unitsMeta,
        units.isAcceptableOrUnknown(data['units']!, _unitsMeta),
      );
    } else if (isInserting) {
      context.missing(_unitsMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CustomSubstance map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CustomSubstance(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      units: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}units'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
    );
  }

  @override
  $CustomSubstancesTable createAlias(String alias) {
    return $CustomSubstancesTable(attachedDatabase, alias);
  }
}

class CustomSubstance extends DataClass implements Insertable<CustomSubstance> {
  final String id;
  final String hlc;
  final bool deleted;
  final String name;
  final String units;
  final String description;
  const CustomSubstance({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.name,
    required this.units,
    required this.description,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['name'] = Variable<String>(name);
    map['units'] = Variable<String>(units);
    map['description'] = Variable<String>(description);
    return map;
  }

  CustomSubstancesCompanion toCompanion(bool nullToAbsent) {
    return CustomSubstancesCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      name: Value(name),
      units: Value(units),
      description: Value(description),
    );
  }

  factory CustomSubstance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CustomSubstance(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      name: serializer.fromJson<String>(json['name']),
      units: serializer.fromJson<String>(json['units']),
      description: serializer.fromJson<String>(json['description']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'name': serializer.toJson<String>(name),
      'units': serializer.toJson<String>(units),
      'description': serializer.toJson<String>(description),
    };
  }

  CustomSubstance copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? name,
    String? units,
    String? description,
  }) => CustomSubstance(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    name: name ?? this.name,
    units: units ?? this.units,
    description: description ?? this.description,
  );
  CustomSubstance copyWithCompanion(CustomSubstancesCompanion data) {
    return CustomSubstance(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      name: data.name.present ? data.name.value : this.name,
      units: data.units.present ? data.units.value : this.units,
      description: data.description.present
          ? data.description.value
          : this.description,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CustomSubstance(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('name: $name, ')
          ..write('units: $units, ')
          ..write('description: $description')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, hlc, deleted, name, units, description);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CustomSubstance &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.name == this.name &&
          other.units == this.units &&
          other.description == this.description);
}

class CustomSubstancesCompanion extends UpdateCompanion<CustomSubstance> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> name;
  final Value<String> units;
  final Value<String> description;
  final Value<int> rowid;
  const CustomSubstancesCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.name = const Value.absent(),
    this.units = const Value.absent(),
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CustomSubstancesCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String name,
    required String units,
    this.description = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       name = Value(name),
       units = Value(units);
  static Insertable<CustomSubstance> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? name,
    Expression<String>? units,
    Expression<String>? description,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (name != null) 'name': name,
      if (units != null) 'units': units,
      if (description != null) 'description': description,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CustomSubstancesCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? name,
    Value<String>? units,
    Value<String>? description,
    Value<int>? rowid,
  }) {
    return CustomSubstancesCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      name: name ?? this.name,
      units: units ?? this.units,
      description: description ?? this.description,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (units.present) {
      map['units'] = Variable<String>(units.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CustomSubstancesCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('name: $name, ')
          ..write('units: $units, ')
          ..write('description: $description, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProductsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _substanceKeyMeta = const VerificationMeta(
    'substanceKey',
  );
  @override
  late final GeneratedColumn<String> substanceKey = GeneratedColumn<String>(
    'substance_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _thcPercentMeta = const VerificationMeta(
    'thcPercent',
  );
  @override
  late final GeneratedColumn<double> thcPercent = GeneratedColumn<double>(
    'thc_percent',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cbdPercentMeta = const VerificationMeta(
    'cbdPercent',
  );
  @override
  late final GeneratedColumn<double> cbdPercent = GeneratedColumn<double>(
    'cbd_percent',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _detailsJsonMeta = const VerificationMeta(
    'detailsJson',
  );
  @override
  late final GeneratedColumn<String> detailsJson = GeneratedColumn<String>(
    'details_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    substanceKey,
    name,
    thcPercent,
    cbdPercent,
    detailsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'products';
  @override
  VerificationContext validateIntegrity(
    Insertable<Product> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('substance_key')) {
      context.handle(
        _substanceKeyMeta,
        substanceKey.isAcceptableOrUnknown(
          data['substance_key']!,
          _substanceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_substanceKeyMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('thc_percent')) {
      context.handle(
        _thcPercentMeta,
        thcPercent.isAcceptableOrUnknown(data['thc_percent']!, _thcPercentMeta),
      );
    }
    if (data.containsKey('cbd_percent')) {
      context.handle(
        _cbdPercentMeta,
        cbdPercent.isAcceptableOrUnknown(data['cbd_percent']!, _cbdPercentMeta),
      );
    }
    if (data.containsKey('details_json')) {
      context.handle(
        _detailsJsonMeta,
        detailsJson.isAcceptableOrUnknown(
          data['details_json']!,
          _detailsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Product(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      substanceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}substance_key'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      thcPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}thc_percent'],
      ),
      cbdPercent: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}cbd_percent'],
      ),
      detailsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details_json'],
      )!,
    );
  }

  @override
  $ProductsTable createAlias(String alias) {
    return $ProductsTable(attachedDatabase, alias);
  }
}

class Product extends DataClass implements Insertable<Product> {
  final String id;
  final String hlc;
  final bool deleted;
  final String substanceKey;
  final String name;
  final double? thcPercent;
  final double? cbdPercent;
  final String detailsJson;
  const Product({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.substanceKey,
    required this.name,
    this.thcPercent,
    this.cbdPercent,
    required this.detailsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['substance_key'] = Variable<String>(substanceKey);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || thcPercent != null) {
      map['thc_percent'] = Variable<double>(thcPercent);
    }
    if (!nullToAbsent || cbdPercent != null) {
      map['cbd_percent'] = Variable<double>(cbdPercent);
    }
    map['details_json'] = Variable<String>(detailsJson);
    return map;
  }

  ProductsCompanion toCompanion(bool nullToAbsent) {
    return ProductsCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      substanceKey: Value(substanceKey),
      name: Value(name),
      thcPercent: thcPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(thcPercent),
      cbdPercent: cbdPercent == null && nullToAbsent
          ? const Value.absent()
          : Value(cbdPercent),
      detailsJson: Value(detailsJson),
    );
  }

  factory Product.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Product(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      substanceKey: serializer.fromJson<String>(json['substanceKey']),
      name: serializer.fromJson<String>(json['name']),
      thcPercent: serializer.fromJson<double?>(json['thcPercent']),
      cbdPercent: serializer.fromJson<double?>(json['cbdPercent']),
      detailsJson: serializer.fromJson<String>(json['detailsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'substanceKey': serializer.toJson<String>(substanceKey),
      'name': serializer.toJson<String>(name),
      'thcPercent': serializer.toJson<double?>(thcPercent),
      'cbdPercent': serializer.toJson<double?>(cbdPercent),
      'detailsJson': serializer.toJson<String>(detailsJson),
    };
  }

  Product copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? substanceKey,
    String? name,
    Value<double?> thcPercent = const Value.absent(),
    Value<double?> cbdPercent = const Value.absent(),
    String? detailsJson,
  }) => Product(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    substanceKey: substanceKey ?? this.substanceKey,
    name: name ?? this.name,
    thcPercent: thcPercent.present ? thcPercent.value : this.thcPercent,
    cbdPercent: cbdPercent.present ? cbdPercent.value : this.cbdPercent,
    detailsJson: detailsJson ?? this.detailsJson,
  );
  Product copyWithCompanion(ProductsCompanion data) {
    return Product(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      substanceKey: data.substanceKey.present
          ? data.substanceKey.value
          : this.substanceKey,
      name: data.name.present ? data.name.value : this.name,
      thcPercent: data.thcPercent.present
          ? data.thcPercent.value
          : this.thcPercent,
      cbdPercent: data.cbdPercent.present
          ? data.cbdPercent.value
          : this.cbdPercent,
      detailsJson: data.detailsJson.present
          ? data.detailsJson.value
          : this.detailsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Product(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('substanceKey: $substanceKey, ')
          ..write('name: $name, ')
          ..write('thcPercent: $thcPercent, ')
          ..write('cbdPercent: $cbdPercent, ')
          ..write('detailsJson: $detailsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hlc,
    deleted,
    substanceKey,
    name,
    thcPercent,
    cbdPercent,
    detailsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Product &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.substanceKey == this.substanceKey &&
          other.name == this.name &&
          other.thcPercent == this.thcPercent &&
          other.cbdPercent == this.cbdPercent &&
          other.detailsJson == this.detailsJson);
}

class ProductsCompanion extends UpdateCompanion<Product> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> substanceKey;
  final Value<String> name;
  final Value<double?> thcPercent;
  final Value<double?> cbdPercent;
  final Value<String> detailsJson;
  final Value<int> rowid;
  const ProductsCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.substanceKey = const Value.absent(),
    this.name = const Value.absent(),
    this.thcPercent = const Value.absent(),
    this.cbdPercent = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProductsCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String substanceKey,
    required String name,
    this.thcPercent = const Value.absent(),
    this.cbdPercent = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       substanceKey = Value(substanceKey),
       name = Value(name);
  static Insertable<Product> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? substanceKey,
    Expression<String>? name,
    Expression<double>? thcPercent,
    Expression<double>? cbdPercent,
    Expression<String>? detailsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (substanceKey != null) 'substance_key': substanceKey,
      if (name != null) 'name': name,
      if (thcPercent != null) 'thc_percent': thcPercent,
      if (cbdPercent != null) 'cbd_percent': cbdPercent,
      if (detailsJson != null) 'details_json': detailsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProductsCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? substanceKey,
    Value<String>? name,
    Value<double?>? thcPercent,
    Value<double?>? cbdPercent,
    Value<String>? detailsJson,
    Value<int>? rowid,
  }) {
    return ProductsCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      substanceKey: substanceKey ?? this.substanceKey,
      name: name ?? this.name,
      thcPercent: thcPercent ?? this.thcPercent,
      cbdPercent: cbdPercent ?? this.cbdPercent,
      detailsJson: detailsJson ?? this.detailsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (substanceKey.present) {
      map['substance_key'] = Variable<String>(substanceKey.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (thcPercent.present) {
      map['thc_percent'] = Variable<double>(thcPercent.value);
    }
    if (cbdPercent.present) {
      map['cbd_percent'] = Variable<double>(cbdPercent.value);
    }
    if (detailsJson.present) {
      map['details_json'] = Variable<String>(detailsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProductsCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('substanceKey: $substanceKey, ')
          ..write('name: $name, ')
          ..write('thcPercent: $thcPercent, ')
          ..write('cbdPercent: $cbdPercent, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PresetsTable extends Presets with TableInfo<$PresetsTable, Preset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _substanceKeyMeta = const VerificationMeta(
    'substanceKey',
  );
  @override
  late final GeneratedColumn<String> substanceKey = GeneratedColumn<String>(
    'substance_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _routeMeta = const VerificationMeta('route');
  @override
  late final GeneratedColumn<String> route = GeneratedColumn<String>(
    'route',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detailsJsonMeta = const VerificationMeta(
    'detailsJson',
  );
  @override
  late final GeneratedColumn<String> detailsJson = GeneratedColumn<String>(
    'details_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hlc,
    deleted,
    substanceKey,
    route,
    name,
    amount,
    unit,
    detailsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'presets';
  @override
  VerificationContext validateIntegrity(
    Insertable<Preset> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('substance_key')) {
      context.handle(
        _substanceKeyMeta,
        substanceKey.isAcceptableOrUnknown(
          data['substance_key']!,
          _substanceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_substanceKeyMeta);
    }
    if (data.containsKey('route')) {
      context.handle(
        _routeMeta,
        route.isAcceptableOrUnknown(data['route']!, _routeMeta),
      );
    } else if (isInserting) {
      context.missing(_routeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    } else if (isInserting) {
      context.missing(_unitMeta);
    }
    if (data.containsKey('details_json')) {
      context.handle(
        _detailsJsonMeta,
        detailsJson.isAcceptableOrUnknown(
          data['details_json']!,
          _detailsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Preset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Preset(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      substanceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}substance_key'],
      )!,
      route: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}route'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}amount'],
      )!,
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      )!,
      detailsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}details_json'],
      )!,
    );
  }

  @override
  $PresetsTable createAlias(String alias) {
    return $PresetsTable(attachedDatabase, alias);
  }
}

class Preset extends DataClass implements Insertable<Preset> {
  final String id;
  final String hlc;
  final bool deleted;
  final String substanceKey;
  final String route;
  final String name;
  final double amount;
  final String unit;
  final String detailsJson;
  const Preset({
    required this.id,
    required this.hlc,
    required this.deleted,
    required this.substanceKey,
    required this.route,
    required this.name,
    required this.amount,
    required this.unit,
    required this.detailsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['hlc'] = Variable<String>(hlc);
    map['deleted'] = Variable<bool>(deleted);
    map['substance_key'] = Variable<String>(substanceKey);
    map['route'] = Variable<String>(route);
    map['name'] = Variable<String>(name);
    map['amount'] = Variable<double>(amount);
    map['unit'] = Variable<String>(unit);
    map['details_json'] = Variable<String>(detailsJson);
    return map;
  }

  PresetsCompanion toCompanion(bool nullToAbsent) {
    return PresetsCompanion(
      id: Value(id),
      hlc: Value(hlc),
      deleted: Value(deleted),
      substanceKey: Value(substanceKey),
      route: Value(route),
      name: Value(name),
      amount: Value(amount),
      unit: Value(unit),
      detailsJson: Value(detailsJson),
    );
  }

  factory Preset.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Preset(
      id: serializer.fromJson<String>(json['id']),
      hlc: serializer.fromJson<String>(json['hlc']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      substanceKey: serializer.fromJson<String>(json['substanceKey']),
      route: serializer.fromJson<String>(json['route']),
      name: serializer.fromJson<String>(json['name']),
      amount: serializer.fromJson<double>(json['amount']),
      unit: serializer.fromJson<String>(json['unit']),
      detailsJson: serializer.fromJson<String>(json['detailsJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'hlc': serializer.toJson<String>(hlc),
      'deleted': serializer.toJson<bool>(deleted),
      'substanceKey': serializer.toJson<String>(substanceKey),
      'route': serializer.toJson<String>(route),
      'name': serializer.toJson<String>(name),
      'amount': serializer.toJson<double>(amount),
      'unit': serializer.toJson<String>(unit),
      'detailsJson': serializer.toJson<String>(detailsJson),
    };
  }

  Preset copyWith({
    String? id,
    String? hlc,
    bool? deleted,
    String? substanceKey,
    String? route,
    String? name,
    double? amount,
    String? unit,
    String? detailsJson,
  }) => Preset(
    id: id ?? this.id,
    hlc: hlc ?? this.hlc,
    deleted: deleted ?? this.deleted,
    substanceKey: substanceKey ?? this.substanceKey,
    route: route ?? this.route,
    name: name ?? this.name,
    amount: amount ?? this.amount,
    unit: unit ?? this.unit,
    detailsJson: detailsJson ?? this.detailsJson,
  );
  Preset copyWithCompanion(PresetsCompanion data) {
    return Preset(
      id: data.id.present ? data.id.value : this.id,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      substanceKey: data.substanceKey.present
          ? data.substanceKey.value
          : this.substanceKey,
      route: data.route.present ? data.route.value : this.route,
      name: data.name.present ? data.name.value : this.name,
      amount: data.amount.present ? data.amount.value : this.amount,
      unit: data.unit.present ? data.unit.value : this.unit,
      detailsJson: data.detailsJson.present
          ? data.detailsJson.value
          : this.detailsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Preset(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('substanceKey: $substanceKey, ')
          ..write('route: $route, ')
          ..write('name: $name, ')
          ..write('amount: $amount, ')
          ..write('unit: $unit, ')
          ..write('detailsJson: $detailsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hlc,
    deleted,
    substanceKey,
    route,
    name,
    amount,
    unit,
    detailsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Preset &&
          other.id == this.id &&
          other.hlc == this.hlc &&
          other.deleted == this.deleted &&
          other.substanceKey == this.substanceKey &&
          other.route == this.route &&
          other.name == this.name &&
          other.amount == this.amount &&
          other.unit == this.unit &&
          other.detailsJson == this.detailsJson);
}

class PresetsCompanion extends UpdateCompanion<Preset> {
  final Value<String> id;
  final Value<String> hlc;
  final Value<bool> deleted;
  final Value<String> substanceKey;
  final Value<String> route;
  final Value<String> name;
  final Value<double> amount;
  final Value<String> unit;
  final Value<String> detailsJson;
  final Value<int> rowid;
  const PresetsCompanion({
    this.id = const Value.absent(),
    this.hlc = const Value.absent(),
    this.deleted = const Value.absent(),
    this.substanceKey = const Value.absent(),
    this.route = const Value.absent(),
    this.name = const Value.absent(),
    this.amount = const Value.absent(),
    this.unit = const Value.absent(),
    this.detailsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PresetsCompanion.insert({
    required String id,
    required String hlc,
    this.deleted = const Value.absent(),
    required String substanceKey,
    required String route,
    required String name,
    required double amount,
    required String unit,
    this.detailsJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       hlc = Value(hlc),
       substanceKey = Value(substanceKey),
       route = Value(route),
       name = Value(name),
       amount = Value(amount),
       unit = Value(unit);
  static Insertable<Preset> custom({
    Expression<String>? id,
    Expression<String>? hlc,
    Expression<bool>? deleted,
    Expression<String>? substanceKey,
    Expression<String>? route,
    Expression<String>? name,
    Expression<double>? amount,
    Expression<String>? unit,
    Expression<String>? detailsJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hlc != null) 'hlc': hlc,
      if (deleted != null) 'deleted': deleted,
      if (substanceKey != null) 'substance_key': substanceKey,
      if (route != null) 'route': route,
      if (name != null) 'name': name,
      if (amount != null) 'amount': amount,
      if (unit != null) 'unit': unit,
      if (detailsJson != null) 'details_json': detailsJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PresetsCompanion copyWith({
    Value<String>? id,
    Value<String>? hlc,
    Value<bool>? deleted,
    Value<String>? substanceKey,
    Value<String>? route,
    Value<String>? name,
    Value<double>? amount,
    Value<String>? unit,
    Value<String>? detailsJson,
    Value<int>? rowid,
  }) {
    return PresetsCompanion(
      id: id ?? this.id,
      hlc: hlc ?? this.hlc,
      deleted: deleted ?? this.deleted,
      substanceKey: substanceKey ?? this.substanceKey,
      route: route ?? this.route,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      unit: unit ?? this.unit,
      detailsJson: detailsJson ?? this.detailsJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (substanceKey.present) {
      map['substance_key'] = Variable<String>(substanceKey.value);
    }
    if (route.present) {
      map['route'] = Variable<String>(route.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (detailsJson.present) {
      map['details_json'] = Variable<String>(detailsJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PresetsCompanion(')
          ..write('id: $id, ')
          ..write('hlc: $hlc, ')
          ..write('deleted: $deleted, ')
          ..write('substanceKey: $substanceKey, ')
          ..write('route: $route, ')
          ..write('name: $name, ')
          ..write('amount: $amount, ')
          ..write('unit: $unit, ')
          ..write('detailsJson: $detailsJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hlcMeta = const VerificationMeta('hlc');
  @override
  late final GeneratedColumn<String> hlc = GeneratedColumn<String>(
    'hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sharedMeta = const VerificationMeta('shared');
  @override
  late final GeneratedColumn<bool> shared = GeneratedColumn<bool>(
    'shared',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("shared" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, hlc, shared];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('hlc')) {
      context.handle(
        _hlcMeta,
        hlc.isAcceptableOrUnknown(data['hlc']!, _hlcMeta),
      );
    } else if (isInserting) {
      context.missing(_hlcMeta);
    }
    if (data.containsKey('shared')) {
      context.handle(
        _sharedMeta,
        shared.isAcceptableOrUnknown(data['shared']!, _sharedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      hlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hlc'],
      )!,
      shared: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}shared'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  final String hlc;
  final bool shared;
  const Setting({
    required this.key,
    required this.value,
    required this.hlc,
    required this.shared,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['hlc'] = Variable<String>(hlc);
    map['shared'] = Variable<bool>(shared);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      hlc: Value(hlc),
      shared: Value(shared),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      hlc: serializer.fromJson<String>(json['hlc']),
      shared: serializer.fromJson<bool>(json['shared']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'hlc': serializer.toJson<String>(hlc),
      'shared': serializer.toJson<bool>(shared),
    };
  }

  Setting copyWith({String? key, String? value, String? hlc, bool? shared}) =>
      Setting(
        key: key ?? this.key,
        value: value ?? this.value,
        hlc: hlc ?? this.hlc,
        shared: shared ?? this.shared,
      );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      hlc: data.hlc.present ? data.hlc.value : this.hlc,
      shared: data.shared.present ? data.shared.value : this.shared,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('hlc: $hlc, ')
          ..write('shared: $shared')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, hlc, shared);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.key == this.key &&
          other.value == this.value &&
          other.hlc == this.hlc &&
          other.shared == this.shared);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<String> hlc;
  final Value<bool> shared;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.hlc = const Value.absent(),
    this.shared = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    required String hlc,
    this.shared = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value),
       hlc = Value(hlc);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<String>? hlc,
    Expression<bool>? shared,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (hlc != null) 'hlc': hlc,
      if (shared != null) 'shared': shared,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<String>? hlc,
    Value<bool>? shared,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      hlc: hlc ?? this.hlc,
      shared: shared ?? this.shared,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (hlc.present) {
      map['hlc'] = Variable<String>(hlc.value);
    }
    if (shared.present) {
      map['shared'] = Variable<bool>(shared.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('hlc: $hlc, ')
          ..write('shared: $shared, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeersTable extends Peers with TableInfo<$PeersTable, Peer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _publicKeyMeta = const VerificationMeta(
    'publicKey',
  );
  @override
  late final GeneratedColumn<String> publicKey = GeneratedColumn<String>(
    'public_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastKnownAddressMeta = const VerificationMeta(
    'lastKnownAddress',
  );
  @override
  late final GeneratedColumn<String> lastKnownAddress = GeneratedColumn<String>(
    'last_known_address',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncedHlcMeta = const VerificationMeta(
    'lastSyncedHlc',
  );
  @override
  late final GeneratedColumn<String> lastSyncedHlc = GeneratedColumn<String>(
    'last_synced_hlc',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pairedAt = GeneratedColumn<DateTime>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    name,
    publicKey,
    lastKnownAddress,
    lastSyncedHlc,
    pairedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peers';
  @override
  VerificationContext validateIntegrity(
    Insertable<Peer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('public_key')) {
      context.handle(
        _publicKeyMeta,
        publicKey.isAcceptableOrUnknown(data['public_key']!, _publicKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_publicKeyMeta);
    }
    if (data.containsKey('last_known_address')) {
      context.handle(
        _lastKnownAddressMeta,
        lastKnownAddress.isAcceptableOrUnknown(
          data['last_known_address']!,
          _lastKnownAddressMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_hlc')) {
      context.handle(
        _lastSyncedHlcMeta,
        lastSyncedHlc.isAcceptableOrUnknown(
          data['last_synced_hlc']!,
          _lastSyncedHlcMeta,
        ),
      );
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId};
  @override
  Peer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Peer(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      publicKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}public_key'],
      )!,
      lastKnownAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_known_address'],
      ),
      lastSyncedHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_synced_hlc'],
      )!,
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paired_at'],
      )!,
    );
  }

  @override
  $PeersTable createAlias(String alias) {
    return $PeersTable(attachedDatabase, alias);
  }
}

class Peer extends DataClass implements Insertable<Peer> {
  final String deviceId;
  final String name;
  final String publicKey;
  final String? lastKnownAddress;
  final String lastSyncedHlc;
  final DateTime pairedAt;
  const Peer({
    required this.deviceId,
    required this.name,
    required this.publicKey,
    this.lastKnownAddress,
    required this.lastSyncedHlc,
    required this.pairedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['name'] = Variable<String>(name);
    map['public_key'] = Variable<String>(publicKey);
    if (!nullToAbsent || lastKnownAddress != null) {
      map['last_known_address'] = Variable<String>(lastKnownAddress);
    }
    map['last_synced_hlc'] = Variable<String>(lastSyncedHlc);
    map['paired_at'] = Variable<DateTime>(pairedAt);
    return map;
  }

  PeersCompanion toCompanion(bool nullToAbsent) {
    return PeersCompanion(
      deviceId: Value(deviceId),
      name: Value(name),
      publicKey: Value(publicKey),
      lastKnownAddress: lastKnownAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(lastKnownAddress),
      lastSyncedHlc: Value(lastSyncedHlc),
      pairedAt: Value(pairedAt),
    );
  }

  factory Peer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Peer(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      name: serializer.fromJson<String>(json['name']),
      publicKey: serializer.fromJson<String>(json['publicKey']),
      lastKnownAddress: serializer.fromJson<String?>(json['lastKnownAddress']),
      lastSyncedHlc: serializer.fromJson<String>(json['lastSyncedHlc']),
      pairedAt: serializer.fromJson<DateTime>(json['pairedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'name': serializer.toJson<String>(name),
      'publicKey': serializer.toJson<String>(publicKey),
      'lastKnownAddress': serializer.toJson<String?>(lastKnownAddress),
      'lastSyncedHlc': serializer.toJson<String>(lastSyncedHlc),
      'pairedAt': serializer.toJson<DateTime>(pairedAt),
    };
  }

  Peer copyWith({
    String? deviceId,
    String? name,
    String? publicKey,
    Value<String?> lastKnownAddress = const Value.absent(),
    String? lastSyncedHlc,
    DateTime? pairedAt,
  }) => Peer(
    deviceId: deviceId ?? this.deviceId,
    name: name ?? this.name,
    publicKey: publicKey ?? this.publicKey,
    lastKnownAddress: lastKnownAddress.present
        ? lastKnownAddress.value
        : this.lastKnownAddress,
    lastSyncedHlc: lastSyncedHlc ?? this.lastSyncedHlc,
    pairedAt: pairedAt ?? this.pairedAt,
  );
  Peer copyWithCompanion(PeersCompanion data) {
    return Peer(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      name: data.name.present ? data.name.value : this.name,
      publicKey: data.publicKey.present ? data.publicKey.value : this.publicKey,
      lastKnownAddress: data.lastKnownAddress.present
          ? data.lastKnownAddress.value
          : this.lastKnownAddress,
      lastSyncedHlc: data.lastSyncedHlc.present
          ? data.lastSyncedHlc.value
          : this.lastSyncedHlc,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Peer(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('publicKey: $publicKey, ')
          ..write('lastKnownAddress: $lastKnownAddress, ')
          ..write('lastSyncedHlc: $lastSyncedHlc, ')
          ..write('pairedAt: $pairedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    name,
    publicKey,
    lastKnownAddress,
    lastSyncedHlc,
    pairedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Peer &&
          other.deviceId == this.deviceId &&
          other.name == this.name &&
          other.publicKey == this.publicKey &&
          other.lastKnownAddress == this.lastKnownAddress &&
          other.lastSyncedHlc == this.lastSyncedHlc &&
          other.pairedAt == this.pairedAt);
}

class PeersCompanion extends UpdateCompanion<Peer> {
  final Value<String> deviceId;
  final Value<String> name;
  final Value<String> publicKey;
  final Value<String?> lastKnownAddress;
  final Value<String> lastSyncedHlc;
  final Value<DateTime> pairedAt;
  final Value<int> rowid;
  const PeersCompanion({
    this.deviceId = const Value.absent(),
    this.name = const Value.absent(),
    this.publicKey = const Value.absent(),
    this.lastKnownAddress = const Value.absent(),
    this.lastSyncedHlc = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeersCompanion.insert({
    required String deviceId,
    required String name,
    required String publicKey,
    this.lastKnownAddress = const Value.absent(),
    this.lastSyncedHlc = const Value.absent(),
    required DateTime pairedAt,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       name = Value(name),
       publicKey = Value(publicKey),
       pairedAt = Value(pairedAt);
  static Insertable<Peer> custom({
    Expression<String>? deviceId,
    Expression<String>? name,
    Expression<String>? publicKey,
    Expression<String>? lastKnownAddress,
    Expression<String>? lastSyncedHlc,
    Expression<DateTime>? pairedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (name != null) 'name': name,
      if (publicKey != null) 'public_key': publicKey,
      if (lastKnownAddress != null) 'last_known_address': lastKnownAddress,
      if (lastSyncedHlc != null) 'last_synced_hlc': lastSyncedHlc,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeersCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? name,
    Value<String>? publicKey,
    Value<String?>? lastKnownAddress,
    Value<String>? lastSyncedHlc,
    Value<DateTime>? pairedAt,
    Value<int>? rowid,
  }) {
    return PeersCompanion(
      deviceId: deviceId ?? this.deviceId,
      name: name ?? this.name,
      publicKey: publicKey ?? this.publicKey,
      lastKnownAddress: lastKnownAddress ?? this.lastKnownAddress,
      lastSyncedHlc: lastSyncedHlc ?? this.lastSyncedHlc,
      pairedAt: pairedAt ?? this.pairedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (publicKey.present) {
      map['public_key'] = Variable<String>(publicKey.value);
    }
    if (lastKnownAddress.present) {
      map['last_known_address'] = Variable<String>(lastKnownAddress.value);
    }
    if (lastSyncedHlc.present) {
      map['last_synced_hlc'] = Variable<String>(lastSyncedHlc.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<DateTime>(pairedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeersCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('name: $name, ')
          ..write('publicKey: $publicKey, ')
          ..write('lastKnownAddress: $lastKnownAddress, ')
          ..write('lastSyncedHlc: $lastSyncedHlc, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PeopleTable people = $PeopleTable(this);
  late final $ExperiencesTable experiences = $ExperiencesTable(this);
  late final $IngestionsTable ingestions = $IngestionsTable(this);
  late final $TimedNotesTable timedNotes = $TimedNotesTable(this);
  late final $RatingsTable ratings = $RatingsTable(this);
  late final $CustomUnitsTable customUnits = $CustomUnitsTable(this);
  late final $CustomSubstancesTable customSubstances = $CustomSubstancesTable(
    this,
  );
  late final $ProductsTable products = $ProductsTable(this);
  late final $PresetsTable presets = $PresetsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $PeersTable peers = $PeersTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    people,
    experiences,
    ingestions,
    timedNotes,
    ratings,
    customUnits,
    customSubstances,
    products,
    presets,
    settings,
    peers,
  ];
}

typedef $$PeopleTableCreateCompanionBuilder = PeopleCompanion Function({
  required String id,
  required String hlc,
  Value<bool> deleted,
  required String name,
  Value<int> colorValue,
  Value<bool> isDefault,
  Value<int> rowid,
});
typedef $$PeopleTableUpdateCompanionBuilder = PeopleCompanion Function({
  Value<String> id,
  Value<String> hlc,
  Value<bool> deleted,
  Value<String> name,
  Value<int> colorValue,
  Value<bool> isDefault,
  Value<int> rowid,
});

final class $$PeopleTableReferences
    extends BaseReferences<_$AppDatabase, $PeopleTable, Person> {
  $$PeopleTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ExperiencesTable, List<Experience>>
  _experiencesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.experiences,
    aliasName: 'people__id__experiences__person_id',
  );

  $$ExperiencesTableProcessedTableManager get experiencesRefs {
    final manager = $$ExperiencesTableTableManager(
      $_db,
      $_db.experiences,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_experiencesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$IngestionsTable, List<Ingestion>>
  _ingestionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ingestions,
    aliasName: 'people__id__ingestions__person_id',
  );

  $$IngestionsTableProcessedTableManager get ingestionsRefs {
    final manager = $$IngestionsTableTableManager(
      $_db,
      $_db.ingestions,
    ).filter((f) => f.personId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ingestionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PeopleTableFilterComposer
    extends Composer<_$AppDatabase, $PeopleTable> {
  $$PeopleTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> experiencesRefs(
    Expression<bool> Function($$ExperiencesTableFilterComposer f) f,
  ) {
    final $$ExperiencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableFilterComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> ingestionsRefs(
    Expression<bool> Function($$IngestionsTableFilterComposer f) f,
  ) {
    final $$IngestionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ingestions,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IngestionsTableFilterComposer(
            $db: $db,
            $table: $db.ingestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PeopleTableOrderingComposer
    extends Composer<_$AppDatabase, $PeopleTable> {
  $$PeopleTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeopleTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeopleTable> {
  $$PeopleTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  Expression<T> experiencesRefs<T extends Object>(
    Expression<T> Function($$ExperiencesTableAnnotationComposer a) f,
  ) {
    final $$ExperiencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableAnnotationComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> ingestionsRefs<T extends Object>(
    Expression<T> Function($$IngestionsTableAnnotationComposer a) f,
  ) {
    final $$IngestionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ingestions,
      getReferencedColumn: (t) => t.personId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IngestionsTableAnnotationComposer(
            $db: $db,
            $table: $db.ingestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PeopleTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeopleTable,
          Person,
          $$PeopleTableFilterComposer,
          $$PeopleTableOrderingComposer,
          $$PeopleTableAnnotationComposer,
          $$PeopleTableCreateCompanionBuilder,
          $$PeopleTableUpdateCompanionBuilder,
          (Person, $$PeopleTableReferences),
          Person,
          PrefetchHooks Function({bool experiencesRefs, bool ingestionsRefs})
        > {
  $$PeopleTableTableManager(_$AppDatabase db, $PeopleTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeopleTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeopleTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeopleTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeopleCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                name: name,
                colorValue: colorValue,
                isDefault: isDefault,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String name,
                Value<int> colorValue = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeopleCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                name: name,
                colorValue: colorValue,
                isDefault: isDefault,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeopleTable, Person>(table),
                  $$PeopleTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({experiencesRefs = false, ingestionsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (experiencesRefs) db.experiences,
                    if (ingestionsRefs) db.ingestions,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (experiencesRefs)
                        await $_getPrefetchedDataByColumns<
                          Person,
                          $PeopleTable,
                          Experience,
                          $ExperiencesTable
                        >(
                          currentTable: table,
                          referencedTable: $$PeopleTableReferences
                              ._experiencesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PeopleTableReferences(
                                db,
                                table,
                                p0,
                              ).experiencesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'person_id',
                          typedResults: items,
                        ),
                      if (ingestionsRefs)
                        await $_getPrefetchedDataByColumns<
                          Person,
                          $PeopleTable,
                          Ingestion,
                          $IngestionsTable
                        >(
                          currentTable: table,
                          referencedTable: $$PeopleTableReferences
                              ._ingestionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PeopleTableReferences(
                                db,
                                table,
                                p0,
                              ).ingestionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'person_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PeopleTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeopleTable,
      Person,
      $$PeopleTableFilterComposer,
      $$PeopleTableOrderingComposer,
      $$PeopleTableAnnotationComposer,
      $$PeopleTableCreateCompanionBuilder,
      $$PeopleTableUpdateCompanionBuilder,
      (Person, $$PeopleTableReferences),
      Person,
      PrefetchHooks Function({bool experiencesRefs, bool ingestionsRefs})
    >;
typedef $$ExperiencesTableCreateCompanionBuilder =
    ExperiencesCompanion Function({
      required String id,
      required String hlc,
      Value<bool> deleted,
      required String personId,
      Value<String> title,
      Value<String> notes,
      required DateTime sortDate,
      required DateTime createdAt,
      Value<bool> isFavorite,
      Value<String?> locationName,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int> rowid,
    });
typedef $$ExperiencesTableUpdateCompanionBuilder =
    ExperiencesCompanion Function({
      Value<String> id,
      Value<String> hlc,
      Value<bool> deleted,
      Value<String> personId,
      Value<String> title,
      Value<String> notes,
      Value<DateTime> sortDate,
      Value<DateTime> createdAt,
      Value<bool> isFavorite,
      Value<String?> locationName,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<int> rowid,
    });

final class $$ExperiencesTableReferences
    extends BaseReferences<_$AppDatabase, $ExperiencesTable, Experience> {
  $$ExperiencesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PeopleTable _personIdTable(_$AppDatabase db) =>
      db.people.createAlias('experiences__person_id__people__id');

  $$PeopleTableProcessedTableManager get personId {
    final $_column = $_itemColumn<String>('person_id')!;

    final manager = $$PeopleTableTableManager(
      $_db,
      $_db.people,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$IngestionsTable, List<Ingestion>>
  _ingestionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.ingestions,
    aliasName: 'experiences__id__ingestions__experience_id',
  );

  $$IngestionsTableProcessedTableManager get ingestionsRefs {
    final manager = $$IngestionsTableTableManager(
      $_db,
      $_db.ingestions,
    ).filter((f) => f.experienceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ingestionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TimedNotesTable, List<TimedNote>>
  _timedNotesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.timedNotes,
    aliasName: 'experiences__id__timed_notes__experience_id',
  );

  $$TimedNotesTableProcessedTableManager get timedNotesRefs {
    final manager = $$TimedNotesTableTableManager(
      $_db,
      $_db.timedNotes,
    ).filter((f) => f.experienceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_timedNotesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RatingsTable, List<Rating>> _ratingsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.ratings,
    aliasName: 'experiences__id__ratings__experience_id',
  );

  $$RatingsTableProcessedTableManager get ratingsRefs {
    final manager = $$RatingsTableTableManager(
      $_db,
      $_db.ratings,
    ).filter((f) => f.experienceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_ratingsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ExperiencesTableFilterComposer
    extends Composer<_$AppDatabase, $ExperiencesTable> {
  $$ExperiencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get sortDate => $composableBuilder(
    column: $table.sortDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  $$PeopleTableFilterComposer get personId {
    final $$PeopleTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableFilterComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> ingestionsRefs(
    Expression<bool> Function($$IngestionsTableFilterComposer f) f,
  ) {
    final $$IngestionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ingestions,
      getReferencedColumn: (t) => t.experienceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IngestionsTableFilterComposer(
            $db: $db,
            $table: $db.ingestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> timedNotesRefs(
    Expression<bool> Function($$TimedNotesTableFilterComposer f) f,
  ) {
    final $$TimedNotesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.timedNotes,
      getReferencedColumn: (t) => t.experienceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TimedNotesTableFilterComposer(
            $db: $db,
            $table: $db.timedNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> ratingsRefs(
    Expression<bool> Function($$RatingsTableFilterComposer f) f,
  ) {
    final $$RatingsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ratings,
      getReferencedColumn: (t) => t.experienceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RatingsTableFilterComposer(
            $db: $db,
            $table: $db.ratings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExperiencesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExperiencesTable> {
  $$ExperiencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get sortDate => $composableBuilder(
    column: $table.sortDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  $$PeopleTableOrderingComposer get personId {
    final $$PeopleTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableOrderingComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ExperiencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExperiencesTable> {
  $$ExperiencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get sortDate =>
      $composableBuilder(column: $table.sortDate, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  $$PeopleTableAnnotationComposer get personId {
    final $$PeopleTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableAnnotationComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> ingestionsRefs<T extends Object>(
    Expression<T> Function($$IngestionsTableAnnotationComposer a) f,
  ) {
    final $$IngestionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ingestions,
      getReferencedColumn: (t) => t.experienceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$IngestionsTableAnnotationComposer(
            $db: $db,
            $table: $db.ingestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> timedNotesRefs<T extends Object>(
    Expression<T> Function($$TimedNotesTableAnnotationComposer a) f,
  ) {
    final $$TimedNotesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.timedNotes,
      getReferencedColumn: (t) => t.experienceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TimedNotesTableAnnotationComposer(
            $db: $db,
            $table: $db.timedNotes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> ratingsRefs<T extends Object>(
    Expression<T> Function($$RatingsTableAnnotationComposer a) f,
  ) {
    final $$RatingsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.ratings,
      getReferencedColumn: (t) => t.experienceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RatingsTableAnnotationComposer(
            $db: $db,
            $table: $db.ratings,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ExperiencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExperiencesTable,
          Experience,
          $$ExperiencesTableFilterComposer,
          $$ExperiencesTableOrderingComposer,
          $$ExperiencesTableAnnotationComposer,
          $$ExperiencesTableCreateCompanionBuilder,
          $$ExperiencesTableUpdateCompanionBuilder,
          (Experience, $$ExperiencesTableReferences),
          Experience,
          PrefetchHooks Function({
            bool personId,
            bool ingestionsRefs,
            bool timedNotesRefs,
            bool ratingsRefs,
          })
        > {
  $$ExperiencesTableTableManager(_$AppDatabase db, $ExperiencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExperiencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExperiencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExperiencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> personId = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<DateTime> sortDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> locationName = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExperiencesCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                personId: personId,
                title: title,
                notes: notes,
                sortDate: sortDate,
                createdAt: createdAt,
                isFavorite: isFavorite,
                locationName: locationName,
                latitude: latitude,
                longitude: longitude,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String personId,
                Value<String> title = const Value.absent(),
                Value<String> notes = const Value.absent(),
                required DateTime sortDate,
                required DateTime createdAt,
                Value<bool> isFavorite = const Value.absent(),
                Value<String?> locationName = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExperiencesCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                personId: personId,
                title: title,
                notes: notes,
                sortDate: sortDate,
                createdAt: createdAt,
                isFavorite: isFavorite,
                locationName: locationName,
                latitude: latitude,
                longitude: longitude,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExperiencesTable, Experience>(table),
                  $$ExperiencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                personId = false,
                ingestionsRefs = false,
                timedNotesRefs = false,
                ratingsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (ingestionsRefs) db.ingestions,
                    if (timedNotesRefs) db.timedNotes,
                    if (ratingsRefs) db.ratings,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (personId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.personId,
                            referencedTable: $$ExperiencesTableReferences
                                ._personIdTable(db),
                            referencedColumn: $$ExperiencesTableReferences
                                ._personIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (ingestionsRefs)
                        await $_getPrefetchedDataByColumns<
                          Experience,
                          $ExperiencesTable,
                          Ingestion,
                          $IngestionsTable
                        >(
                          currentTable: table,
                          referencedTable: $$ExperiencesTableReferences
                              ._ingestionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExperiencesTableReferences(
                                db,
                                table,
                                p0,
                              ).ingestionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'experience_id',
                          typedResults: items,
                        ),
                      if (timedNotesRefs)
                        await $_getPrefetchedDataByColumns<
                          Experience,
                          $ExperiencesTable,
                          TimedNote,
                          $TimedNotesTable
                        >(
                          currentTable: table,
                          referencedTable: $$ExperiencesTableReferences
                              ._timedNotesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExperiencesTableReferences(
                                db,
                                table,
                                p0,
                              ).timedNotesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'experience_id',
                          typedResults: items,
                        ),
                      if (ratingsRefs)
                        await $_getPrefetchedDataByColumns<
                          Experience,
                          $ExperiencesTable,
                          Rating,
                          $RatingsTable
                        >(
                          currentTable: table,
                          referencedTable: $$ExperiencesTableReferences
                              ._ratingsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ExperiencesTableReferences(
                                db,
                                table,
                                p0,
                              ).ratingsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'experience_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ExperiencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExperiencesTable,
      Experience,
      $$ExperiencesTableFilterComposer,
      $$ExperiencesTableOrderingComposer,
      $$ExperiencesTableAnnotationComposer,
      $$ExperiencesTableCreateCompanionBuilder,
      $$ExperiencesTableUpdateCompanionBuilder,
      (Experience, $$ExperiencesTableReferences),
      Experience,
      PrefetchHooks Function({
        bool personId,
        bool ingestionsRefs,
        bool timedNotesRefs,
        bool ratingsRefs,
      })
    >;
typedef $$IngestionsTableCreateCompanionBuilder = IngestionsCompanion Function({
  required String id,
  required String hlc,
  Value<bool> deleted,
  required String experienceId,
  required String personId,
  required String substanceKey,
  required String route,
  required DateTime time,
  Value<DateTime?> endTime,
  Value<double?> dose,
  Value<String?> unit,
  Value<bool> doseIsEstimate,
  Value<double?> doseStdDev,
  Value<String?> stomachFullness,
  Value<String?> customUnitId,
  Value<String?> productId,
  Value<double?> absorbedMg,
  Value<String?> method,
  Value<String> notes,
  Value<String> detailsJson,
  Value<int> rowid,
});
typedef $$IngestionsTableUpdateCompanionBuilder = IngestionsCompanion Function({
  Value<String> id,
  Value<String> hlc,
  Value<bool> deleted,
  Value<String> experienceId,
  Value<String> personId,
  Value<String> substanceKey,
  Value<String> route,
  Value<DateTime> time,
  Value<DateTime?> endTime,
  Value<double?> dose,
  Value<String?> unit,
  Value<bool> doseIsEstimate,
  Value<double?> doseStdDev,
  Value<String?> stomachFullness,
  Value<String?> customUnitId,
  Value<String?> productId,
  Value<double?> absorbedMg,
  Value<String?> method,
  Value<String> notes,
  Value<String> detailsJson,
  Value<int> rowid,
});

final class $$IngestionsTableReferences
    extends BaseReferences<_$AppDatabase, $IngestionsTable, Ingestion> {
  $$IngestionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ExperiencesTable _experienceIdTable(_$AppDatabase db) =>
      db.experiences.createAlias('ingestions__experience_id__experiences__id');

  $$ExperiencesTableProcessedTableManager get experienceId {
    final $_column = $_itemColumn<String>('experience_id')!;

    final manager = $$ExperiencesTableTableManager(
      $_db,
      $_db.experiences,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_experienceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PeopleTable _personIdTable(_$AppDatabase db) =>
      db.people.createAlias('ingestions__person_id__people__id');

  $$PeopleTableProcessedTableManager get personId {
    final $_column = $_itemColumn<String>('person_id')!;

    final manager = $$PeopleTableTableManager(
      $_db,
      $_db.people,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_personIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$IngestionsTableFilterComposer
    extends Composer<_$AppDatabase, $IngestionsTable> {
  $$IngestionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get dose => $composableBuilder(
    column: $table.dose,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get doseIsEstimate => $composableBuilder(
    column: $table.doseIsEstimate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get doseStdDev => $composableBuilder(
    column: $table.doseStdDev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stomachFullness => $composableBuilder(
    column: $table.stomachFullness,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customUnitId => $composableBuilder(
    column: $table.customUnitId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get absorbedMg => $composableBuilder(
    column: $table.absorbedMg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnFilters(column),
  );

  $$ExperiencesTableFilterComposer get experienceId {
    final $$ExperiencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableFilterComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PeopleTableFilterComposer get personId {
    final $$PeopleTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableFilterComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IngestionsTableOrderingComposer
    extends Composer<_$AppDatabase, $IngestionsTable> {
  $$IngestionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endTime => $composableBuilder(
    column: $table.endTime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get dose => $composableBuilder(
    column: $table.dose,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get doseIsEstimate => $composableBuilder(
    column: $table.doseIsEstimate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get doseStdDev => $composableBuilder(
    column: $table.doseStdDev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stomachFullness => $composableBuilder(
    column: $table.stomachFullness,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customUnitId => $composableBuilder(
    column: $table.customUnitId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get productId => $composableBuilder(
    column: $table.productId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get absorbedMg => $composableBuilder(
    column: $table.absorbedMg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get method => $composableBuilder(
    column: $table.method,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$ExperiencesTableOrderingComposer get experienceId {
    final $$ExperiencesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableOrderingComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PeopleTableOrderingComposer get personId {
    final $$PeopleTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableOrderingComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IngestionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $IngestionsTable> {
  $$IngestionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get route =>
      $composableBuilder(column: $table.route, builder: (column) => column);

  GeneratedColumn<DateTime> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<DateTime> get endTime =>
      $composableBuilder(column: $table.endTime, builder: (column) => column);

  GeneratedColumn<double> get dose =>
      $composableBuilder(column: $table.dose, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<bool> get doseIsEstimate => $composableBuilder(
    column: $table.doseIsEstimate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get doseStdDev => $composableBuilder(
    column: $table.doseStdDev,
    builder: (column) => column,
  );

  GeneratedColumn<String> get stomachFullness => $composableBuilder(
    column: $table.stomachFullness,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customUnitId => $composableBuilder(
    column: $table.customUnitId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get productId =>
      $composableBuilder(column: $table.productId, builder: (column) => column);

  GeneratedColumn<double> get absorbedMg => $composableBuilder(
    column: $table.absorbedMg,
    builder: (column) => column,
  );

  GeneratedColumn<String> get method =>
      $composableBuilder(column: $table.method, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => column,
  );

  $$ExperiencesTableAnnotationComposer get experienceId {
    final $$ExperiencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableAnnotationComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PeopleTableAnnotationComposer get personId {
    final $$PeopleTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.personId,
      referencedTable: $db.people,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PeopleTableAnnotationComposer(
            $db: $db,
            $table: $db.people,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$IngestionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IngestionsTable,
          Ingestion,
          $$IngestionsTableFilterComposer,
          $$IngestionsTableOrderingComposer,
          $$IngestionsTableAnnotationComposer,
          $$IngestionsTableCreateCompanionBuilder,
          $$IngestionsTableUpdateCompanionBuilder,
          (Ingestion, $$IngestionsTableReferences),
          Ingestion,
          PrefetchHooks Function({bool experienceId, bool personId})
        > {
  $$IngestionsTableTableManager(_$AppDatabase db, $IngestionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IngestionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IngestionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IngestionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> experienceId = const Value.absent(),
                Value<String> personId = const Value.absent(),
                Value<String> substanceKey = const Value.absent(),
                Value<String> route = const Value.absent(),
                Value<DateTime> time = const Value.absent(),
                Value<DateTime?> endTime = const Value.absent(),
                Value<double?> dose = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<bool> doseIsEstimate = const Value.absent(),
                Value<double?> doseStdDev = const Value.absent(),
                Value<String?> stomachFullness = const Value.absent(),
                Value<String?> customUnitId = const Value.absent(),
                Value<String?> productId = const Value.absent(),
                Value<double?> absorbedMg = const Value.absent(),
                Value<String?> method = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> detailsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IngestionsCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                experienceId: experienceId,
                personId: personId,
                substanceKey: substanceKey,
                route: route,
                time: time,
                endTime: endTime,
                dose: dose,
                unit: unit,
                doseIsEstimate: doseIsEstimate,
                doseStdDev: doseStdDev,
                stomachFullness: stomachFullness,
                customUnitId: customUnitId,
                productId: productId,
                absorbedMg: absorbedMg,
                method: method,
                notes: notes,
                detailsJson: detailsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String experienceId,
                required String personId,
                required String substanceKey,
                required String route,
                required DateTime time,
                Value<DateTime?> endTime = const Value.absent(),
                Value<double?> dose = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<bool> doseIsEstimate = const Value.absent(),
                Value<double?> doseStdDev = const Value.absent(),
                Value<String?> stomachFullness = const Value.absent(),
                Value<String?> customUnitId = const Value.absent(),
                Value<String?> productId = const Value.absent(),
                Value<double?> absorbedMg = const Value.absent(),
                Value<String?> method = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<String> detailsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IngestionsCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                experienceId: experienceId,
                personId: personId,
                substanceKey: substanceKey,
                route: route,
                time: time,
                endTime: endTime,
                dose: dose,
                unit: unit,
                doseIsEstimate: doseIsEstimate,
                doseStdDev: doseStdDev,
                stomachFullness: stomachFullness,
                customUnitId: customUnitId,
                productId: productId,
                absorbedMg: absorbedMg,
                method: method,
                notes: notes,
                detailsJson: detailsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$IngestionsTable, Ingestion>(table),
                  $$IngestionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({experienceId = false, personId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (experienceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.experienceId,
                        referencedTable: $$IngestionsTableReferences
                            ._experienceIdTable(db),
                        referencedColumn: $$IngestionsTableReferences
                            ._experienceIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (personId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.personId,
                        referencedTable: $$IngestionsTableReferences
                            ._personIdTable(db),
                        referencedColumn: $$IngestionsTableReferences
                            ._personIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$IngestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IngestionsTable,
      Ingestion,
      $$IngestionsTableFilterComposer,
      $$IngestionsTableOrderingComposer,
      $$IngestionsTableAnnotationComposer,
      $$IngestionsTableCreateCompanionBuilder,
      $$IngestionsTableUpdateCompanionBuilder,
      (Ingestion, $$IngestionsTableReferences),
      Ingestion,
      PrefetchHooks Function({bool experienceId, bool personId})
    >;
typedef $$TimedNotesTableCreateCompanionBuilder = TimedNotesCompanion Function({
  required String id,
  required String hlc,
  Value<bool> deleted,
  required String experienceId,
  required DateTime time,
  required String note,
  Value<int> colorValue,
  Value<bool> showOnTimeline,
  Value<int> rowid,
});
typedef $$TimedNotesTableUpdateCompanionBuilder = TimedNotesCompanion Function({
  Value<String> id,
  Value<String> hlc,
  Value<bool> deleted,
  Value<String> experienceId,
  Value<DateTime> time,
  Value<String> note,
  Value<int> colorValue,
  Value<bool> showOnTimeline,
  Value<int> rowid,
});

final class $$TimedNotesTableReferences
    extends BaseReferences<_$AppDatabase, $TimedNotesTable, TimedNote> {
  $$TimedNotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ExperiencesTable _experienceIdTable(_$AppDatabase db) =>
      db.experiences.createAlias('timed_notes__experience_id__experiences__id');

  $$ExperiencesTableProcessedTableManager get experienceId {
    final $_column = $_itemColumn<String>('experience_id')!;

    final manager = $$ExperiencesTableTableManager(
      $_db,
      $_db.experiences,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_experienceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TimedNotesTableFilterComposer
    extends Composer<_$AppDatabase, $TimedNotesTable> {
  $$TimedNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get showOnTimeline => $composableBuilder(
    column: $table.showOnTimeline,
    builder: (column) => ColumnFilters(column),
  );

  $$ExperiencesTableFilterComposer get experienceId {
    final $$ExperiencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableFilterComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimedNotesTableOrderingComposer
    extends Composer<_$AppDatabase, $TimedNotesTable> {
  $$TimedNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get showOnTimeline => $composableBuilder(
    column: $table.showOnTimeline,
    builder: (column) => ColumnOrderings(column),
  );

  $$ExperiencesTableOrderingComposer get experienceId {
    final $$ExperiencesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableOrderingComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimedNotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TimedNotesTable> {
  $$TimedNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<DateTime> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get showOnTimeline => $composableBuilder(
    column: $table.showOnTimeline,
    builder: (column) => column,
  );

  $$ExperiencesTableAnnotationComposer get experienceId {
    final $$ExperiencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableAnnotationComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimedNotesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TimedNotesTable,
          TimedNote,
          $$TimedNotesTableFilterComposer,
          $$TimedNotesTableOrderingComposer,
          $$TimedNotesTableAnnotationComposer,
          $$TimedNotesTableCreateCompanionBuilder,
          $$TimedNotesTableUpdateCompanionBuilder,
          (TimedNote, $$TimedNotesTableReferences),
          TimedNote,
          PrefetchHooks Function({bool experienceId})
        > {
  $$TimedNotesTableTableManager(_$AppDatabase db, $TimedNotesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimedNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimedNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TimedNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> experienceId = const Value.absent(),
                Value<DateTime> time = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<bool> showOnTimeline = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TimedNotesCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                experienceId: experienceId,
                time: time,
                note: note,
                colorValue: colorValue,
                showOnTimeline: showOnTimeline,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String experienceId,
                required DateTime time,
                required String note,
                Value<int> colorValue = const Value.absent(),
                Value<bool> showOnTimeline = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TimedNotesCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                experienceId: experienceId,
                time: time,
                note: note,
                colorValue: colorValue,
                showOnTimeline: showOnTimeline,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TimedNotesTable, TimedNote>(table),
                  $$TimedNotesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({experienceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (experienceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.experienceId,
                        referencedTable: $$TimedNotesTableReferences
                            ._experienceIdTable(db),
                        referencedColumn: $$TimedNotesTableReferences
                            ._experienceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TimedNotesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TimedNotesTable,
      TimedNote,
      $$TimedNotesTableFilterComposer,
      $$TimedNotesTableOrderingComposer,
      $$TimedNotesTableAnnotationComposer,
      $$TimedNotesTableCreateCompanionBuilder,
      $$TimedNotesTableUpdateCompanionBuilder,
      (TimedNote, $$TimedNotesTableReferences),
      TimedNote,
      PrefetchHooks Function({bool experienceId})
    >;
typedef $$RatingsTableCreateCompanionBuilder = RatingsCompanion Function({
  required String id,
  required String hlc,
  Value<bool> deleted,
  required String experienceId,
  Value<DateTime?> time,
  Value<String?> shulgin,
  Value<String> scoresJson,
  Value<int> rowid,
});
typedef $$RatingsTableUpdateCompanionBuilder = RatingsCompanion Function({
  Value<String> id,
  Value<String> hlc,
  Value<bool> deleted,
  Value<String> experienceId,
  Value<DateTime?> time,
  Value<String?> shulgin,
  Value<String> scoresJson,
  Value<int> rowid,
});

final class $$RatingsTableReferences
    extends BaseReferences<_$AppDatabase, $RatingsTable, Rating> {
  $$RatingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ExperiencesTable _experienceIdTable(_$AppDatabase db) =>
      db.experiences.createAlias('ratings__experience_id__experiences__id');

  $$ExperiencesTableProcessedTableManager get experienceId {
    final $_column = $_itemColumn<String>('experience_id')!;

    final manager = $$ExperiencesTableTableManager(
      $_db,
      $_db.experiences,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_experienceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RatingsTableFilterComposer
    extends Composer<_$AppDatabase, $RatingsTable> {
  $$RatingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get shulgin => $composableBuilder(
    column: $table.shulgin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scoresJson => $composableBuilder(
    column: $table.scoresJson,
    builder: (column) => ColumnFilters(column),
  );

  $$ExperiencesTableFilterComposer get experienceId {
    final $$ExperiencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableFilterComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RatingsTableOrderingComposer
    extends Composer<_$AppDatabase, $RatingsTable> {
  $$RatingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get time => $composableBuilder(
    column: $table.time,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get shulgin => $composableBuilder(
    column: $table.shulgin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scoresJson => $composableBuilder(
    column: $table.scoresJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$ExperiencesTableOrderingComposer get experienceId {
    final $$ExperiencesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableOrderingComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RatingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RatingsTable> {
  $$RatingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<DateTime> get time =>
      $composableBuilder(column: $table.time, builder: (column) => column);

  GeneratedColumn<String> get shulgin =>
      $composableBuilder(column: $table.shulgin, builder: (column) => column);

  GeneratedColumn<String> get scoresJson => $composableBuilder(
    column: $table.scoresJson,
    builder: (column) => column,
  );

  $$ExperiencesTableAnnotationComposer get experienceId {
    final $$ExperiencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.experienceId,
      referencedTable: $db.experiences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ExperiencesTableAnnotationComposer(
            $db: $db,
            $table: $db.experiences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RatingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RatingsTable,
          Rating,
          $$RatingsTableFilterComposer,
          $$RatingsTableOrderingComposer,
          $$RatingsTableAnnotationComposer,
          $$RatingsTableCreateCompanionBuilder,
          $$RatingsTableUpdateCompanionBuilder,
          (Rating, $$RatingsTableReferences),
          Rating,
          PrefetchHooks Function({bool experienceId})
        > {
  $$RatingsTableTableManager(_$AppDatabase db, $RatingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RatingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RatingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RatingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> experienceId = const Value.absent(),
                Value<DateTime?> time = const Value.absent(),
                Value<String?> shulgin = const Value.absent(),
                Value<String> scoresJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RatingsCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                experienceId: experienceId,
                time: time,
                shulgin: shulgin,
                scoresJson: scoresJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String experienceId,
                Value<DateTime?> time = const Value.absent(),
                Value<String?> shulgin = const Value.absent(),
                Value<String> scoresJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RatingsCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                experienceId: experienceId,
                time: time,
                shulgin: shulgin,
                scoresJson: scoresJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RatingsTable, Rating>(table),
                  $$RatingsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({experienceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (experienceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.experienceId,
                        referencedTable: $$RatingsTableReferences
                            ._experienceIdTable(db),
                        referencedColumn: $$RatingsTableReferences
                            ._experienceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RatingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RatingsTable,
      Rating,
      $$RatingsTableFilterComposer,
      $$RatingsTableOrderingComposer,
      $$RatingsTableAnnotationComposer,
      $$RatingsTableCreateCompanionBuilder,
      $$RatingsTableUpdateCompanionBuilder,
      (Rating, $$RatingsTableReferences),
      Rating,
      PrefetchHooks Function({bool experienceId})
    >;
typedef $$CustomUnitsTableCreateCompanionBuilder =
    CustomUnitsCompanion Function({
      required String id,
      required String hlc,
      Value<bool> deleted,
      required String substanceKey,
      required String route,
      required String name,
      required String unitSingular,
      Value<String?> unitPlural,
      Value<double?> doseOfOneUnit,
      Value<double?> doseStdDev,
      required String originalUnit,
      Value<bool> isEstimate,
      Value<bool> isArchived,
      Value<String> note,
      Value<int> rowid,
    });
typedef $$CustomUnitsTableUpdateCompanionBuilder =
    CustomUnitsCompanion Function({
      Value<String> id,
      Value<String> hlc,
      Value<bool> deleted,
      Value<String> substanceKey,
      Value<String> route,
      Value<String> name,
      Value<String> unitSingular,
      Value<String?> unitPlural,
      Value<double?> doseOfOneUnit,
      Value<double?> doseStdDev,
      Value<String> originalUnit,
      Value<bool> isEstimate,
      Value<bool> isArchived,
      Value<String> note,
      Value<int> rowid,
    });

class $$CustomUnitsTableFilterComposer
    extends Composer<_$AppDatabase, $CustomUnitsTable> {
  $$CustomUnitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unitSingular => $composableBuilder(
    column: $table.unitSingular,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unitPlural => $composableBuilder(
    column: $table.unitPlural,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get doseOfOneUnit => $composableBuilder(
    column: $table.doseOfOneUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get doseStdDev => $composableBuilder(
    column: $table.doseStdDev,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get originalUnit => $composableBuilder(
    column: $table.originalUnit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isEstimate => $composableBuilder(
    column: $table.isEstimate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomUnitsTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomUnitsTable> {
  $$CustomUnitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unitSingular => $composableBuilder(
    column: $table.unitSingular,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unitPlural => $composableBuilder(
    column: $table.unitPlural,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get doseOfOneUnit => $composableBuilder(
    column: $table.doseOfOneUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get doseStdDev => $composableBuilder(
    column: $table.doseStdDev,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get originalUnit => $composableBuilder(
    column: $table.originalUnit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isEstimate => $composableBuilder(
    column: $table.isEstimate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomUnitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomUnitsTable> {
  $$CustomUnitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get route =>
      $composableBuilder(column: $table.route, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get unitSingular => $composableBuilder(
    column: $table.unitSingular,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unitPlural => $composableBuilder(
    column: $table.unitPlural,
    builder: (column) => column,
  );

  GeneratedColumn<double> get doseOfOneUnit => $composableBuilder(
    column: $table.doseOfOneUnit,
    builder: (column) => column,
  );

  GeneratedColumn<double> get doseStdDev => $composableBuilder(
    column: $table.doseStdDev,
    builder: (column) => column,
  );

  GeneratedColumn<String> get originalUnit => $composableBuilder(
    column: $table.originalUnit,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isEstimate => $composableBuilder(
    column: $table.isEstimate,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isArchived => $composableBuilder(
    column: $table.isArchived,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$CustomUnitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomUnitsTable,
          CustomUnit,
          $$CustomUnitsTableFilterComposer,
          $$CustomUnitsTableOrderingComposer,
          $$CustomUnitsTableAnnotationComposer,
          $$CustomUnitsTableCreateCompanionBuilder,
          $$CustomUnitsTableUpdateCompanionBuilder,
          (
            CustomUnit,
            BaseReferences<_$AppDatabase, $CustomUnitsTable, CustomUnit>,
          ),
          CustomUnit,
          PrefetchHooks Function()
        > {
  $$CustomUnitsTableTableManager(_$AppDatabase db, $CustomUnitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomUnitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomUnitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomUnitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> substanceKey = const Value.absent(),
                Value<String> route = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> unitSingular = const Value.absent(),
                Value<String?> unitPlural = const Value.absent(),
                Value<double?> doseOfOneUnit = const Value.absent(),
                Value<double?> doseStdDev = const Value.absent(),
                Value<String> originalUnit = const Value.absent(),
                Value<bool> isEstimate = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomUnitsCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                substanceKey: substanceKey,
                route: route,
                name: name,
                unitSingular: unitSingular,
                unitPlural: unitPlural,
                doseOfOneUnit: doseOfOneUnit,
                doseStdDev: doseStdDev,
                originalUnit: originalUnit,
                isEstimate: isEstimate,
                isArchived: isArchived,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String substanceKey,
                required String route,
                required String name,
                required String unitSingular,
                Value<String?> unitPlural = const Value.absent(),
                Value<double?> doseOfOneUnit = const Value.absent(),
                Value<double?> doseStdDev = const Value.absent(),
                required String originalUnit,
                Value<bool> isEstimate = const Value.absent(),
                Value<bool> isArchived = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomUnitsCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                substanceKey: substanceKey,
                route: route,
                name: name,
                unitSingular: unitSingular,
                unitPlural: unitPlural,
                doseOfOneUnit: doseOfOneUnit,
                doseStdDev: doseStdDev,
                originalUnit: originalUnit,
                isEstimate: isEstimate,
                isArchived: isArchived,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CustomUnitsTable, CustomUnit>(table),
                  BaseReferences<_$AppDatabase, $CustomUnitsTable, CustomUnit>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomUnitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomUnitsTable,
      CustomUnit,
      $$CustomUnitsTableFilterComposer,
      $$CustomUnitsTableOrderingComposer,
      $$CustomUnitsTableAnnotationComposer,
      $$CustomUnitsTableCreateCompanionBuilder,
      $$CustomUnitsTableUpdateCompanionBuilder,
      (
        CustomUnit,
        BaseReferences<_$AppDatabase, $CustomUnitsTable, CustomUnit>,
      ),
      CustomUnit,
      PrefetchHooks Function()
    >;
typedef $$CustomSubstancesTableCreateCompanionBuilder =
    CustomSubstancesCompanion Function({
      required String id,
      required String hlc,
      Value<bool> deleted,
      required String name,
      required String units,
      Value<String> description,
      Value<int> rowid,
    });
typedef $$CustomSubstancesTableUpdateCompanionBuilder =
    CustomSubstancesCompanion Function({
      Value<String> id,
      Value<String> hlc,
      Value<bool> deleted,
      Value<String> name,
      Value<String> units,
      Value<String> description,
      Value<int> rowid,
    });

class $$CustomSubstancesTableFilterComposer
    extends Composer<_$AppDatabase, $CustomSubstancesTable> {
  $$CustomSubstancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get units => $composableBuilder(
    column: $table.units,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CustomSubstancesTableOrderingComposer
    extends Composer<_$AppDatabase, $CustomSubstancesTable> {
  $$CustomSubstancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get units => $composableBuilder(
    column: $table.units,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CustomSubstancesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CustomSubstancesTable> {
  $$CustomSubstancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get units =>
      $composableBuilder(column: $table.units, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );
}

class $$CustomSubstancesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CustomSubstancesTable,
          CustomSubstance,
          $$CustomSubstancesTableFilterComposer,
          $$CustomSubstancesTableOrderingComposer,
          $$CustomSubstancesTableAnnotationComposer,
          $$CustomSubstancesTableCreateCompanionBuilder,
          $$CustomSubstancesTableUpdateCompanionBuilder,
          (
            CustomSubstance,
            BaseReferences<
              _$AppDatabase,
              $CustomSubstancesTable,
              CustomSubstance
            >,
          ),
          CustomSubstance,
          PrefetchHooks Function()
        > {
  $$CustomSubstancesTableTableManager(
    _$AppDatabase db,
    $CustomSubstancesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CustomSubstancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CustomSubstancesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CustomSubstancesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> units = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomSubstancesCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                name: name,
                units: units,
                description: description,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String name,
                required String units,
                Value<String> description = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CustomSubstancesCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                name: name,
                units: units,
                description: description,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CustomSubstancesTable, CustomSubstance>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $CustomSubstancesTable,
                    CustomSubstance
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CustomSubstancesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CustomSubstancesTable,
      CustomSubstance,
      $$CustomSubstancesTableFilterComposer,
      $$CustomSubstancesTableOrderingComposer,
      $$CustomSubstancesTableAnnotationComposer,
      $$CustomSubstancesTableCreateCompanionBuilder,
      $$CustomSubstancesTableUpdateCompanionBuilder,
      (
        CustomSubstance,
        BaseReferences<_$AppDatabase, $CustomSubstancesTable, CustomSubstance>,
      ),
      CustomSubstance,
      PrefetchHooks Function()
    >;
typedef $$ProductsTableCreateCompanionBuilder = ProductsCompanion Function({
  required String id,
  required String hlc,
  Value<bool> deleted,
  required String substanceKey,
  required String name,
  Value<double?> thcPercent,
  Value<double?> cbdPercent,
  Value<String> detailsJson,
  Value<int> rowid,
});
typedef $$ProductsTableUpdateCompanionBuilder = ProductsCompanion Function({
  Value<String> id,
  Value<String> hlc,
  Value<bool> deleted,
  Value<String> substanceKey,
  Value<String> name,
  Value<double?> thcPercent,
  Value<double?> cbdPercent,
  Value<String> detailsJson,
  Value<int> rowid,
});

class $$ProductsTableFilterComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get thcPercent => $composableBuilder(
    column: $table.thcPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get cbdPercent => $composableBuilder(
    column: $table.cbdPercent,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProductsTableOrderingComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get thcPercent => $composableBuilder(
    column: $table.thcPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get cbdPercent => $composableBuilder(
    column: $table.cbdPercent,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProductsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProductsTable> {
  $$ProductsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get thcPercent => $composableBuilder(
    column: $table.thcPercent,
    builder: (column) => column,
  );

  GeneratedColumn<double> get cbdPercent => $composableBuilder(
    column: $table.cbdPercent,
    builder: (column) => column,
  );

  GeneratedColumn<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => column,
  );
}

class $$ProductsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProductsTable,
          Product,
          $$ProductsTableFilterComposer,
          $$ProductsTableOrderingComposer,
          $$ProductsTableAnnotationComposer,
          $$ProductsTableCreateCompanionBuilder,
          $$ProductsTableUpdateCompanionBuilder,
          (Product, BaseReferences<_$AppDatabase, $ProductsTable, Product>),
          Product,
          PrefetchHooks Function()
        > {
  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProductsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProductsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProductsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> substanceKey = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double?> thcPercent = const Value.absent(),
                Value<double?> cbdPercent = const Value.absent(),
                Value<String> detailsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                substanceKey: substanceKey,
                name: name,
                thcPercent: thcPercent,
                cbdPercent: cbdPercent,
                detailsJson: detailsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String substanceKey,
                required String name,
                Value<double?> thcPercent = const Value.absent(),
                Value<double?> cbdPercent = const Value.absent(),
                Value<String> detailsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProductsCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                substanceKey: substanceKey,
                name: name,
                thcPercent: thcPercent,
                cbdPercent: cbdPercent,
                detailsJson: detailsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProductsTable, Product>(table),
                  BaseReferences<_$AppDatabase, $ProductsTable, Product>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProductsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProductsTable,
      Product,
      $$ProductsTableFilterComposer,
      $$ProductsTableOrderingComposer,
      $$ProductsTableAnnotationComposer,
      $$ProductsTableCreateCompanionBuilder,
      $$ProductsTableUpdateCompanionBuilder,
      (Product, BaseReferences<_$AppDatabase, $ProductsTable, Product>),
      Product,
      PrefetchHooks Function()
    >;
typedef $$PresetsTableCreateCompanionBuilder = PresetsCompanion Function({
  required String id,
  required String hlc,
  Value<bool> deleted,
  required String substanceKey,
  required String route,
  required String name,
  required double amount,
  required String unit,
  Value<String> detailsJson,
  Value<int> rowid,
});
typedef $$PresetsTableUpdateCompanionBuilder = PresetsCompanion Function({
  Value<String> id,
  Value<String> hlc,
  Value<bool> deleted,
  Value<String> substanceKey,
  Value<String> route,
  Value<String> name,
  Value<double> amount,
  Value<String> unit,
  Value<String> detailsJson,
  Value<int> rowid,
});

class $$PresetsTableFilterComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PresetsTableOrderingComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get route => $composableBuilder(
    column: $table.route,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PresetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get substanceKey => $composableBuilder(
    column: $table.substanceKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get route =>
      $composableBuilder(column: $table.route, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<String> get detailsJson => $composableBuilder(
    column: $table.detailsJson,
    builder: (column) => column,
  );
}

class $$PresetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PresetsTable,
          Preset,
          $$PresetsTableFilterComposer,
          $$PresetsTableOrderingComposer,
          $$PresetsTableAnnotationComposer,
          $$PresetsTableCreateCompanionBuilder,
          $$PresetsTableUpdateCompanionBuilder,
          (Preset, BaseReferences<_$AppDatabase, $PresetsTable, Preset>),
          Preset,
          PrefetchHooks Function()
        > {
  $$PresetsTableTableManager(_$AppDatabase db, $PresetsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PresetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PresetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String> substanceKey = const Value.absent(),
                Value<String> route = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<double> amount = const Value.absent(),
                Value<String> unit = const Value.absent(),
                Value<String> detailsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PresetsCompanion(
                id: id,
                hlc: hlc,
                deleted: deleted,
                substanceKey: substanceKey,
                route: route,
                name: name,
                amount: amount,
                unit: unit,
                detailsJson: detailsJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String hlc,
                Value<bool> deleted = const Value.absent(),
                required String substanceKey,
                required String route,
                required String name,
                required double amount,
                required String unit,
                Value<String> detailsJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PresetsCompanion.insert(
                id: id,
                hlc: hlc,
                deleted: deleted,
                substanceKey: substanceKey,
                route: route,
                name: name,
                amount: amount,
                unit: unit,
                detailsJson: detailsJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PresetsTable, Preset>(table),
                  BaseReferences<_$AppDatabase, $PresetsTable, Preset>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PresetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PresetsTable,
      Preset,
      $$PresetsTableFilterComposer,
      $$PresetsTableOrderingComposer,
      $$PresetsTableAnnotationComposer,
      $$PresetsTableCreateCompanionBuilder,
      $$PresetsTableUpdateCompanionBuilder,
      (Preset, BaseReferences<_$AppDatabase, $PresetsTable, Preset>),
      Preset,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  required String hlc,
  Value<bool> shared,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<String> hlc,
  Value<bool> shared,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get shared => $composableBuilder(
    column: $table.shared,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hlc => $composableBuilder(
    column: $table.hlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get shared => $composableBuilder(
    column: $table.shared,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<String> get hlc =>
      $composableBuilder(column: $table.hlc, builder: (column) => column);

  GeneratedColumn<bool> get shared =>
      $composableBuilder(column: $table.shared, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<String> hlc = const Value.absent(),
                Value<bool> shared = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                hlc: hlc,
                shared: shared,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                required String hlc,
                Value<bool> shared = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                hlc: hlc,
                shared: shared,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$PeersTableCreateCompanionBuilder = PeersCompanion Function({
  required String deviceId,
  required String name,
  required String publicKey,
  Value<String?> lastKnownAddress,
  Value<String> lastSyncedHlc,
  required DateTime pairedAt,
  Value<int> rowid,
});
typedef $$PeersTableUpdateCompanionBuilder = PeersCompanion Function({
  Value<String> deviceId,
  Value<String> name,
  Value<String> publicKey,
  Value<String?> lastKnownAddress,
  Value<String> lastSyncedHlc,
  Value<DateTime> pairedAt,
  Value<int> rowid,
});

class $$PeersTableFilterComposer extends Composer<_$AppDatabase, $PeersTable> {
  $$PeersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastKnownAddress => $composableBuilder(
    column: $table.lastKnownAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSyncedHlc => $composableBuilder(
    column: $table.lastSyncedHlc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeersTableOrderingComposer
    extends Composer<_$AppDatabase, $PeersTable> {
  $$PeersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publicKey => $composableBuilder(
    column: $table.publicKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastKnownAddress => $composableBuilder(
    column: $table.lastKnownAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSyncedHlc => $composableBuilder(
    column: $table.lastSyncedHlc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeersTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeersTable> {
  $$PeersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get publicKey =>
      $composableBuilder(column: $table.publicKey, builder: (column) => column);

  GeneratedColumn<String> get lastKnownAddress => $composableBuilder(
    column: $table.lastKnownAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSyncedHlc => $composableBuilder(
    column: $table.lastSyncedHlc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);
}

class $$PeersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeersTable,
          Peer,
          $$PeersTableFilterComposer,
          $$PeersTableOrderingComposer,
          $$PeersTableAnnotationComposer,
          $$PeersTableCreateCompanionBuilder,
          $$PeersTableUpdateCompanionBuilder,
          (Peer, BaseReferences<_$AppDatabase, $PeersTable, Peer>),
          Peer,
          PrefetchHooks Function()
        > {
  $$PeersTableTableManager(_$AppDatabase db, $PeersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> publicKey = const Value.absent(),
                Value<String?> lastKnownAddress = const Value.absent(),
                Value<String> lastSyncedHlc = const Value.absent(),
                Value<DateTime> pairedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeersCompanion(
                deviceId: deviceId,
                name: name,
                publicKey: publicKey,
                lastKnownAddress: lastKnownAddress,
                lastSyncedHlc: lastSyncedHlc,
                pairedAt: pairedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String name,
                required String publicKey,
                Value<String?> lastKnownAddress = const Value.absent(),
                Value<String> lastSyncedHlc = const Value.absent(),
                required DateTime pairedAt,
                Value<int> rowid = const Value.absent(),
              }) => PeersCompanion.insert(
                deviceId: deviceId,
                name: name,
                publicKey: publicKey,
                lastKnownAddress: lastKnownAddress,
                lastSyncedHlc: lastSyncedHlc,
                pairedAt: pairedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeersTable, Peer>(table),
                  BaseReferences<_$AppDatabase, $PeersTable, Peer>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeersTable,
      Peer,
      $$PeersTableFilterComposer,
      $$PeersTableOrderingComposer,
      $$PeersTableAnnotationComposer,
      $$PeersTableCreateCompanionBuilder,
      $$PeersTableUpdateCompanionBuilder,
      (Peer, BaseReferences<_$AppDatabase, $PeersTable, Peer>),
      Peer,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PeopleTableTableManager get people =>
      $$PeopleTableTableManager(_db, _db.people);
  $$ExperiencesTableTableManager get experiences =>
      $$ExperiencesTableTableManager(_db, _db.experiences);
  $$IngestionsTableTableManager get ingestions =>
      $$IngestionsTableTableManager(_db, _db.ingestions);
  $$TimedNotesTableTableManager get timedNotes =>
      $$TimedNotesTableTableManager(_db, _db.timedNotes);
  $$RatingsTableTableManager get ratings =>
      $$RatingsTableTableManager(_db, _db.ratings);
  $$CustomUnitsTableTableManager get customUnits =>
      $$CustomUnitsTableTableManager(_db, _db.customUnits);
  $$CustomSubstancesTableTableManager get customSubstances =>
      $$CustomSubstancesTableTableManager(_db, _db.customSubstances);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db, _db.products);
  $$PresetsTableTableManager get presets =>
      $$PresetsTableTableManager(_db, _db.presets);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$PeersTableTableManager get peers =>
      $$PeersTableTableManager(_db, _db.peers);
}
