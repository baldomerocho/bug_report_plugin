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
///   1. POST a la URL configurada enviando el comentario y
///      datos de contacto (si se habilitó).
///      La respuesta es un JSON con { id: UUID }.
///   2. Por cada imagen adjunta se realiza un PUT a la URL configurada con el UUID
///      que envía la imagen.
/// El plugin incluye manejo de errores, confirmación de acciones y bloqueo
/// de salida mientras se suben archivos.
class BugReportPlugin {
  /// Configuración del plugin
  static String? _host;
  static String? _collection;
  static String? _apiKey;
  static String? _package;

  /// Configura el plugin con los parámetros necesarios
  ///
  /// @param host URL base del servidor Pocketbase
  /// @param collection Nombre de la colección en Pocketbase
  /// @param apiKey API key para autenticación
  /// @param package Identificador del paquete
  static void configure({
    required String host,
    required String collection,
    required String apiKey,
    required String package,
  }) {
    _host = host;
    _collection = collection;
    _apiKey = apiKey;
    _package = package;
  }

  /// Método estático para mostrar la vista de reporte de bug.
  ///
  /// Se puede usar en un onPressed:
  /// ```dart
  /// onPressed: () {
  ///   BugReportPlugin.bugReport(context);
  /// }
  /// ```
  static void bugReport(BuildContext context) {
    // Verificar que el plugin esté configurado
    if (_host == null || _collection == null || _apiKey == null || _package == null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Error de configuración"),
          content: const Text("El plugin no ha sido configurado correctamente. Utilice BugReportPlugin.configure() antes de llamar a bugReport()."),
          actions: [
            TextButton(
              child: const Text("Aceptar"),
              onPressed: () => Navigator.of(context).pop(),
            )
          ],
        ),
      );
      return;
    }
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const BugReportForm(),
        fullscreenDialog: true,
      ),
    );
  }
}

