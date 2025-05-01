library bug_report_plugin;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Plugin para reporte de bugs.
///
/// Este plugin expone el método estático [BugReportPlugin.bugReport] que
/// muestra una vista con un formulario para enviar un reporte de error.
/// El formulario permite ingresar:
///   - Comentario (único campo requerido)
///   - Adjuntar imágenes (screenshots) – se suben en forma secuencial (cola)
///   - Toggle para "¿Deseas ser contactado?" y, de ser así, se muestran campos
///     para email, teléfono y nombre.
///
/// Al enviar el formulario se realiza:
///   1. POST a https://bug-report.test/bug-report enviando el comentario y
///      datos de contacto (si se habilitó).
///      La respuesta es un JSON con { report: UUID }.
///   2. Por cada imagen adjunta se realiza un PUT a https://bug-report.test/bug-report/UUID
///      que envía la imagen.
/// El plugin incluye manejo de errores, confirmación de acciones y bloqueo
/// de salida mientras se suben archivos.
class BugReportPlugin {
  /// Método estático para mostrar la vista de reporte de bug.
  ///
  /// Se puede usar en un onPressed:
  /// ```dart
  /// onPressed: () {
  ///   BugReportPlugin.bugReport(context);
  /// }
  /// ```
  static void bugReport(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BugReportForm(),
        fullscreenDialog: true,
      ),
    );
  }
}

/// Vista con el formulario para el reporte de bug.
class BugReportForm extends StatefulWidget {
  @override
  _BugReportFormState createState() => _BugReportFormState();
}

class _BugReportFormState extends State<BugReportForm> {
  final _formKey = GlobalKey<FormState>();

  // Controladores de texto
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  // Variables de estado
  bool _contactMe = false;
  bool _isUploading = false;
  bool _cancelled = false;

  // Lista de imágenes seleccionadas (almacenadas en memoria)
  final List<Uint8List> _images = [];

