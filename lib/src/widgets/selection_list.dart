import 'package:flutter/material.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

/// A single scrollable owns both the scrollbar and the lazy list.
class SelectionList<T> extends StatefulWidget {
  const SelectionList({
    required this.title,
    required this.items,
    required this.label,
    required this.onSelect,
    this.icon,
    this.searchHint,
    this.status,
    super.key,
  });
  final String title;
  final List<T> items;
  final String Function(T) label;
  final void Function(T) onSelect;
  final Widget Function(T)? icon;
  final String? searchHint;
  final Widget? status;
  @override
  State<SelectionList<T>> createState() => _SelectionListState<T>();
}

class _SelectionListState<T> extends State<SelectionList<T>> {
  final _scroll = ScrollController();
  final _focus = FocusNode();
  String _term = '';
  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items
        .where(
          (v) => widget.label(v).toLowerCase().contains(_term.toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: widget.searchHint == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: Theme.of(context).canvasColor,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        children: [
                          const Icon(Icons.search),
                          Expanded(
                            child: TextField(
                              focusNode: _focus,
                              autofocus: true,
                              decoration: InputDecoration.collapsed(
                                hintText: widget.searchHint,
                              ),
                              onChanged: (value) {
                                if (_scroll.hasClients) _scroll.jumpTo(0);
                                setState(() => _term = value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
      body:
          widget.status ??
          (items.isEmpty
              ? Center(child: Text(context.t('No results')))
              : Scrollbar(
                  controller: _scroll,
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.only(top: 4),
                    itemCount: items.length,
                    itemBuilder: (context, index) => Card(
                      child: ListTile(
                        title: Text(widget.label(items[index])),
                        leading: widget.icon?.call(items[index]),
                        onTap: () => widget.onSelect(items[index]),
                      ),
                    ),
                  ),
                )),
    );
  }
}
