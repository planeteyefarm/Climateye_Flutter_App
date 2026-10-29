import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme.dart';
import 'common.dart';
import 'live_dashboard.dart';

/// AI AQI report. Only requested when the user taps Generate/Retry, matching
/// the website (auto-fetch is disabled there).
class AqiReportCard extends StatefulWidget {
  const AqiReportCard({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.date,
  });

  final double latitude, longitude;
  final DateTime date;

  @override
  State<AqiReportCard> createState() => _AqiReportCardState();
}

class _AqiReportCardState extends State<AqiReportCard> {
  bool _loading = false;
  String? _text;
  String? _error;

  @override
  void didUpdateWidget(AqiReportCard old) {
    super.didUpdateWidget(old);
    if (old.date != widget.date) {
      _text = null;
      _error = null;
    }
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await ApiClient.instance
          .fetchAqiAnalysis(widget.latitude, widget.longitude, widget.date);
      if (mounted) setState(() => _text = t);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const LoadingBox(label: 'Generating analysis…');
    } else if (_error != null) {
      body = ErrorBox(message: _error!, onRetry: _generate);
    } else if (_text != null) {
      body = _ReportText(_text!);
    } else {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            const Text('No analysis data available',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _generate,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('Generate Analysis',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );
    }
    return LiveCard(
      title: 'AQI Analysis Report',
      titleSize: 22,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        body,
        if (_text != null && !_loading)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Regenerate'),
            ),
          ),
      ]),
    );
  }
}

/// Renders numbered headings and bullet lines from the analysis text.
class _ReportText extends StatelessWidget {
  const _ReportText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n').map((l) => l.trimRight()).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          if (line.trim().isEmpty)
            const SizedBox(height: 8)
          else if (RegExp(r'^\d+\.\s').hasMatch(line.trim()))
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 2),
              child: Text(line.trim().replaceAll('**', ''),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: AppColors.accent)),
            )
          else if (RegExp(r'^\s*[-•*]\s').hasMatch(line))
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  '),
                Expanded(
                    child: Text(line
                        .trim()
                        .replaceFirst(RegExp(r'^[-•*]\s*'), '')
                        .replaceAll('**', ''))),
              ]),
            )
          else
            Text(line.replaceAll('**', '')),
      ],
    );
  }
}
