import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:substance_journal_app/data/cannabis_products.dart';

import 'helpers.dart';

void main() {
  testWidgets('picking a saved product fills THC, and the dose remembers the product', (tester) async {
    final app = await buildTestApp(tester);
    final product = await dbRun(
      tester,
      () => app.db.addProduct(
        substanceKey: 'cannabis',
        name: 'Blue Dream',
        thcPercent: 20,
        cbdPercent: 0.5,
        details: const ProductDetails(costPerGram: 10).toJson(),
      ),
    );
    await startApp(tester, app);
    await tapKey(tester, 'journal-add');
    await tapKey(tester, 'compound-cannabis');
    await tapKey(tester, 'route-smoked');

    await tapKey(tester, 'cannabis-product-pick');
    await tester.tap(find.text('Blue Dream').last);
    await settle(tester);
    expect(find.widgetWithText(TextFormField, '20'), findsOneWidget); // THC filled in

    await tester.enterText(find.byKey(const ValueKey('cannabis-grams')), '0.5');
    await settle(tester, rounds: 2);
    expect(find.text('THC consumed: 100.0 mg'), findsOneWidget);

    await tapKey(tester, 'primary-action');
    await tapKey(tester, 'primary-action');

    final person = (await dbRun(tester, app.db.activePeople)).single;
    final row = (await dbRun(tester, () => app.db.ingestionsForPerson(person.id))).single;
    expect(row.productId, product.id);
    expect(row.detailsJson, contains('"product":"Blue Dream"'));

    final usage = ProductUsage.of(product, [row]);
    expect(usage.doses, 1);
    expect(usage.grams, closeTo(0.5, 1e-9));
    expect(usage.spend, closeTo(5, 1e-9)); // half a gram at $10 a gram
    await disposeApp(tester, app);
  });

  testWidgets('the products page adds, lists and removes a product, with undo', (tester) async {
    final app = await buildTestApp(tester);
    await startApp(tester, app);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tapKey(tester, 'manage-products');
    expect(find.textContaining('Save a strain or batch once'), findsOneWidget);

    await tapKey(tester, 'add-product');
    await tapKey(tester, 'product-save');
    expect(find.text('Give it a name.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('product-name')), 'Gelato');
    await tester.enterText(find.byKey(const ValueKey('product-thc')), '24');
    await tester.enterText(find.byKey(const ValueKey('product-source')), 'Local shop');
    await tapKey(tester, 'product-save');
    expect(find.text('Gelato'), findsOneWidget);
    expect(find.textContaining('THC 24%'), findsOneWidget);
    expect(find.textContaining('From Local shop'), findsOneWidget);
    expect(find.textContaining('Not used yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await settle(tester);
    expect(find.text('Gelato'), findsNothing);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('Gelato'), findsOneWidget);
    await disposeApp(tester, app);
  });
}
