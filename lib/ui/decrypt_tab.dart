import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../crypto_service.dart';
import '../device_key_store.dart';

class DecryptTab extends StatefulWidget {
  const DecryptTab({super.key});

  @override
  State<DecryptTab> createState() => _DecryptTabState();
}

class _DecryptTabState extends State<DecryptTab>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _crypto = LinkCrypto(deviceKeyProvider: DeviceKeyStore().getOrCreateKey);

  bool _busy = false;
  String? _result;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _token.dispose();
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
      setState(() => _token.text = text);
    }
  }

  Future<void> _decrypt() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final link = await _crypto.decrypt(_token.text);
      if (!mounted) return;
      setState(() => _result = link);
    } on LinkCryptoException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('حصل خطأ غير متوقع أثناء فك التشفير');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final result = _result;
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: result));
    _toast('اتنسخ الرابط');
  }

  Uri? get _openableUri {
    final text = _result?.trim();
    if (text == null) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    return uri;
  }

  Future<void> _open() async {
    final uri = _openableUri;
    if (uri == null) return;

    // Never open automatically: show the full link and ask first.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فتح الرابط؟'),
        content: Directionality(
          textDirection: TextDirection.ltr,
          child: SelectableText(uri.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('افتح'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) _toast('مقدرتش أفتح الرابط');
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
                controller: _token,
                minLines: 3,
                maxLines: 5,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: 'النص المشفّر',
                  hintText: 'LL3.…',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'لصق',
                    icon: const Icon(Icons.content_paste_rounded),
                    onPressed: _paste,
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'الصق النص المشفّر الأول'
                    : null,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _decrypt,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(_busy ? 'بيفك التشفير...' : 'فك التشفير'),
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
                  Text('الرابط', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SelectableText(_result!),
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
                      if (_openableUri != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _open,
                            icon: const Icon(Icons.open_in_new_rounded),
                            label: const Text('فتح'),
                          ),
                        ),
                      ],
                    ],
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
