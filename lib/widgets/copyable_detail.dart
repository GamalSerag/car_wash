import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> copyDetail(BuildContext context, String value) async {
  try {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم النسخ')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر النسخ. حاول مرة أخرى')),
      );
    }
  }
}

class CopyableDetail extends StatelessWidget {
  const CopyableDetail({
    super.key,
    required this.label,
    required this.value,
    this.textDirection,
  });

  final String label;
  final String value;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                SelectableText(value, textDirection: textDirection),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'نسخ $label',
            onPressed: () => copyDetail(context, value),
            icon: const Icon(Icons.copy_outlined),
          ),
        ],
      ),
    );
  }
}
