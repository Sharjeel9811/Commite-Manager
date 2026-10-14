import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/committee.dart';
import '../models/member.dart';
import '../models/payment.dart';
import '../models/payment_schedule.dart';
import '../services/committee_service.dart';

/// Generates and shares a professional PDF report for a completed or active
/// committee.  The organiser can tap "Generate Report" from the committee
/// details screen to get a shareable PDF.
class ReportService {
  const ReportService();

  static const String reportFilename = 'committee_report.pdf';

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ public API

  /// Builds the PDF and immediately opens the OS share sheet / print dialog.
  Future<void> generateAndShare({required CommitteeBundle bundle}) async {
    await Printing.sharePdf(
      bytes: await buildPdfBytes(bundle: bundle),
      filename: reportFilename,
    );
  }

  /// Builds a complete report without invoking the platform share sheet.
  ///
  /// Keeping document generation separate makes failures deterministic and
  /// allows callers/tests to verify large committees before sharing.
  Future<Uint8List> buildPdfBytes({required CommitteeBundle bundle}) async {
    final pw.Document pdf = await _buildPdf(bundle);
    return pdf.save();
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ PDF layout

  Future<pw.Document> _buildPdf(CommitteeBundle bundle) async {
    final pw.Document doc = pw.Document(
      title: '${bundle.committee.name} â€” Committee Report',
      author: 'Committee Manager',
    );

    // Use built-in Helvetica - no network call, always works offline.
    final pw.ThemeData theme = pw.ThemeData.base();

    final Committee c = bundle.committee;

    // â”€â”€ Summary stats â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    final int totalMembers = bundle.members.length;
    final double collected = bundle.payments
        .where((Payment p) => p.isPaid)
        .fold<double>(0, (double s, Payment p) => s + p.amount);
    final double pending = bundle.payments
        .where((Payment p) => !p.isPaid)
        .fold<double>(0, (double s, Payment p) => s + p.amount);
    final int paidCount = bundle.payments.where((Payment p) => p.isPaid).length;
    final int overdueCount = bundle.payments
        .where((Payment p) => !p.isPaid && p.dueDate.isBefore(DateTime.now()))
        .length;

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        maxPages: 500,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context ctx) => _header(ctx, c),
        footer: (pw.Context ctx) => _footer(ctx),
        build: (pw.Context ctx) => <pw.Widget>[
          _summarySection(
            c,
            totalMembers,
            collected,
            pending,
            paidCount,
            overdueCount,
          ),
          pw.SizedBox(height: 20),
          _membersSection(bundle),
          pw.SizedBox(height: 20),
          _periodsSection(bundle),
          pw.SizedBox(height: 20),
          ..._paymentDetailsSections(bundle),
        ],
      ),
    );

    return doc;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Sections

  pw.Widget _header(pw.Context ctx, Committee c) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.indigo700, width: 2),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: 8),
      margin: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text(
                'Committee Report',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.indigo700,
                ),
              ),
              pw.Text(
                c.name,
                style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Text(
                'Committee Manager',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
              pw.Text(
                _fmt(DateTime.now()),
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: <pw.Widget>[
          pw.Text(
            'Generated by Committee Manager',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey400),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: PdfColors.grey400),
          ),
        ],
      ),
    );
  }

  pw.Widget _summarySection(
    Committee c,
    int totalMembers,
    double collected,
    double pending,
    int paidCount,
    int overdueCount,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _sectionTitle('Committee Summary'),
        pw.SizedBox(height: 8),
        pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColors.indigo50,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.indigo100),
          ),
          padding: const pw.EdgeInsets.all(12),
          child: pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    _kv('Committee Name', c.name),
                    _kv('Status', c.status.label),
                    _kv('Frequency', c.frequency.label),
                    _kv('Start Date', _fmt(c.startDate)),
                    _kv('End Date', _fmt(c.lastDueDate)),
                  ],
                ),
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    _kv('Total Members', '$totalMembers'),
                    _kv(
                      'Contribution / Period',
                      'Rs ${_money(c.contributionAmount)}',
                    ),
                    _kv('Pot Per Turn', 'Rs ${_money(c.totalPoolPerTurn)}'),
                    _kv('Total Periods', '${c.durationPeriods}'),
                    _kv('Completed Turns', '${c.completedTurns}'),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        // Financial summary row
        pw.Row(
          children: <pw.Widget>[
            _statBox(
              'Collected',
              'Rs ${_money(collected)}',
              PdfColors.green700,
              PdfColors.green50,
            ),
            pw.SizedBox(width: 8),
            _statBox(
              'Pending',
              'Rs ${_money(pending)}',
              PdfColors.orange700,
              PdfColors.orange50,
            ),
            pw.SizedBox(width: 8),
            _statBox(
              'Paid Payments',
              '$paidCount',
              PdfColors.blue700,
              PdfColors.blue50,
            ),
            pw.SizedBox(width: 8),
            _statBox(
              'Overdue',
              '$overdueCount',
              PdfColors.red700,
              PdfColors.red50,
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _membersSection(CommitteeBundle bundle) {
    final List<Member> members = List<Member>.of(bundle.members)
      ..sort((Member a, Member b) => a.turnNumber.compareTo(b.turnNumber));
    final Map<String, List<Payment>> paymentsByMember =
        <String, List<Payment>>{};
    for (final Payment payment in bundle.payments) {
      (paymentsByMember[payment.memberId] ??= <Payment>[]).add(payment);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _sectionTitle('Members and Collection Order'),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: <String>[
            'Turn #',
            'Name',
            'Phone',
            'Role',
            'Paid',
            'Pending',
            'Amount Paid',
          ],
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 9,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
          cellStyle: pw.TextStyle(fontSize: 8),
          cellAlignments: <int, pw.Alignment>{
            0: pw.Alignment.center,
            4: pw.Alignment.center,
            5: pw.Alignment.center,
            6: pw.Alignment.centerRight,
          },
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          data: members.map((Member m) {
            final List<Payment> mPayments =
                paymentsByMember[m.id] ?? <Payment>[];
            final int paid = mPayments.where((Payment p) => p.isPaid).length;
            final int pend = mPayments.where((Payment p) => !p.isPaid).length;
            final double amount = mPayments
                .where((Payment p) => p.isPaid)
                .fold<double>(0, (double s, Payment p) => s + p.amount);
            return <String>[
              '${m.turnNumber}',
              m.name,
              m.phoneNumber ?? '-',
              m.isOrganizer ? 'Organiser' : 'Member',
              '$paid',
              '$pend',
              'Rs ${_money(amount)}',
            ];
          }).toList(),
        ),
      ],
    );
  }

  pw.Widget _periodsSection(CommitteeBundle bundle) {
    final List<PaymentSchedule> periods =
        List<PaymentSchedule>.of(bundle.periods)..sort(
          (PaymentSchedule a, PaymentSchedule b) =>
              a.periodNumber.compareTo(b.periodNumber),
        );
    final Map<int, List<Payment>> paymentsByPeriod = <int, List<Payment>>{};
    for (final Payment payment in bundle.payments) {
      (paymentsByPeriod[payment.periodNumber] ??= <Payment>[]).add(payment);
    }
    final Map<String, String> memberNames = <String, String>{
      for (final Member member in bundle.members) member.id: member.name,
    };
    final Map<int, String> recipientByPeriod = <int, String>{
      for (final turn in bundle.turns)
        turn.periodNumber: memberNames[turn.memberId] ?? '-',
    };

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        _sectionTitle('Collection Periods'),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          headers: <String>[
            'Period',
            'Due Date',
            'Paid',
            'Total',
            'Collected',
            'Recipient',
            'Status',
          ],
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 9,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
          cellStyle: pw.TextStyle(fontSize: 8),
          cellAlignments: <int, pw.Alignment>{
            2: pw.Alignment.center,
            3: pw.Alignment.center,
            4: pw.Alignment.centerRight,
          },
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          data: periods.map((PaymentSchedule ps) {
            final List<Payment> pp =
                paymentsByPeriod[ps.periodNumber] ?? <Payment>[];
            final int paidCount = pp.where((Payment p) => p.isPaid).length;
            final double paidAmt = pp
                .where((Payment p) => p.isPaid)
                .fold<double>(0, (double s, Payment p) => s + p.amount);

            final String recipientName =
                recipientByPeriod[ps.periodNumber] ?? '-';

            final bool complete = paidCount == pp.length && pp.isNotEmpty;
            return <String>[
              'P${ps.periodNumber}',
              _fmt(ps.dueDate),
              '$paidCount',
              '${pp.length}',
              'Rs ${_money(paidAmt)}',
              recipientName,
              complete ? 'Complete' : (ps.isClosed ? 'Closed' : 'Open'),
            ];
          }).toList(),
        ),
      ],
    );
  }

  List<pw.Widget> _paymentDetailsSections(CommitteeBundle bundle) {
    final List<Payment> paid =
        bundle.payments.where((Payment p) => p.isPaid).toList()..sort(
          (Payment a, Payment b) =>
              (b.paidDate ?? b.dueDate).compareTo(a.paidDate ?? a.dueDate),
        );

    if (paid.isEmpty) return <pw.Widget>[];

    // Map memberId â†’ name for quick lookup
    final Map<String, String> memberNames = <String, String>{
      for (final Member m in bundle.members) m.id: m.name,
    };

    final List<List<String>> rows = paid
        .map((Payment p) {
          return <String>[
            memberNames[p.memberId] ?? '-',
            'P${p.periodNumber}',
            'Rs ${_money(p.amount)}',
            _methodLabel(p.method?.name),
            p.paidDate != null ? _fmt(p.paidDate!) : '-',
          ];
        })
        .toList(growable: false);

    // Keep each table bounded. A single very large table can repeatedly
    // re-layout at a page boundary in pdf's MultiPage engine and eventually
    // throw TooManyPagesException for otherwise valid committees.
    const int rowsPerTable = 40;
    final List<pw.Widget> sections = <pw.Widget>[
      _sectionTitle('Payment History'),
      pw.SizedBox(height: 8),
    ];
    for (int start = 0; start < rows.length; start += rowsPerTable) {
      final int end = (start + rowsPerTable).clamp(0, rows.length);
      sections.add(
        pw.TableHelper.fromTextArray(
          headers: const <String>[
            'Member',
            'Period',
            'Amount',
            'Method',
            'Paid On',
          ],
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            fontSize: 9,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.indigo700),
          cellStyle: pw.TextStyle(fontSize: 8),
          cellAlignments: <int, pw.Alignment>{2: pw.Alignment.centerRight},
          oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          data: rows.sublist(start, end),
        ),
      );
      if (end < rows.length) sections.add(pw.SizedBox(height: 10));
    }

    return sections;
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Helpers

  pw.Widget _sectionTitle(String title) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.indigo300, width: 1),
        ),
      ),
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 13,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.indigo700,
        ),
      ),
    );
  }

  pw.Widget _kv(String key, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              key,
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  pw.Widget _statBox(
    String label,
    String value,
    PdfColor textColor,
    PdfColor bgColor,
  ) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          color: bgColor,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: textColor.shade(0.3)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(
              label,
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€ Formatters

  String _fmt(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  String _money(double v) => NumberFormat('#,##0', 'en_US').format(v);

  String _methodLabel(String? method) {
    if (method == null || method.isEmpty) return 'Cash';
    // Match against PaymentMethod enum name
    return switch (method) {
      'cash' => 'Cash',
      'easypaisa' => 'Easypaisa',
      'jazzCash' => 'JazzCash',
      'nayaPay' => 'NayaPay',
      'sadaPay' => 'SadaPay',
      'bankTransfer' => 'Bank Transfer',
      'hbl' => 'HBL',
      'meezan' => 'Meezan',
      'ubl' => 'UBL',
      'mcb' => 'MCB',
      'askari' => 'Askari',
      'alfalah' => 'Alfalah',
      'cheque' => 'Cheque',
      _ => 'Other',
    };
  }
}

// pw.Expanded is a real widget, remove the shim
