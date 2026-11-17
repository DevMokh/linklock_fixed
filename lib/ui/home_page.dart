import 'package:flutter/material.dart';

import '../device_key_store.dart';
import 'decrypt_tab.dart';
import 'encrypt_tab.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _rotateDeviceKey(BuildContext context) async {
    final store = DeviceKeyStore();
    final hadKey = await store.hasKey();
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تدوير مفتاح الجهاز؟'),
        content: Text(
          hadKey
              ? 'هيتعمل مفتاح جديد للجهاز ده دلوقتي. أي رابط اتشفّر قبل كده '
                  'بخيار "على الجهاز ده بس" مش هينفع يتفتح تاني أبدًا، لا '
                  'على الجهاز ده ولا على أي جهاز تاني.'
              : 'هيتعمل أول مفتاح جهاز هنا. مفيش روابط مشفّرة هتتأثر '
                  'دلوقتي.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: hadKey
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(hadKey ? 'دوّر المفتاح' : 'أنشئ المفتاح'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await store.rotateKey();
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('اتعمل مفتاح جهاز جديد')));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('قفل الروابط'),
          actions: [
            IconButton(
              tooltip: 'تدوير مفتاح الجهاز',
              icon: const Icon(Icons.autorenew_rounded),
              onPressed: () => _rotateDeviceKey(context),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.lock_outline), text: 'تشفير'),
              Tab(icon: Icon(Icons.lock_open_outlined), text: 'فك التشفير'),
            ],
          ),
        ),
        body: const SafeArea(
          child: TabBarView(
            children: [
              EncryptTab(),
              DecryptTab(),
            ],
          ),
        ),
      ),
    );
  }
}