  // Instancia para seleccionar imágenes.
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _commentController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Permite seleccionar una imagen usando image_picker.
  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile =
      await _picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _images.add(bytes);
        });
      }
    } catch (e) {
      _showError("Error al seleccionar imagen: $e");
    }
  }

  /// Muestra un diálogo de error con [message].
  Future<void> _showError(String message) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            child: Text("Aceptar"),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    );
  }

  /// Muestra un diálogo de confirmación con [message] y retorna true/false.
  Future<bool> _showConfirmation(String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Confirmación"),
        content: Text(message),
        actions: [
          TextButton(
            child: Text("Cancelar"),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text("Aceptar"),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// Envía el reporte de bug.
  ///
  /// Primero se envía el POST con los datos y se obtiene el UUID del reporte.
  /// Luego se suben las imágenes adjuntas de forma secuencial.
  Future<void> _submitReport() async {
    if (_commentController.text.trim().isEmpty) {
      _showError("El comentario es obligatorio.");
      return;
    }

    // Confirmación de envío
    bool confirm = await _showConfirmation(
        "¿Deseas enviar el reporte? Se utilizarán los datos ingresados para mejorar la app.");
    if (!confirm) return;

    setState(() {
      _isUploading = true;
      _cancelled = false;
    });

    try {
      // Realiza el POST para crear el reporte
      final reportId = await _createReport();
      // Sube cada imagen en forma secuencial (cola)
      for (int i = 0; i < _images.length; i++) {
        if (_cancelled) break;
        await _uploadImage(reportId, _images[i]);
      }
      if (!_cancelled) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text("Reporte enviado"),
            content: Text("El reporte se envió correctamente.\nID: $reportId"),
            actions: [
              TextButton(
                child: Text("Aceptar"),
                onPressed: () => Navigator.of(context).pop(),
              )
            ],
          ),
        );
        Navigator.of(context).pop(); // Cierra la vista de reporte
      }
    } catch (e) {
      _showError("Error al enviar el reporte: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  /// Realiza la petición POST para crear el reporte.
  ///
  /// Envía los datos (comentario y datos de contacto si corresponden)
  /// a la URL: https://bug-report.test/bug-report y retorna el UUID del reporte.
  Future<String> _createReport() async {
    final uri = Uri.parse("http://bug-report.test/api/bug-reports");
    final httpClient = HttpClient();
    final request = await httpClient.postUrl(uri);

    request.headers.set(HttpHeaders.contentTypeHeader, "application/json");

    final Map<String, dynamic> payload = {
      "comentario": _commentController.text.trim(),
    };
    if (_contactMe) {
      payload["email"] = _emailController.text.trim();
      payload["telefono"] = _phoneController.text.trim();
      payload["nombre"] = _nameController.text.trim();
    }
    request.add(utf8.encode(json.encode(payload)));

    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw Exception("Error en POST: ${response.statusCode}");
    }
    final data = json.decode(responseBody);
    httpClient.close();
    if (data["report"] == null) {
      throw Exception("Respuesta inválida del servidor");
    }
    return data["report"];
  }

  /// Realiza la petición PUT para subir una imagen al reporte.
  ///
  /// Se envía a la URL https://bug-report.test/bug-report/{reportId}
  /// con el contenido de la imagen en formato JPEG.
  Future<void> _uploadImage(String reportId, Uint8List imageBytes) async {
    final uri = Uri.parse("http://bug-report.test/api/bug-reports/$reportId");
    final httpClient = HttpClient();
    final request = await httpClient.putUrl(uri);

    // Se asume que la imagen es JPEG; ajustar según sea necesario
    request.headers.set(HttpHeaders.contentTypeHeader, "image/jpeg");
    request.add(imageBytes);

    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception("Error al subir imagen. Código: ${response.statusCode}");
    }
    httpClient.close();
  }

  /// Muestra una alerta para confirmar la cancelación del reporte.
  Future<bool> _confirmCancel() async {
    return await _showConfirmation(
        "¿Seguro que deseas cancelar el reporte? Se perderán los datos ingresados.");
  }

  @override
  Widget build(BuildContext context) {
    // Se utiliza WillPopScope para bloquear la salida mientras se suben archivos.
    return WillPopScope(
      onWillPop: () async {
        if (_isUploading) {
          // Si se están subiendo archivos, se bloquea la salida.
          return false;
        }
        // Si no se está subiendo, se pide confirmación para cancelar.
        return await _confirmCancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text("Reportar un Bug"),
          actions: [
            IconButton(
              icon: Icon(Icons.close),
              onPressed: _isUploading
                  ? null
                  : () async {
                if (await _confirmCancel()) {
                  Navigator.of(context).pop();
                }
              },
            )
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Información de la ventana
                Text(
                  "Se está reportando un error con fines de mejorar la calidad de la app.",
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
                // Campo de comentario (requerido)
                TextFormField(
                  controller: _commentController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: "Comentario *",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "El comentario es obligatorio.";
                    }
                    return null;
                  },
                ),
                SizedBox(height: 16),
                // Toggle para "Deseas ser contactado"
                SwitchListTile(
                  title: Text("¿Deseas ser contactado?"),
                  value: _contactMe,
                  onChanged: (val) {
                    setState(() {
                      _contactMe = val;
                    });
                  },
                ),
                // Campos de contacto (solo si _contactMe es true)
                if (_contactMe) ...[
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: "Email",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: "Teléfono",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: "Nombre",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 16),
                ],
                // Sección para adjuntar imágenes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Adjuntar imágenes:"),
                    TextButton.icon(
                      onPressed: _isUploading ? null : _pickImage,
                      icon: Icon(Icons.add_a_photo),
                      label: Text("Agregar imagen"),
                    ),
                  ],
                ),
                // Vista previa de imágenes seleccionadas
                _images.isEmpty
                    ? Text("No se han agregado imágenes.")
                    : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _images
                      .map((bytes) => Stack(
                    children: [
                      Image.memory(
                        bytes,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: GestureDetector(
                          onTap: _isUploading
                              ? null
                              : () {
                            setState(() {
                              _images.remove(bytes);
                            });
                          },
                          child: Container(
                            color: Colors.black54,
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      )
                    ],
                  ))
                      .toList(),
                ),
                SizedBox(height: 24),
                // Botón de envío
                ElevatedButton(
                  onPressed: _isUploading ? null : _submitReport,
                  child: Text("Enviar reporte"),
                ),
                if (_isUploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 8),
                        Text("Subiendo datos, por favor espere..."),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
