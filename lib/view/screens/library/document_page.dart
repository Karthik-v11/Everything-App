import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:everything_app/bloc/document/document_bloc.dart';
import 'package:everything_app/core/utils/extensions.dart';
import 'package:everything_app/core/utils/responsive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// [DocumentPage] is the Document Writer's one screen (Requirement 11).
///
/// It has two modes over the same text: a raw Markdown editor and a rendered
/// preview, toggled from the app bar (Requirement 11.5). Editing writes to
/// [DocumentBloc], which auto-saves every 30 seconds (Requirement 11.2) and once
/// more when this screen is torn down, so leaving never loses the last edit.
///
/// The screen takes the document's **id**, not the document. A new document is
/// opened at a freshly minted id (see the project screen), which [DocumentBloc]
/// finds is absent and treats as a blank document filed under [projectId].
class DocumentPage extends StatefulWidget {
  const DocumentPage({required this.documentId, this.projectId, super.key});

  final String documentId;
  final String? projectId;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  late final DocumentBloc _bloc = context.read<DocumentBloc>();

  TextEditingController? _titleController;
  TextEditingController? _contentController;

  @override
  void initState() {
    super.initState();
    _bloc.add(
      LoadDocumentEvent(
        documentId: widget.documentId,
        projectId: widget.projectId,
      ),
    );
  }

  /// Bind the controllers to the loaded document exactly once. Their listeners are
  /// attached *after* the initial text is set, so seeding them does not itself mark
  /// the document dirty.
  void _bindControllers(DocumentState state) {
    if (_contentController != null) return;

    _titleController = TextEditingController(text: state.title)
      ..addListener(() {
        _bloc.add(ChangeDocumentTitleEvent(title: _titleController!.text));
      });
    _contentController = TextEditingController(text: state.content)
      ..addListener(() {
        _bloc.add(
          ChangeDocumentContentEvent(content: _contentController!.text),
        );
      });
  }

  @override
  void dispose() {
    // The last write, in case fewer than 30 seconds have passed since the last
    // keystroke. The bloc no-ops if nothing changed.
    _bloc.add(const SaveDocumentEvent());
    _titleController?.dispose();
    _contentController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DocumentBloc, DocumentState>(
      listenWhen: (previous, current) => previous.error != current.error,
      listener: (context, state) {
        if (state.error.isNotEmpty) {
          context.showSnack(state.error, isError: true);
        }
      },
      builder: (context, state) {
        if (!state.isReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        _bindControllers(state);

        return Scaffold(
          appBar: AppBar(
            title: TextField(
              controller: _titleController,
              textInputAction: TextInputAction.next,
              style: context.texts.titleMedium,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'Untitled document',
                isCollapsed: true,
              ),
            ),
            actions: [
              IconButton(
                onPressed: () =>
                    context.read<DocumentBloc>().add(const TogglePreviewEvent()),
                icon: Icon(
                  state.isPreview
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                ),
                tooltip: state.isPreview ? 'Edit' : 'Preview',
              ),
              _ExportMenu(state: state),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                _SaveStatus(state: state),
                Expanded(
                  child: state.isPreview
                      ? _Preview(content: state.content)
                      : _Editor(controller: _contentController!),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// [_SaveStatus] is the one line that says whether the work is safe: saving, saved
/// at a time, or edited since (Requirement 11.2).
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.state});

  final DocumentState state;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (state) {
      _ when state.isSaving => ('Saving…', Icons.sync_rounded),
      _ when state.isDirty => ('Unsaved changes', Icons.edit_outlined),
      _ when state.lastSavedAt != null => (
          'Saved ${state.lastSavedAt!.shortDateTime}',
          Icons.check_rounded,
        ),
      _ => ('Not saved yet', Icons.circle_outlined),
    };

    return Container(
      width: double.infinity,
      padding: responsivePadding(context).copyWith(top: 6, bottom: 6),
      color: context.colors.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(icon, size: 13, color: context.colors.onSurfaceVariant),
          const Gap(6),
          Text(label, style: context.texts.labelSmall),
        ],
      ),
    );
  }
}

/// [_Editor] is the raw Markdown surface — a monospace [TextField] that fills the
/// screen so the caret is always where the next character goes.
class _Editor extends StatelessWidget {
  const _Editor({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      expands: true,
      maxLines: null,
      minLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: context.texts.bodyMedium?.copyWith(fontFamily: 'monospace'),
      decoration: InputDecoration(
        border: InputBorder.none,
        hintText: 'Start writing in Markdown…',
        contentPadding: responsivePadding(context).copyWith(top: 12),
      ),
    );
  }
}

/// [_Preview] renders the Markdown (Requirement 11.5): headings at their level,
/// lists, checklists, code and links.
class _Preview extends StatelessWidget {
  const _Preview({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) {
      return Center(
        child: Text('Nothing to preview yet.', style: context.texts.bodySmall),
      );
    }

    return Markdown(
      data: content,
      padding: responsivePadding(context).copyWith(top: 12, bottom: 24),
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
      onTapLink: (text, href, title) => _openLink(href),
    );
  }

  Future<void> _openLink(String? href) async {
    // Preview links are a convenience, not a core path; a malformed or
    // unopenable href simply does nothing rather than surfacing an error over the
    // document.
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null || !await canLaunchUrl(uri)) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// [_ExportMenu] exports the document as Markdown, plain text or PDF via the OS
/// share sheet (Requirement 11.4).
class _ExportMenu extends StatelessWidget {
  const _ExportMenu({required this.state});

  final DocumentState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ExportFormat>(
      icon: const Icon(Icons.ios_share_rounded),
      tooltip: 'Export',
      onSelected: (format) => _export(context, format),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _ExportFormat.markdown,
          child: Text('Export as Markdown'),
        ),
        PopupMenuItem(
          value: _ExportFormat.plainText,
          child: Text('Export as plain text'),
        ),
        PopupMenuItem(
          value: _ExportFormat.pdf,
          child: Text('Export as PDF'),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, _ExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    final title = state.title.isBlank ? 'document' : state.title.trim();

    try {
      // PDF is rendered bytes handed straight to `printing`'s share, not a text
      // file — so it takes its own path rather than the `writeAsString` one below.
      if (format == _ExportFormat.pdf) {
        await Printing.sharePdf(
          bytes: await _buildPdf(title, state.content),
          filename: '${_safeFileName(title)}.pdf',
        );
        return;
      }

      final (body, extension) = switch (format) {
        _ExportFormat.markdown => (state.content, 'md'),
        _ExportFormat.plainText => (_toPlainText(state.content), 'txt'),
        _ExportFormat.pdf => throw StateError('handled above'),
      };

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/${_safeFileName(title)}.$extension');
      await file.writeAsString(body);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: title),
      );
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not export the document.')),
      );
    }
  }

