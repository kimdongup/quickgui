import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:gettext_i18n/gettext_i18n.dart';

import '../model/operating_system.dart';
import '../../main.dart' show loadOperatingSystems;
import '../model/osicons.dart';

class OperatingSystemSelection extends StatefulWidget {
  const OperatingSystemSelection({super.key});

  @override
  State<OperatingSystemSelection> createState() =>
      _OperatingSystemSelectionState();
}

class _OperatingSystemSelectionState extends State<OperatingSystemSelection> {
  var term = "";
  late Future<List<OperatingSystem>> _catalog;
  final focusNode = FocusNode();

  @override
  void initState() {
    _catalog = loadOperatingSystems();
    focusNode.requestFocus();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('Select operating system')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              decoration: BoxDecoration(color: Theme.of(context).canvasColor),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.search),
                      Expanded(
                        child: TextField(
                          focusNode: focusNode,
                          decoration: InputDecoration.collapsed(
                            hintText: context.t('Search operating system'),
                          ),
                          onChanged: (value) {
                            setState(() {
                              term = value;
                            });
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
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            FutureBuilder(
              future: _catalog,
              builder: (BuildContext context, AsyncSnapshot<List> snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      SelectableText('${snapshot.error}'),
                      TextButton(
                        onPressed: () => setState(() {
                          _catalog = loadOperatingSystems();
                        }),
                        child: Text(context.t('Retry')),
                      ),
                    ],
                  );
                }
                if (snapshot.hasData) {
                  List list = snapshot.data!
                      .where(
                        (os) =>
                            os.name.toLowerCase().contains(term.toLowerCase()),
                      )
                      .toList();
                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 4),
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      var item = list[index];
                      Widget icon;

                      if (osIcons.containsKey(item.code)) {
                        icon = SvgPicture.asset(
                          osIcons[item.code]!,
                          width: 32,
                          height: 32,
                        );
                      } else {
                        // Replace with generic icon
                        icon = const Icon(Icons.computer, size: 32);
                      }
                      return Card(
                        child: ListTile(
                          title: Text(item.name),
                          leading: icon,
                          onTap: () {
                            Navigator.of(context).pop(item);
                          },
                        ),
                      );
                    },
                  );
                } else {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                          Text(context.t('Loading available downloads')),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
