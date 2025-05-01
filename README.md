# Bug Report Plugin

A Flutter plugin that provides an easy-to-use interface for collecting and submitting bug reports to a Pocketbase backend. This plugin allows users to submit detailed bug reports with optional contact information and image attachments.

## Features

- **Simple Integration**: Easy to add to any Flutter application
- **Customizable Configuration**: Configure your Pocketbase backend details
- **Contact Information Collection**: Optional user contact details (email, phone, name)
- **Image Attachments**: Support for multiple image attachments
- **Professional UI**: Clean, user-friendly interface with loading states
- **Error Handling**: Comprehensive error handling and user feedback

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  bug_report_plugin: ^0.0.2
```

Then run:

```bash
flutter pub get
```

## Setup

### Backend Requirements

This plugin requires a Pocketbase backend with a collection for storing bug reports. The collection should have the following fields:

- `email` (text)
- `telefono` (text)
- `nombre` (text)
- `package` (text)
- `comentario` (text)
- `imagenes` (file[])

### Plugin Configuration

Before using the plugin, you need to configure it with your Pocketbase details:

```dart
import 'package:bug_report_plugin/bug_report_plugin.dart';

// Configure the plugin (typically in your app initialization)
BugReportPlugin.configure(
  host: "https://your-pocketbase-server.com",
  collection: "bug_reports",
  apiKey: "your-api-key",
  package: "your-package-identifier"
);
```

## Usage

Once configured, you can show the bug report form by calling:

```dart
// Show the bug report form
BugReportPlugin.bugReport(context);
```

This will open a full-screen dialog with the bug report form. Users can:

1. Enter a comment describing the issue (required)
2. Toggle whether they want to be contacted
3. Provide contact information if they chose to be contacted
4. Add multiple images as attachments
5. Submit the report

## Example

```dart
import 'package:flutter/material.dart';
import 'package:bug_report_plugin/bug_report_plugin.dart';

void main() {
  // Configure the plugin
  BugReportPlugin.configure(
    host: "https://your-pocketbase-server.com",
    collection: "bug_reports",
    apiKey: "your-api-key",
    package: "your-package-identifier"
  );
  
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text('Bug Report Example'),
        ),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              BugReportPlugin.bugReport(context);
            },
            child: Text('Report a Bug'),
          ),
        ),
      ),
    );
  }
}
```

## Form Flow

1. User fills out the bug report form
2. User submits the form
3. Form is hidden and a loading screen is displayed
4. If submission is successful, a success dialog is shown
5. If an error occurs, the form reappears with an error message

## Customization

Currently, the plugin provides a standard UI that follows Material Design guidelines. Future versions may include customization options for colors, text, and other UI elements.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