  /// [_buildPdf] renders the Markdown to a paginated PDF.
  ///
  /// It is a lightweight renderer, not a second Markdown engine: headings by their
  /// `#` level, bullet and numbered lists, and everything else as a paragraph.
  /// That covers what the plain-text editor actually produces without pulling the
  /// preview's full HTML pipeline into a background PDF build.
  Future<Uint8List> _buildPdf(String title, String markdown) async {
    final document = pw.Document();
    final blocks = <pw.Widget>[];

    if (title.isNotEmpty) {
      blocks
        ..add(
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
        )
        ..add(pw.SizedBox(height: 12));
    }

    for (final line in const LineSplitter().convert(markdown)) {
      blocks.add(_pdfLine(line));
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => blocks,
      ),
    );

    return document.save();
  }

  pw.Widget _pdfLine(String line) {
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty) return pw.SizedBox(height: 8);

    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
    if (heading != null) {
      final level = heading.group(1)!.length;
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8, bottom: 4),
        child: pw.Text(
          heading.group(2)!,
          style: pw.TextStyle(
            fontSize: 20.0 - (level * 1.5),
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
    }

    final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
    if (bullet != null) {
      return pw.Bullet(text: _toPlainText(bullet.group(1)!));
    }

    final numbered = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
    if (numbered != null) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, bottom: 2),
        child: pw.Text(
          '${numbered.group(1)}. ${_toPlainText(numbered.group(2)!)}',
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(_toPlainText(trimmed)),
    );
  }

  /// [_safeFileName] keeps the shared file's name to characters every platform's
  /// file system accepts, so the export never fails on a title with a slash in it.
  String _safeFileName(String title) {
    final cleaned = title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    return cleaned.isEmpty ? 'document' : cleaned;
  }
}

enum _ExportFormat { markdown, plainText, pdf }

/// [_toPlainText] strips the Markdown decoration for a plain-text export: heading
/// hashes, emphasis and code markers, link syntax reduced to its text, and list
/// bullets left as they read. It is deliberately conservative — the point is
/// readable text, not a second Markdown parser.
String _toPlainText(String markdown) {
  return markdown
      .replaceAllMapped(
        RegExp(r'!?\[([^\]]*)\]\([^)]*\)'),
        (match) => match.group(1) ?? '',
      )
      .replaceAll(RegExp(r'`{1,3}'), '')
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s{0,3}>\s?', multiLine: true), '')
      .replaceAll(RegExp(r'(\*\*|__|\*|_|~~)'), '');
}
