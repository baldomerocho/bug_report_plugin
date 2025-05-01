library bug_report_plugin;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// A Flutter plugin for reporting bugs with image attachments.
///
/// This plugin provides a static method [BugReportPlugin.bugReport] that
/// displays a view with a form to submit an error report.
/// The form allows users to:
///   - Add a comment (only required field)
///   - Attach images (screenshots) - uploaded sequentially
///   - Toggle "Would you like to be contacted?" and, if enabled, fields for
///     email, phone, and name are displayed.
///
/// When submitting the form:
///   1. A POST request is made to the configured URL sending the comment and
///      contact information (if enabled) along with any attached images.
///      The response is a JSON with { id: UUID }.
/// The plugin includes error handling, action confirmation, and prevents
/// exit while files are being uploaded.
class BugReportPlugin {
  /// Plugin configuration
  static String? _host;
  static String? _collection;
  static String? _apiKey;
  static String? _package;
  
  /// Text dictionary for customizing UI text elements
  static Map<String, String> _textDictionary = defaultTextDictionary;
  
  /// Default text dictionary with English text
  static const Map<String, String> defaultTextDictionary = {
    // Dialog titles
    'configuration_error_title': 'Configuration Error',
    'error_title': 'Error',
    'confirmation_title': 'Confirmation',
    'report_sent_title': 'Report Sent',
    
    // Dialog messages
    'configuration_error_message': 'The plugin has not been properly configured. Use BugReportPlugin.configure() before calling bugReport().',
    'report_sent_message': 'The report was sent successfully.',
    'cancel_confirmation_message': 'Are you sure you want to cancel the report? All entered data will be lost.',
    'submit_confirmation_message': 'Do you want to send the report? The entered data will be used to improve the app.',
    
    // Button labels
    'ok_button': 'OK',
    'cancel_button': 'Cancel',
    'submit_button': 'Submit report',
    'add_image_button': 'Add image',
    
    // Form labels
    'app_bar_title': 'Report a Bug',
    'form_intro': 'You are reporting an error to help improve the quality of the app.',
    'comment_label': 'Comment *',
    'comment_validation': 'Comment is required.',
    'contact_toggle': 'Would you like to be contacted?',
    'email_label': 'Email',
    'phone_label': 'Phone',
    'name_label': 'Name',
    'attach_images_label': 'Attach images:',
    'no_images_label': 'No images have been added.',
    
    // Loading state
    'sending_report': 'Sending report...',
    'please_wait': 'Please wait a moment',
  };

  /// Configures the plugin with the necessary parameters
  ///
  /// @param host Base URL of the Pocketbase server
  /// @param collection Name of the collection in Pocketbase
  /// @param apiKey API key for authentication
  /// @param package Package identifier
  /// @param textDictionary Optional dictionary to customize UI text elements
  static void configure({
    required String host,
    required String collection,
    required String apiKey,
    required String package,
    Map<String, String>? textDictionary,
  }) {
    _host = host;
    _collection = collection;
    _apiKey = apiKey;
    _package = package;
    
    // If custom text dictionary is provided, merge it with the default
    if (textDictionary != null) {
      _textDictionary = Map.from(defaultTextDictionary)..addAll(textDictionary);
    } else {
      _textDictionary = Map.from(defaultTextDictionary);
    }
  }

  /// Gets a text value from the dictionary or returns the default if not found
  static String getText(String key) {
    return _textDictionary[key] ?? defaultTextDictionary[key] ?? key;
  }