/// Vista con el formulario para el reporte de bug.
class BugReportForm extends StatefulWidget {
  const BugReportForm({super.key});

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
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("Aceptar"),
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
        title: const Text("Confirmación"),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("Cancelar"),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: const Text("Aceptar"),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// Envía el reporte de bug.
  ///
  /// Se envía el POST con los datos y las imágenes en una sola petición
  /// utilizando multipart/form-data para compatibilidad con Pocketbase.
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
      FocusScope.of(context).unfocus();
      _isUploading = true;
      _cancelled = false;
    });

    try {
      // Realiza el POST para crear el reporte con las imágenes
      final reportId = await _createReportWithImages();
      
      if (!_cancelled) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text("Reporte enviado"),
            content: Text("El reporte se envió correctamente.\nID: $reportId"),
            actions: [
              TextButton(
                child: const Text("Aceptar"),
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

  /// Realiza la petición POST para crear el reporte con imágenes.
  ///
  /// Envía los datos (comentario, datos de contacto e imágenes) en una sola petición
  /// a la URL configurada utilizando multipart/form-data para compatibilidad con Pocketbase.
  Future<String> _createReportWithImages() async {
    // Verificar que el plugin esté configurado
    if (BugReportPlugin._host == null || 
        BugReportPlugin._collection == null || 
        BugReportPlugin._apiKey == null || 
        BugReportPlugin._package == null) {
      throw Exception("El plugin no está configurado correctamente");
    }
    
    final uri = Uri.parse("${BugReportPlugin._host}/api/collections/${BugReportPlugin._collection}/records");
    
    // Crear un límite único para el formulario multipart
    final boundary = '----${DateTime.now().millisecondsSinceEpoch}----';
    
    // Crear el cuerpo de la solicitud manualmente
    final bodyData = <int>[];
    
    // Función para agregar un campo de texto al cuerpo
    void addTextPart(String name, String value) {
      bodyData.addAll(utf8.encode('--$boundary\r\n'));
      bodyData.addAll(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
      bodyData.addAll(utf8.encode('$value\r\n'));
    }
    
    // Función para agregar una imagen al cuerpo
    void addImagePart(String name, Uint8List bytes, int index) {
      bodyData.addAll(utf8.encode('--$boundary\r\n'));
      bodyData.addAll(utf8.encode('Content-Disposition: form-data; name="$name"; filename="image_$index.jpg"\r\n'));
      bodyData.addAll(utf8.encode('Content-Type: image/jpeg\r\n\r\n'));
      bodyData.addAll(bytes);
      bodyData.addAll(utf8.encode('\r\n'));
    }
    
    // Agregar campos de texto
    addTextPart('email', _contactMe ? _emailController.text.trim() : "test");
    addTextPart('telefono', _contactMe ? _phoneController.text.trim() : "test");
    addTextPart('nombre', _contactMe ? _nameController.text.trim() : "test");
    addTextPart('package', BugReportPlugin._package!);
    addTextPart('comentario', _commentController.text.trim());
    
    // Agregar imágenes si existen
    for (int i = 0; i < _images.length; i++) {
      if (_cancelled) break;
      addImagePart('imagenes', _images[i], i);
    }
    
    // Finalizar el cuerpo multipart
    bodyData.addAll(utf8.encode('--$boundary--\r\n'));
    
    // Crear un cliente HTTP y una solicitud
    final httpClient = HttpClient();
    final request = await httpClient.postUrl(uri);
    
    // Establecer encabezados
    request.headers.set("apikey", BugReportPlugin._apiKey!);
    request.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
    request.contentLength = bodyData.length;
    
    // Enviar los datos
    request.add(Uint8List.fromList(bodyData));
    
    // Enviar la solicitud y procesar la respuesta
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception("Error en POST: ${response.statusCode} - $responseBody");
    }
    
    final data = json.decode(responseBody);
    httpClient.close();
    
    if (data["id"] == null) {
      throw Exception("Respuesta inválida del servidor");
    }
    
    return data["id"];
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
          title: const Text("Reportar un Bug"),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
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
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Información de la ventana
                const Text(
                  "Se está reportando un error con fines de mejorar la calidad de la app.",
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                // Campo de comentario (requerido)
                TextFormField(
                  controller: _commentController,
                  maxLines: null,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: "Comentario *",
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return "El comentario es obligatorio.";
                    }
                    return null;
                  },
                  onTapOutside: (event) {
                    FocusScope.of(context).unfocus();
                  },
                ),
                const SizedBox(height: 16),
                // Toggle para "Deseas ser contactado"
                SwitchListTile(
                  title: const Text("¿Deseas ser contactado?"),
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
                    decoration: const InputDecoration(
                      labelText: "Email",
                      border: OutlineInputBorder(),
                    ),
                    onTapOutside: (event) {
                    FocusScope.of(context).unfocus();
                  },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(
                      labelText: "Teléfono",
                      border: OutlineInputBorder(),
                    ),
                    onTapOutside: (event) {
                    FocusScope.of(context).unfocus();
                  },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: "Nombre",
                      border: OutlineInputBorder(),
                    ),
                    onTapOutside: (event) {
                    FocusScope.of(context).unfocus();
                  },
                  ),
                  const SizedBox(height: 16),
                ],
                // Sección para adjuntar imágenes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Adjuntar imágenes:"),
                    TextButton.icon(
                      onPressed: _isUploading ? null : _pickImage,
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text("Agregar imagen"),
                    ),
                  ],
                ),
                // Vista previa de imágenes seleccionadas
                _images.isEmpty
                    ? const Text("No se han agregado imágenes.")
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
                            child: const Icon(
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
                const SizedBox(height: 24),
                // Botón de envío
                ElevatedButton(
                  onPressed: _isUploading ? null : _submitReport,
                  child: const Text("Enviar reporte"),
                ),
                if (_isUploading)
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0),
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
