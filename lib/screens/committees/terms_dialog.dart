import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../providers/locale_provider.dart';
import 'package:provider/provider.dart';

/// Shows bilingual (Urdu + English) Terms & Conditions before the user
/// creates their first committee.  Returns true when the user accepts,
/// false / null when they decline.
Future<bool> showTermsDialog(BuildContext context) async {
  final bool? accepted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) => const _TermsDialog(),
  );
  return accepted == true;
}

class _TermsDialog extends StatefulWidget {
  const _TermsDialog();

  @override
  State<_TermsDialog> createState() => _TermsDialogState();
}

class _TermsDialogState extends State<_TermsDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isUrdu =
        context.watch<LocaleProvider>().language.code == 'ur';

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Terms & Conditions', style: theme.textTheme.titleLarge),
          Text(
            'شرائط و ضوابط',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[

              // ── English ──────────────────────────────────────────────
              _SectionHeader(
                en: 'Please read before creating a committee',
                ur: 'کمیٹی بنانے سے پہلے پڑھیں',
              ),

              _Term(
                number: '1',
                en: 'This app is a local-only tool. All data stays on your device. The developer is not responsible for any financial disputes between members.',
                ur: '۱. یہ ایپ صرف مقامی استعمال کے لیے ہے۔ تمام ڈیٹا آپ کے ڈیوائس پر رہتا ہے۔ اراکین کے درمیان کسی مالی تنازعے کی ذمہ داری ڈویلپر پر نہیں ہے۔',
              ),
              _Term(
                number: '2',
                en: 'The organiser is responsible for collecting and distributing funds fairly. The app only tracks records — it does not move money.',
                ur: '۲. منتظم رقم جمع کرنے اور منصفانہ تقسیم کا ذمہ دار ہے۔ ایپ صرف ریکارڈ رکھتی ہے — رقم منتقل نہیں کرتی۔',
              ),
              _Term(
                number: '3',
                en: 'Never share your PIN or OTP code with anyone, including the committee organiser.',
                ur: '۳. اپنا پِن یا او-ٹی-پی کوڈ کسی کو نہ دیں، بشمول کمیٹی منتظم۔',
              ),
              _Term(
                number: '4',
                en: 'Always agree on the contribution amount and payout order with all members before starting the committee.',
                ur: '۴. کمیٹی شروع کرنے سے پہلے تمام اراکین سے چندہ کی رقم اور ادائیگی کی ترتیب پر اتفاق ضروری ہے۔',
              ),
              _Term(
                number: '5',
                en: 'The developer provides this app as-is with no warranty. Use at your own risk.',
                ur: '۵. ڈویلپر یہ ایپ بغیر کسی ضمانت کے فراہم کرتا ہے۔ اپنے خطرے پر استعمال کریں۔',
              ),
              _Term(
                number: '6',
                en: 'Payments recorded in this app are for your reference only and do not constitute a legal contract.',
                ur: '۶. اس ایپ میں درج ادائیگیاں صرف آپ کے حوالے کے لیے ہیں اور قانونی معاہدہ نہیں ہیں۔',
              ),
              _Term(
                number: '7',
                en: 'Join codes allow other users to view committee details. Only share the code with trusted members.',
                ur: '۷. شمولیت کوڈ دوسرے صارفین کو کمیٹی کی تفصیلات دیکھنے دیتا ہے۔ صرف قابل اعتماد اراکین کو کوڈ دیں۔',
              ),

              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),

              // Checkbox
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Checkbox(
                    value: _agreed,
                    onChanged: (bool? v) => setState(() => _agreed = v ?? false),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _agreed = !_agreed),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SizedBox(height: 12),
                          Text(
                            'I have read and agree to these terms.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            'میں نے یہ شرائط پڑھی ہیں اور متفق ہوں۔',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Decline / انکار'),
        ),
        FilledButton(
          onPressed: _agreed ? () => Navigator.pop(context, true) : null,
          child: const Text('Accept & Continue / قبول کریں'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.en, required this.ur});
  final String en;
  final String ur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(en, style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.brandIndigo, fontWeight: FontWeight.w700)),
          Text(ur, style: theme.textTheme.labelMedium?.copyWith(
            color: AppColors.brandIndigo, fontWeight: FontWeight.w700),
            textDirection: TextDirection.rtl),
        ],
      ),
    );
  }
}

class _Term extends StatelessWidget {
  const _Term({required this.number, required this.en, required this.ur});
  final String number;
  final String en;
  final String ur;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(en, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            ur,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }
}
