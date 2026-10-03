# ByebyeCJ

byebyehakan tarafından geliştirilen küçük ve deneysel bir Dart depolama motorudur.

ByebyeCJ, uygulamalar için hafif, yerel ve sayfa tabanlı bir veri deposu sağlar. SQLite/Hive/Isar gibi hazır çözümlerin üzerine kurulmaz; yerine kendi depolama katmanı, sayfa yönetimi, kayıt yapısı ve temel indeks/query mantığına odaklanır.

## Nedir?

ByebyeCJ, yerel veri saklama için küçük ama anlaşılır bir altyapı sunar. Uygulama içi verileri dosyaya kaydetmek, açmak, sorgulamak ve yeniden başlatma sonrası veriyi korumak için tasarlanmıştır.

## Özellikler

- Sayfa tabanlı dosya yapısı
- sabit boyutlu sayfalar
- kayıt tabanlı veri saklama
- JSON serializer ile map dönüştürme
- yeniden açıldığında veriyi koruma
- temel put/get/delete/query akışı
- transaction ile commit/rollback
- index desteği ve sorgu seçimi
- benchmark/ölçüm desteği

## Kurulum

```bash
dart pub add byebyecj
```

## Hızlı kullanım

```dart
import 'package:byebyecj/byebyecj.dart';

Future<void> main() async {
  final db = await ByebyeCJ.open('app.db');

  await db.put('users', '123', {
    'name': 'Hakan',
    'age': 20,
  });

  final user = await db.get('users', '123');
  print(user);

  await db.close();
}
```

## Transaction örneği

```dart
await db.transaction((tx) async {
  await tx.put('users', '123', {'name': 'Hakan'});
  await tx.put('accounts', 'a1', {'balance': 100});
});
```

## Benchmark

Kütüphane içinde temel benchmark aracı vardır:

```bash
dart run tool/benchmark.dart
```

Bu araç:
- yazma hızı
- okuma hızı
- index sorgu hızı
- full scan hızı
- compaction süresini ölçer

## Test

```bash
dart test
```

## Not

Bu proje, hazır bir üretim veritabanı değil; daha çok öğrenilebilir, genişletilebilir ve yerel veri katmanı için tasarlanmış bir geliştirici platformudur.

## Lisans

MIT lisansı ile sunulmaktadır.
Copyright (c) 2026 byebyehakan

---

Created by byebyehakan
