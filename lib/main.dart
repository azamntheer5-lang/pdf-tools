import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf_render/pdf_render.dart' as pdf_render;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(PDFApp());

class PDFApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(home: HomePage());
}

class HomePage extends StatelessWidget {
  Future<void> _openEditor(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => EditorScreen(pdfPath: result.files.single.path!),
      ));
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('PDF Editor')),
    body: Center(child: ElevatedButton.icon(
      icon: Icon(Icons.picture_as_pdf),
      label: Text('اختر ملف PDF'),
      onPressed: () => _openEditor(context),
    )),
  );
}

// --- نموذج المربع ---
class TextBoxModel {
  final String id;
  String text;
  double x, y, width, height;
  Color textColor, bgColor;
  String fontFamily;
  double fontSize;
  TextBoxModel({
    required this.id, this.text = 'نص', this.x = 100, this.y = 100,
    this.width = 200, this.height = 40, this.textColor = Colors.black,
    this.bgColor = Colors.transparent, this.fontFamily = 'Helvetica', this.fontSize = 16,
  });
}

// --- شاشة التحرير ---
class EditorScreen extends StatefulWidget {
  final String pdfPath;
  const EditorScreen({required this.pdfPath});
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late pdf_render.PdfDocument _pdfDoc;
  int _currentPage = 0, _totalPages = 0;
  Uint8List? _pageImage;
  double _pageWidth = 0, _pageHeight = 0;
  final Map<int, List<TextBoxModel>> _annotations = {};
  String? _selectedId;
  bool _showProps = false;

  @override
  void initState() {
    super.initState();
    _initDoc();
  }

  Future<void> _initDoc() async {
    final bytes = File(widget.pdfPath).readAsBytesSync();
    _pdfDoc = await pdf_render.PdfDocument.openData(bytes);
    _totalPages = _pdfDoc.pageCount;
    _loadPage(0);
  }

  Future<void> _loadPage(int idx) async {
    if (idx < 0 || idx >= _totalPages) return;
    final page = await _pdfDoc.getPage(idx + 1);
    _pageWidth = page.size.width; _pageHeight = page.size.height;
    final img = await page.render(width: _pageWidth.toInt(), height: _pageHeight.toInt());
    final bytes = await img.bytes;
    setState(() { _pageImage = Uint8List.fromList(bytes); _currentPage = idx; _selectedId = null; });
  }

  void _addTextBox() {
    final box = TextBoxModel(id: Uuid().v4(), x: _pageWidth/2-100, y: _pageHeight/2-20);
    setState(() { _annotations.putIfAbsent(_currentPage, () => []).add(box); _selectedId = box.id; _showProps = true; });
  }

  void _deleteSelected() {
    if (_selectedId == null) return;
    setState(() { _annotations[_currentPage]!.removeWhere((b) => b.id == _selectedId); _selectedId = null; _showProps = false; });
  }

