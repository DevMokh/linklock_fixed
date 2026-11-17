import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../crypto_service.dart';
import '../device_key_store.dart';

class EncryptTab extends StatefulWidget {
  const EncryptTab({super.key});

  @override
  State<EncryptTab> createState() => _EncryptTabState();
}

class _EncryptTabState extends State<EncryptTab>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _link = TextEditingController();
  final _crypto = LinkCrypto(deviceKeyProvider: DeviceKeyStore().getOrCreateKey);

  bool _deviceOnly = false;
  bool _busy = false;
  String? _result;
  bool _resultDeviceOnly = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _link.text = text);
    }
  }

  Future<void> _encrypt() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final deviceOnly = _deviceOnly;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final token = await _crypto.encrypt(_link.text, deviceOnly: deviceOnly);
      if (!mounted) return;
      setState(() {
        _result = token;
        _resultDeviceOnly = deviceOnly;
      });
    } on LinkCryptoException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('حصل خطأ غير متوقع أثناء التشفير');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final result = _result;
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: result));
    _toast('اتنسخ النص المشفّر');
  }

  Future<void> _share() async {
    final result = _result;
    if (result == null) return;
    await Share.share(result);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _link,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'الرابط',
                  hintText: 'https://example.com/...',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: IconButton(
                    tooltip: 'لصق',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _paste,
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'اكتب الرابط الأول'
                    : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _deviceOnly,
                onChanged:
                    _busy ? null : (v) => setState(() => _deviceOnly = v),
                title: const Text('اقفله على الجهاز ده بس'),
                subtitle: Text(
                  _deviceOnly
                      ? 'محدش يقدر يفتحه غير على الجهاز ده، ومش هينفع تبعته لحد.'
                      : 'تمويه للمشاركة: أي حد معاه النص والتطبيق يقدر يفتحه. '
                          'شغّل الخيار ده لو عايز حماية حقيقية.',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _encrypt,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_rounded),
                label: Text(_busy ? 'بيشفّر...' : 'شفّر الرابط'),
              ),
            ],
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('النص المشفّر', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(
                      _result!,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _copy,
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('نسخ'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _share,
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('مشاركة'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _resultDeviceOnly
                        ? 'اتشفّر بمفتاح محفوظ في الجهاز ده. لو مسحت التطبيق '
                            'أو غيّرت الجهاز مش هتقدر تفتحه.'
                        : 'المفتاح جوه النص نفسه، فبيتفتح على أي جهاز عليه '
                            'التطبيق. ده تمويه مش حماية.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
