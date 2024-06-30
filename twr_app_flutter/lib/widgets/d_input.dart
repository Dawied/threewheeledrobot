import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/screen_model.dart';

class DInput extends StatefulWidget {
  final String fieldKey;
  final String label;

  const DInput({super.key, required this.fieldKey, required this.label});

  @override
  DInputState createState() => DInputState();
}

class DInputState extends State<DInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    // Initialize the controller with the initial value
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final screenModel = context.read<ScreenModel>();
      _controller.text = screenModel.getValue(widget.fieldKey);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScreenModel>(
      builder: (context, screenModel, child) {
        // Update the controller's text if the value changes
        if (_controller.text != screenModel.getValue(widget.fieldKey)) {
          _controller.text = screenModel.getValue(widget.fieldKey);
        }
        return TextField(
          controller: _controller,
          onChanged: (value) {
            screenModel.updateValue(widget.fieldKey, value);
          },
          decoration: InputDecoration(
            labelText: widget.label,
          ),
        );
      },
    );
  }
}
