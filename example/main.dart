import 'package:byebyecj/byebyecj.dart';

Future<void> main() async {
  final db = await ByebyeCJ.open('example.db');

  await db.put('users', '1', {
    'name': 'Ali',
    'role': 'developer',
  });

  final user = await db.get('users', '1');
  print('User: $user');

  await db.close();
}
