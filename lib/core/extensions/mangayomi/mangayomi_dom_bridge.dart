import 'dart:convert';

import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Dart side of the MangaYomi `Document` / `Element` bridge.
///
/// MangaYomi extension JavaScript keeps opaque integer handles into a parser
/// table on the host. This mirrors that contract with `package:html` so the
/// stock MangaYomi `dom_selector` prelude can run unchanged.
///
/// Selector support is `package:html`'s CSS subset: type, class, id, attribute,
/// descendant/child/sibling combinators, and the pseudo-classes it implements.
/// XPath is not supported and answers empty, which only affects the minority of
/// sources that use it.
class MangayomiDomBridge {
  final Map<int, Element?> _elements = <int, Element?>{};
  int _nextKey = 0;
  bool _registered = false;

  void register(JavaScriptRuntime runtime) {
    if (_registered) return;
    _registered = true;

    void on(String channel, Object? Function(dynamic) handler) {
      runtime.registerHostMessageHandler(channel, handler);
    }

    on('get_doc_element', (dynamic arguments) {
      final args = _args(arguments);
      final document = _parse(args[0]);
      final type = args[1];
      final element = switch (type) {
        'body' => document.body,
        'documentElement' => document.documentElement,
        'head' => document.head,
        _ => document.parent,
      };
      return _store(element);
    });

    on('get_doc_string', (dynamic arguments) {
      final args = _args(arguments);
      final document = _parse(args[0]);
      final result = args[1] == 'text' ? document.text : document.outerHtml;
      return result;
    });

    on('get_element_string', (dynamic arguments) {
      final args = _args(arguments);
      final type = args[0];
      final element = _elements[args[1]];
      final result = switch (type) {
        'text' => element?.text,
        'innerHtml' => element?.innerHtml,
        'outerHtml' => element?.outerHtml,
        'className' => element?.className,
        'localName' => element?.localName,
        'namespaceUri' => element?.namespaceUri,
        'getSrc' => _firstAttribute(element, 'src'),
        'getImg' => _imgSource(element),
        'getHref' => _firstAttribute(element, 'href'),
        _ => _firstAttribute(element, 'data-src'),
      };
      return result ?? '';
    });

    on('doc_select_first', (dynamic arguments) {
      final args = _args(arguments);
      return _store(_selectFirst(_parse(args[0]), args[1]));
    });

    on('ele_selectFirst', (dynamic arguments) {
      final args = _args(arguments);
      return _store(_selectFirst(_elements[args[1]], args[0]));
    });

    on('ele_element_sibling', (dynamic arguments) {
      final args = _args(arguments);
      final element = _elements[args[1]];
      return _store(
        args[0] == 'nextElementSibling'
            ? element?.nextElementSibling
            : element?.previousElementSibling,
      );
    });

    on('ele_attr', (dynamic arguments) {
      final args = _args(arguments);
      return _elements[args[1]]?.attributes[args[0] as String] ?? '';
    });

    on('doc_attr', (dynamic arguments) {
      final args = _args(arguments);
      return _parse(args[0]).attributes[args[1] as String] ?? '';
    });

    on('ele_has_attr', (dynamic arguments) {
      final args = _args(arguments);
      return _elements[args[1]]?.attributes.containsKey(args[0]) ?? false;
    });

    on('doc_has_attr', (dynamic arguments) {
      final args = _args(arguments);
      return _parse(args[0]).attributes.containsKey(args[1]);
    });

    // XPath is not available through package:html. Answering empty keeps
    // sources that probe it from crashing while still failing visibly.
    on('doc_xpath_first', (dynamic) => '');
    on('ele_xpathFirst', (dynamic) => '');
    on('doc_xpath', (dynamic) => jsonEncode(const <String>[]));
    on('ele_xpath', (dynamic) => jsonEncode(const <String>[]));
    // MangaYomi's own prelude calls these two misspelled channels.
    on('xpathFirst', (dynamic) => '');
    on('xpath', (dynamic) => jsonEncode(const <String>[]));

    on('doc_get_elements_by', (dynamic arguments) {
      final args = _args(arguments);
      final document = _parse(args[0]);
      final type = args[1];
      final name = args[2];
      final elements = switch (type) {
        'children' => document.children,
        'getElementsByTagName' => document.getElementsByTagName('$name'),
        _ => document.getElementsByClassName('$name'),
      };
      return jsonEncode(_storeAll(elements));
    });

    on('ele_get_elements_by', (dynamic arguments) {
      final args = _args(arguments);
      final type = args[0];
      final name = args[1];
      final element = _elements[args[2]];
      final elements = switch (type) {
        'children' => element?.children ?? const <Element>[],
        'getElementsByTagName' =>
          element?.getElementsByTagName('$name') ?? const <Element>[],
        _ => element?.getElementsByClassName('$name') ?? const <Element>[],
      };
      return jsonEncode(_storeAll(elements));
    });

    on('doc_get_element_by_id', (dynamic arguments) {
      final args = _args(arguments);
      return _store(_parse(args[0]).getElementById('${args[1]}'));
    });

    on('doc_select', (dynamic arguments) {
      final args = _args(arguments);
      return jsonEncode(_storeAll(_selectAll(_parse(args[0]), args[1])));
    });

    on('ele_select', (dynamic arguments) {
      final args = _args(arguments);
      return jsonEncode(_storeAll(_selectAll(_elements[args[1]], args[0])));
    });
  }

  void dispose() {
    _elements.clear();
    _nextKey = 0;
  }

  /// The stock prelude sends `JSON.stringify([...])`; a few forks send the
  /// array itself, so both are accepted.
  static List<dynamic> _args(dynamic arguments) {
    var value = arguments;
    if (value is String) value = jsonDecode(value);
    if (value is List) return value;
    throw const FormatException('MangaYomi DOM channel expects an array.');
  }

  static Document _parse(Object? input) =>
      html_parser.parse(input is String ? input : '');

  static Element? _selectFirst(Object? root, Object? selector) {
    if (selector is! String || selector.trim().isEmpty) return null;
    try {
      if (root is Element) return root.querySelector(selector);
      if (root is Document) return root.querySelector(selector);
    } catch (_) {}
    return null;
  }

  static List<Element> _selectAll(Object? root, Object? selector) {
    if (selector is! String || selector.trim().isEmpty) {
      return const <Element>[];
    }
    try {
      if (root is Element) return root.querySelectorAll(selector);
      if (root is Document) return root.querySelectorAll(selector);
    } catch (_) {}
    return const <Element>[];
  }

  int _store(Element? element) {
    final key = ++_nextKey;
    _elements[key] = element;
    return key;
  }

  List<int> _storeAll(Iterable<Element> elements) {
    final keys = <int>[];
    for (final element in elements) {
      keys.add(_store(element));
    }
    return keys;
  }

  /// MangaYomi reads image/source URLs out of raw markup so lazy attributes and
  /// `srcset` still resolve. Try the direct attribute first, then the markup.
  static String? _firstAttribute(Element? element, String name) {
    if (element == null) return null;
    final direct = element.attributes[name];
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final pattern = RegExp(
      '$name\\s*=\\s*["\']([^"\']+)["\']',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(element.outerHtml);
    return match?.group(1)?.trim();
  }

  static String? _imgSource(Element? element) {
    if (element == null) return null;
    if (element.localName == 'img') {
      final src = _firstAttribute(element, 'src');
      if (src != null) return src;
    }
    final image = element.querySelector('img');
    return image == null ? null : _firstAttribute(image, 'src');
  }
}