  /// Static method to display the bug report view.
  ///
  /// Can be used in an onPressed callback:
  /// ```dart
  /// onPressed: () {
  ///   BugReportPlugin.bugReport(context);
  /// }
  /// ```
  static void bugReport(BuildContext context) {
    // Verify that the plugin is configured
    if (_host == null || _collection == null || _apiKey == null || _package == null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(getText('configuration_error_title')),
          content: Text(getText('configuration_error_message')),
          actions: [
            TextButton(
              child: Text(getText('ok_button')),
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

/// View with the bug report form.
class BugReportForm extends StatefulWidget {
  const BugReportForm({super.key});

  @override
  _BugReportFormState createState() => _BugReportFormState();
}

class _BugReportFormState extends State<BugReportForm> {
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  // State variables
  bool _contactMe = false;
  bool _isUploading = false;
  bool _cancelled = false;
  bool _formSubmitted = false; // To track if the form has been submitted

  // List of selected images (stored in memory)
  final List<Uint8List> _images = [];

  // Instance to select images
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Prevent the comment field from automatically getting focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).unfocus();
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// Allows selecting an image using image_picker.
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
      _showError("Error selecting image: $e");
    }
  }

  /// Shows an error dialog with [message].
  Future<void> _showError(String message) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(BugReportPlugin.getText('error_title')),
        content: Text(message),
        actions: [
          TextButton(
            child: Text(BugReportPlugin.getText('ok_button')),
            onPressed: () => Navigator.of(context).pop(),
          )
        ],
      ),
    );
  }

  /// Shows a confirmation dialog with [message] and returns true/false.
  Future<bool> _showConfirmation(String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(BugReportPlugin.getText('confirmation_title')),
        content: Text(message),
        actions: [
          TextButton(
            child: Text(BugReportPlugin.getText('cancel_button')),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          TextButton(
            child: Text(BugReportPlugin.getText('ok_button')),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// Submits the bug report.
  ///
  /// Sends a POST request with the data and images in a single request
  /// using multipart/form-data for Pocketbase compatibility.
  Future<void> _submitReport() async {
    // Ensure the keyboard is closed before continuing
    FocusScope.of(context).unfocus();
    
    if (_commentController.text.trim().isEmpty) {
      _showError(BugReportPlugin.getText('comment_validation'));
      return;
    }

    // Submission confirmation
    bool confirm = await _showConfirmation(
        BugReportPlugin.getText('submit_confirmation_message'));
    if (!confirm) return;

    // Mark the form as submitted to prevent the keyboard from showing
    setState(() {
      _formSubmitted = true;
    });
    
    // Wait for the keyboard to finish closing before showing the loader
    await Future.delayed(const Duration(milliseconds: 300));
    
    setState(() {
      _isUploading = true;
      _cancelled = false;
    });

    try {
      // Perform the POST to create the report with images
      final reportId = await _createReportWithImages();
      
      if (!_cancelled) {
        // We don't hide the loader here, as the success dialog will be shown on top
        
        // Show the success dialog
        await showDialog(
          context: context,
          barrierDismissible: false, // Prevent closing by tapping outside
          builder: (_) => AlertDialog(
            title: Text(BugReportPlugin.getText('report_sent_title')),
            content: Text("${BugReportPlugin.getText('report_sent_message')}\nID: $reportId"),
            actions: [
              TextButton(
                child: Text(BugReportPlugin.getText('ok_button')),
                onPressed: () {
                  Navigator.of(context).pop(); // Close the dialog
                  Navigator.of(context).pop(); // Close the report view
                },
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _formSubmitted = false; // Allow editing the form again in case of error
        });
        _showError("Error sending report: $e");
      }
    }
  }

  /// Performs the POST request to create the report with images.
  ///
  /// Sends the data (comment, contact information, and images) in a single request
  /// to the configured URL using multipart/form-data for Pocketbase compatibility.
  Future<String> _createReportWithImages() async {
    // Verify that the plugin is configured
    if (BugReportPlugin._host == null || 
        BugReportPlugin._collection == null || 
        BugReportPlugin._apiKey == null || 
        BugReportPlugin._package == null) {
      throw Exception("The plugin is not properly configured");
    }
    
    final uri = Uri.parse("${BugReportPlugin._host}/api/collections/${BugReportPlugin._collection}/records");
    
    // Create a unique boundary for the multipart form
    final boundary = '----${DateTime.now().millisecondsSinceEpoch}----';
    
    // Create the request body manually
    final bodyData = <int>[];
    
    // Function to add a text field to the body
    void addTextPart(String name, String value) {
      bodyData.addAll(utf8.encode('--$boundary\r\n'));
      bodyData.addAll(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
      bodyData.addAll(utf8.encode('$value\r\n'));
    }
    
    // Function to add an image to the body
    void addImagePart(String name, Uint8List bytes, int index) {
      bodyData.addAll(utf8.encode('--$boundary\r\n'));
      bodyData.addAll(utf8.encode('Content-Disposition: form-data; name="$name"; filename="image_$index.jpg"\r\n'));
      bodyData.addAll(utf8.encode('Content-Type: image/jpeg\r\n\r\n'));
      bodyData.addAll(bytes);
      bodyData.addAll(utf8.encode('\r\n'));
    }
    
    // Add text fields
    addTextPart('email', _contactMe ? _emailController.text.trim() : "test");
    addTextPart('telefono', _contactMe ? _phoneController.text.trim() : "test");
    addTextPart('nombre', _contactMe ? _nameController.text.trim() : "test");
    addTextPart('package', BugReportPlugin._package!);
    addTextPart('comentario', _commentController.text.trim());
    
    // Add images if they exist
    for (int i = 0; i < _images.length; i++) {
      if (_cancelled) break;
      addImagePart('imagenes', _images[i], i);
    }
    
    // Finalize the multipart body
    bodyData.addAll(utf8.encode('--$boundary--\r\n'));
    
    // Create an HTTP client and a request
    final httpClient = HttpClient();
    final request = await httpClient.postUrl(uri);
    
    // Set headers
    request.headers.set("apikey", BugReportPlugin._apiKey!);
    request.headers.set(HttpHeaders.contentTypeHeader, 'multipart/form-data; boundary=$boundary');
    request.contentLength = bodyData.length;
    
    // Send the data
    request.add(Uint8List.fromList(bodyData));
    
    // Send the request and process the response
    final response = await request.close();
    final responseBody = await response.transform(utf8.decoder).join();
    
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception("Error in POST: ${response.statusCode} - $responseBody");
    }
    
    final data = json.decode(responseBody);
    httpClient.close();
    
    if (data["id"] == null) {
      throw Exception("Invalid server response");
    }
    
    return data["id"];
  }

  /// Shows an alert to confirm cancellation of the report.
  Future<bool> _confirmCancel() async {
    return await _showConfirmation(
        BugReportPlugin.getText('cancel_confirmation_message'));
  }

  @override
  Widget build(BuildContext context) {
    // WillPopScope is used to block exit while files are being uploaded.
    return WillPopScope(
      onWillPop: () async {
        if (_isUploading) {
          // If files are being uploaded, exit is blocked.
          return false;
        }
        // If not uploading, ask for confirmation to cancel.
        return await _confirmCancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(BugReportPlugin.getText('app_bar_title')),
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
        body: GestureDetector(
          // Close the keyboard when tapping outside any text field
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              // Form (visible only if not uploading)
              Visibility(
                visible: !_isUploading,
                maintainState: true,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Window information
                        Text(
                          BugReportPlugin.getText('form_intro'),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        // Comment field (required)
                        TextFormField(
                          controller: _commentController,
                          maxLines: null,
                          minLines: 1,
                          autofocus: false, // Prevent automatic focus
                          readOnly: _formSubmitted, // Disable editing if the form has been submitted
                          decoration: InputDecoration(
                            labelText: BugReportPlugin.getText('comment_label'),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return BugReportPlugin.getText('comment_validation');
                            }
                            return null;
                          },
                          onTapOutside: (event) {
                            FocusScope.of(context).unfocus();
                          },
                        ),
                        const SizedBox(height: 16),
                        // Toggle for "Would you like to be contacted?"
                        SwitchListTile(
                          title: Text(BugReportPlugin.getText('contact_toggle')),
                          value: _contactMe,
                          onChanged: (val) {
                            setState(() {
                              _contactMe = val;
                            });
                          },
                        ),
                        // Contact fields (only if _contactMe is true)
                        if (_contactMe) ...[
                          TextFormField(
                            controller: _emailController,
                            readOnly: _formSubmitted, // Disable editing if the form has been submitted
                            decoration: InputDecoration(
                              labelText: BugReportPlugin.getText('email_label'),
                              border: const OutlineInputBorder(),
                            ),
                            onTapOutside: (event) {
                              FocusScope.of(context).unfocus();
                            },
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _phoneController,
                            readOnly: _formSubmitted, // Disable editing if the form has been submitted
                            decoration: InputDecoration(
                              labelText: BugReportPlugin.getText('phone_label'),
                              border: const OutlineInputBorder(),
                            ),
                            onTapOutside: (event) {
                              FocusScope.of(context).unfocus();
                            },
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameController,
                            readOnly: _formSubmitted, // Disable editing if the form has been submitted
                            decoration: InputDecoration(
                              labelText: BugReportPlugin.getText('name_label'),
                              border: const OutlineInputBorder(),
                            ),
                            onTapOutside: (event) {
                              FocusScope.of(context).unfocus();
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Section for attaching images
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(BugReportPlugin.getText('attach_images_label')),
                            TextButton.icon(
                              onPressed: _isUploading ? null : _pickImage,
                              icon: const Icon(Icons.add_a_photo),
                              label: Text(BugReportPlugin.getText('add_image_button')),
                            ),
                          ],
                        ),
                        // Preview of selected images
                        _images.isEmpty
                            ? Text(BugReportPlugin.getText('no_images_label'))
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
                        // Submit button
                        ElevatedButton(
                          onPressed: _isUploading ? null : _submitReport,
                          child: Text(BugReportPlugin.getText('submit_button')),
                        ),
                        // Additional space to prevent the button from being hidden by the loader
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ),
              
              // Loading screen (visible only during submission)
              if (_isUploading)
                Container(
                  color: Colors.white,
                  width: double.infinity,
                  height: double.infinity,
                  child: Center(
                    child: Card(
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              BugReportPlugin.getText('sending_report'),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(BugReportPlugin.getText('please_wait')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
