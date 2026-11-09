import 'package:sqflite/sqflite.dart';

/// Reuses native repository transactions inside the approval transaction.
/// It cannot commit, close, or start an independent connection.
class TransactionDatabase implements Database, Transaction {
  TransactionDatabase(this.tx);
  final Transaction tx;
  @override
  Database get database => this;
  @override
  bool get isOpen => true;
  @override
  String get path => tx.database.path;
  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction) action, {
    bool? exclusive,
  }) => action(this);
  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction) action) =>
      action(this);
  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      tx.execute(sql, arguments);
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => tx.rawQuery(sql, arguments);
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      tx.rawInsert(sql, arguments);
  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      tx.rawUpdate(sql, arguments);
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      tx.rawDelete(sql, arguments);
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => tx.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );
  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => tx.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );
  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      tx.delete(table, where: where, whereArgs: whereArgs);
  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => tx.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );
  @override
  Batch batch() => tx.batch();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Operation not allowed inside approval transaction: ${invocation.memberName}',
  );
}
