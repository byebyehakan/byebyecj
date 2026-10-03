import 'package:byebyecj/byebyecj.dart';

Future<void> demoStore() async {
  final db = await ByebyeCJ.open('demo.db');

  await db.put('products', 'p1', {
    'name': 'Widget',
    'price': 99,
  });

  final product = await db.get('products', 'p1');
  print(product);

  await db.close();
}
