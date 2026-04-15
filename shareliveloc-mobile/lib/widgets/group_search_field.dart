import 'dart:async';
import 'package:flutter/material.dart';
import '../models/group.dart';
import '../services/api_service.dart';

class GroupSearchField extends StatefulWidget {
  final Function(Group) onSelected;
  final Function(String)? onTextChanged;
  final bool activeOnly;
  final String? initialValue;

  const GroupSearchField({
    super.key,
    required this.onSelected,
    this.onTextChanged,
    this.activeOnly = false,
    this.initialValue,
  });

  @override
  State<GroupSearchField> createState() => _GroupSearchFieldState();
}

class _GroupSearchFieldState extends State<GroupSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Group> _groups = [];
  bool _showDropdown = false;
  bool _isLoading = false;
  Timer? _debounce;
  int? _totalGroups;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    _loadInitialGroups();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _groups.isNotEmpty) {
        setState(() => _showDropdown = true);
      }
      if (!_focusNode.hasFocus) {
        // Delay to allow tap on dropdown item
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _showDropdown = false);
        });
      }
    });
  }

  Future<void> _loadInitialGroups() async {
    try {
      final groups = await ApiService.getGroups(activeOnly: widget.activeOnly);
      if (mounted) {
        setState(() {
          _groups = groups;
          _totalGroups = groups.length;
        });
      }
    } catch (_) {}
  }

  void _onSearchChanged(String query) {
    widget.onTextChanged?.call(query);
    _debounce?.cancel();

    if (_totalGroups != null && _totalGroups! <= 5) {
      // Filter locally
      if (query.isEmpty) {
        _loadInitialGroups();
      } else {
        setState(() {
          _groups = _groups
              .where((g) => g.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
        });
      }
      setState(() => _showDropdown = _groups.isNotEmpty);
      return;
    }

    if (query.length < 3) {
      setState(() {
        _showDropdown = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      setState(() => _isLoading = true);
      try {
        final groups = await ApiService.getGroups(
          search: query,
          activeOnly: widget.activeOnly,
        );
        if (mounted) {
          setState(() {
            _groups = groups;
            _showDropdown = groups.isNotEmpty;
            _isLoading = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          decoration: InputDecoration(
            labelText: 'Nama Group',
            border: const OutlineInputBorder(),
            suffixIcon: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
            hintText: _totalGroups != null && _totalGroups! > 5
                ? 'Ketik minimal 3 huruf...'
                : 'Ketik atau pilih group',
          ),
          onChanged: _onSearchChanged,
          onTap: () {
            _loadInitialGroups().then((_) {
              if (_groups.isNotEmpty) {
                setState(() => _showDropdown = true);
              }
            });
          },
        ),
        if (_showDropdown && _groups.isNotEmpty)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
              color: Colors.white,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _groups.length,
              itemBuilder: (context, index) {
                final group = _groups[index];
                return ListTile(
                  dense: true,
                  title: Text(group.name),
                  onTap: () {
                    _controller.text = group.name;
                    setState(() => _showDropdown = false);
                    _focusNode.unfocus();
                    widget.onSelected(group);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