  Future<void> _savePdf() async {
    final originalBytes = File(widget.pdfPath).readAsBytesSync();
    final doc = PdfDocument(inputBytes: originalBytes);
    for (int p = 0; p < _totalPages; p++) {
      final page = doc.pages[p];
      final graphics = page.graphics;
      final boxes = _annotations[p];
      if (boxes == null) continue;
      for (final box in boxes) {
        if (box.bgColor != Colors.transparent) {
          graphics.drawRectangle(
            brush: PdfSolidBrush(PdfColor(box.bgColor.red, box.bgColor.green, box.bgColor.blue)),
            bounds: Rect.fromLTWH(box.x, box.y, box.width, box.height),
          );
        }
        PdfStandardFont font;
        switch (box.fontFamily) {
          case 'Times-Roman': font = PdfStandardFont(PdfFontFamily.timesRoman, box.fontSize); break;
          case 'Courier': font = PdfStandardFont(PdfFontFamily.courier, box.fontSize); break;
          default: font = PdfStandardFont(PdfFontFamily.helvetica, box.fontSize);
        }
        graphics.drawString(
          box.text, font,
          brush: PdfSolidBrush(PdfColor(box.textColor.red, box.textColor.green, box.textColor.blue)),
          bounds: Rect.fromLTWH(box.x, box.y, box.width, box.height),
        );
      }
    }
    final List<int> savedBytes = doc.save();
    doc.dispose();
    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
    File(outPath).writeAsBytesSync(savedBytes);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الحفظ: $outPath')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('تحرير PDF'), actions: [
        IconButton(icon: Icon(Icons.add_box), onPressed: _addTextBox),
        IconButton(icon: Icon(Icons.save), onPressed: _savePdf),
      ]),
      body: _pageImage == null ? Center(child: CircularProgressIndicator()) : Column(children: [
        Expanded(child: InteractiveViewer(child: SizedBox(width: _pageWidth, height: _pageHeight, child: Stack(children: [
          Image.memory(_pageImage!, fit: BoxFit.fill),
          ...?_annotations[_currentPage]?.map((box) {
            bool selected = box.id == _selectedId;
            return Positioned(left: box.x, top: box.y, width: box.width, height: box.height,
              child: GestureDetector(
                onTap: () => setState(() { _selectedId = box.id; _showProps = true; }),
                onPanUpdate: (d) => setState(() { box.x += d.delta.dx; box.y += d.delta.dy; }),
                child: Container(
                  decoration: BoxDecoration(color: box.bgColor, border: selected ? Border.all(color: Colors.blue, width: 2) : null),
                  alignment: Alignment.center,
                  child: Text(box.text, style: TextStyle(color: box.textColor, fontFamily: box.fontFamily == 'Helvetica' ? null : box.fontFamily, fontSize: box.fontSize)),
                ),
              ),
            );
          }).toList(),
        ])))),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: Icon(Icons.chevron_left), onPressed: _currentPage > 0 ? () => _loadPage(_currentPage-1) : null),
          Text('${_currentPage+1}/$_totalPages'),
          IconButton(icon: Icon(Icons.chevron_right), onPressed: _currentPage < _totalPages-1 ? () => _loadPage(_currentPage+1) : null),
        ]),
      ]),
      bottomSheet: (_selectedId != null && _showProps) ? _propertiesPanel() : null,
    );
  }

  Widget _propertiesPanel() {
    final box = _annotations[_currentPage]!.firstWhere((b) => b.id == _selectedId);
    return Container(color: Colors.grey[100], padding: EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [
      TextField(
        controller: TextEditingController(text: box.text)..selection = TextSelection.collapsed(offset: box.text.length),
        decoration: InputDecoration(labelText: 'النص'),
        onChanged: (v) => setState(() => box.text = v),
      ),
      Row(children: [
        Text('الحجم:'), Expanded(child: Slider(value: box.fontSize, min: 6, max: 72, onChanged: (v) => setState(() => box.fontSize = v))),
        Text('${box.fontSize.toInt()}'),
      ]),
      Row(children: [
        Text('الخط:'),
        DropdownButton<String>(value: box.fontFamily, items: ['Helvetica','Times-Roman','Courier'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
          onChanged: (v) => setState(() => box.fontFamily = v!)),
        Spacer(),
        IconButton(icon: Icon(Icons.format_color_text, color: box.textColor), onPressed: () => _pickColor(true)),
        IconButton(icon: Icon(Icons.format_color_fill, color: box.bgColor), onPressed: () => _pickColor(false)),
        IconButton(icon: Icon(Icons.delete), onPressed: _deleteSelected),
      ]),
      TextButton(onPressed: () => setState(() => _showProps = false), child: Text('إغلاق')),
    ]));
  }

  Future<void> _pickColor(bool isText) async {
    final box = _annotations[_currentPage]!.firstWhere((b) => b.id == _selectedId);
    Color? picked = await showDialog<Color>(context: context, builder: (_) => AlertDialog(title: Text('اختر لون'), content: Wrap(spacing: 10, children: [
      Colors.black, Colors.white, Colors.red, Colors.green, Colors.blue, Colors.yellow, Colors.orange, Colors.purple, Colors.transparent
    ].map((c) => GestureDetector(onTap: () => Navigator.pop(context, c), child: Container(width: 40, height: 40, decoration: BoxDecoration(color: c, border: Border.all(color: Colors.grey))))).toList())));
    if (picked != null) setState(() { if (isText) box.textColor = picked; else box.bgColor = picked; });
  }

  @override
  void dispose() { _pdfDoc.dispose(); super.dispose(); }
}
