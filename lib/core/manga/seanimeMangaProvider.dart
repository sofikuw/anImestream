import 'dart:convert';

import 'package:animestream/core/extensions/javascript/javascript_runtime.dart';
import 'package:animestream/core/manga/mangaProvider.dart';
import 'package:animestream/core/manga/types.dart';

/// Support for Seanime-style provider extensions.
///
/// A Seanime extension is a `manifest.json` plus a `provider.js`:
///
/// ```json
/// { "id": "mangafreak", "name": "MangaFreak", "type": "manga-provider",
///   "language": "javascript", "version": "1.0.3",
///   "manifestURI": "https://.../manifest.json",
///   "payloadURI": "https://.../provider.js" }
/// ```
///
/// and the payload declares `class Provider` with
/// `search({query})`, `findChapters(id)`, `findChapterPages(id)` and
/// `getSettings()`.
///
/// ## The compatibility gap
///
/// Seanime providers do **not** use the `api.request` bridge that
/// [JavaScriptAnimeProvider] exposes. They call a global `fetch(url, init)` and
/// a global `LoadDoc(html)` that returns a cheerio-like selector API. Neither
/// exists in our runtime, so [seanimeRuntimeShim] supplies both ahead of the
/// provider source.
///
/// `fetch` is backed by the *same* allowlisted, HTTPS-only, DNS-pinned bridge
/// as every other extension, so Seanime code gains no extra network reach.
/// `LoadDoc` is a self-contained parser and selector engine, so HTML never
/// leaves the sandbox.
///
/// ## Honest limitations
///
/// - The selector engine covers what real providers use (tag, `.class`, `#id`,
///   `[attr]`, `:first-child`, `:last-child`, descendant and `>` combinators,
///   comma groups), not the whole CSS spec.
/// - Seanime manifests carry no `allowedHosts`. Hosts are instead harvested
///   from the payload source and intersected with the manifest, so the
///   allowlist stays explicit and reviewable rather than "anywhere".
library;

/// Preloaded before every Seanime payload. Defines `fetch` and `LoadDoc`.
///
/// Raw string: the JavaScript is full of `$`, backslashes and `${}` template
/// literals that must reach QuickJS verbatim.
const String seanimeRuntimeShim = r'''
// ---- fetch: adapts the host's allowlisted bridge to the shape Seanime code
// expects ({ ok, status, text(), json() }). The second argument is treated as
// { headers } when it has that key, otherwise as a flat header map -- real
// Seanime providers do both.
globalThis.fetch = function (url, init) {
  if (typeof url !== 'string') {
    return Promise.reject(new Error('fetch: url must be a string'));
  }
  var opts = init || {};
  var headers = {};
  var method = 'GET';
  var body;

  if (opts && typeof opts === 'object') {
    if (opts.headers && typeof opts.headers === 'object') {
      for (var k in opts.headers) headers[k] = String(opts.headers[k]);
    } else {
      for (var key in opts) {
        var value = opts[key];
        if (typeof value === 'string') headers[key] = value;
      }
    }
    if (typeof opts.method === 'string') method = opts.method.toUpperCase();
    if (opts.body !== undefined && opts.body !== null) body = opts.body;
  }

  return globalThis.__ANIMESTREAM_HTTP_REQUEST__({
    url: url,
    method: method,
    headers: headers,
    body: body
  }).then(function (res) {
    var text = res && res.body !== undefined ? String(res.body) : '';
    var status = res && typeof res.statusCode === 'number' ? res.statusCode : 0;
    return {
      ok: status >= 200 && status < 300,
      status: status,
      statusText: '',
      headers: (res && res.headers) || {},
      url: url,
      text: function () { return Promise.resolve(text); },
      json: function () { return Promise.resolve(JSON.parse(text)); }
    };
  });
};

// ---- LoadDoc: a compact HTML parser + selector engine.
(function () {
  var VOID = {area:1,base:1,br:1,col:1,embed:1,hr:1,img:1,input:1,link:1,meta:1,param:1,source:1,track:1,wbr:1};
  var RAW = {script:1,style:1};

  function parse(html) {
    var root = { tagName: '#root', attrs: {}, children: [], parent: null, text: '' };
    var stack = [root];
    var i = 0;
    var len = html.length;

    function top() { return stack[stack.length - 1]; }

    while (i < len) {
      var lt = html.indexOf('<', i);
      if (lt === -1) {
        top().text += html.slice(i);
        break;
      }
      if (lt > i) top().text += html.slice(i, lt);

      if (html.substr(lt, 4) === '<!--') {
        var endC = html.indexOf('-->', lt + 4);
        i = endC === -1 ? len : endC + 3;
        continue;
      }
      if (html.substr(lt, 2) === '<!') {
        var endD = html.indexOf('>', lt);
        i = endD === -1 ? len : endD + 1;
        continue;
      }
      if (html.substr(lt, 2) === '</') {
        var endT = html.indexOf('>', lt);
        if (endT === -1) { i = len; break; }
        var name = html.slice(lt + 2, endT).trim().toLowerCase();
        for (var s = stack.length - 1; s > 0; s--) {
          if (stack[s].tagName === name) { stack.length = s; break; }
        }
        i = endT + 1;
        continue;
      }

      var gt = html.indexOf('>', lt);
      if (gt === -1) { top().text += html.slice(lt); break; }
      var rawTag = html.slice(lt + 1, gt);
      var selfClosing = rawTag.slice(-1) === '/';
      if (selfClosing) rawTag = rawTag.slice(0, -1);

      var space = rawTag.search(/\s/);
      var tagName = (space === -1 ? rawTag : rawTag.slice(0, space)).toLowerCase();
      var attrText = space === -1 ? '' : rawTag.slice(space + 1);

      var node = { tagName: tagName, attrs: {}, children: [], parent: top(), text: '' };
      var attrRe = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
      var m;
      while ((m = attrRe.exec(attrText)) !== null) {
        var attrName = m[1].toLowerCase();
        var attrValue = m[2] !== undefined ? m[2] : (m[3] !== undefined ? m[3] : (m[4] !== undefined ? m[4] : ''));
        node.attrs[attrName] = attrValue;
      }
      top().children.push(node);

      if (!selfClosing && !VOID[tagName]) {
        stack.push(node);
        // Raw-text elements: consume verbatim up to the matching close tag.
        if (RAW[tagName]) {
          var close = html.toLowerCase().indexOf('</' + tagName, gt + 1);
          if (close === -1) { i = len; continue; }
          node.text = html.slice(gt + 1, close);
          i = close;
          continue;
        }
      }
      i = gt + 1;
    }
    return root;
  }

  function descendants(node, out) {
    for (var c = 0; c < node.children.length; c++) {
      out.push(node.children[c]);
      descendants(node.children[c], out);
    }
    return out;
  }

  function elementChildren(node) {
    return node.children;
  }

  function parseCompound(text) {
    var compound = { tag: null, id: null, classes: [], attrs: [], pseudos: [] };
    var re = /([#.]?[A-Za-z0-9_-]+)|(\[[^\]]+\])|(:[a-z-]+(?:\([^)]*\))?)/g;
    var m;
    while ((m = re.exec(text)) !== null) {
      var token = m[0];
      if (token[0] === '.') compound.classes.push(token.slice(1));
      else if (token[0] === '#') compound.id = token.slice(1);
      else if (token[0] === '[') {
        var inner = token.slice(1, -1);
        var eq = inner.indexOf('=');
        if (eq === -1) compound.attrs.push({ name: inner.trim().toLowerCase(), value: null });
        else compound.attrs.push({
          name: inner.slice(0, eq).trim().toLowerCase(),
          value: inner.slice(eq + 1).trim().replace(/^["']|["']$/g, '')
        });
      } else if (token[0] === ':') {
        compound.pseudos.push(token.slice(1).toLowerCase());
      } else if (token[0] === '*') {
        compound.tag = null;
      } else {
        compound.tag = token.toLowerCase();
      }
    }
    return compound;
  }

  function parseSelector(selector) {
    var groups = [];
    var parts = selector.split(',');
    for (var g = 0; g < parts.length; g++) {
      var chars = parts[g].trim();
      if (!chars) continue;
      var steps = [];
      var buffer = '';
      var combinator = ' ';
      for (var c = 0; c < chars.length; c++) {
        var ch = chars[c];
        if (ch === ' ' || ch === '>') {
          if (buffer) {
            steps.push({ combinator: steps.length === 0 ? null : combinator, compound: parseCompound(buffer) });
            buffer = '';
          }
          if (ch === '>') combinator = '>';
          else combinator = ' ';
        } else {
          buffer += ch;
        }
      }
      if (buffer) steps.push({ combinator: steps.length === 0 ? null : combinator, compound: parseCompound(buffer) });
      if (steps.length) groups.push(steps);
    }
    return groups;
  }

  function matchesCompound(el, compound, parent) {
    if (compound.tag && el.tagName !== compound.tag) return false;
    if (compound.id && el.attrs.id !== compound.id) return false;
    for (var c = 0; c < compound.classes.length; c++) {
      var klass = (el.attrs['class'] || '').split(/\s+/);
      if (klass.indexOf(compound.classes[c]) === -1) return false;
    }
    for (var a = 0; a < compound.attrs.length; a++) {
      var want = compound.attrs[a];
      if (!(want.name in el.attrs)) return false;
      if (want.value !== null && el.attrs[want.name] !== want.value) return false;
    }
    for (var p = 0; p < compound.pseudos.length; p++) {
      var pseudo = compound.pseudos[p];
      var siblings = parent ? parent.children : [];
      var at = siblings.indexOf(el);
      if (pseudo === 'first-child' && at !== 0) return false;
      if (pseudo === 'last-child' && at !== siblings.length - 1) return false;
      if (pseudo === 'empty' && el.children.length > 0) return false;
    }
    return true;
  }

  function matchSteps(el, steps, index) {
    if (index < 0) return true;
    var step = steps[index];
    var parent = el.parent;
    if (!matchesCompound(el, step.compound, parent)) return false;
    if (index === 0) return true;
    if (step.combinator === '>') return parent ? matchSteps(parent, steps, index - 1) : false;
    var ancestor = parent;
    while (ancestor) {
      if (matchSteps(ancestor, steps, index - 1)) return true;
      ancestor = ancestor.parent;
    }
    return false;
  }

  function query(root, selector) {
    var groups = parseSelector(selector);
    var pool = descendants(root, []);
    var out = [];
    for (var i = 0; i < pool.length; i++) {
      for (var g = 0; g < groups.length; g++) {
        if (matchSteps(pool[i], groups[g], groups[g].length - 1)) { out.push(pool[i]); break; }
      }
    }
    return out;
  }

  function textOf(node) {
    var out = node.text || '';
    for (var c = 0; c < node.children.length; c++) out += textOf(node.children[c]);
    return out;
  }

  function makeElement(node) {
    return {
      tagName: node.tagName,
      attrs: function () { return node.attrs; },
      attr: function (name) { return node.attrs[String(name).toLowerCase()]; },
      text: function () { return textOf(node); },
      html: function () { return textOf(node); },
      children: function () { return collection(node.children.slice()); },
      find: function (sel) { return collection(query(node, sel)); },
      parent: function () { return node.parent && node.parent.tagName !== '#root' ? collection([node.parent]) : collection([]); }
    };
  }

  function collection(nodes) {
    var api = {
      length: nodes.length,
      each: function (fn) {
        for (var i = 0; i < nodes.length; i++) fn(i, makeElement(nodes[i]));
        return api;
      },
      first: function () { return collection(nodes.length ? [nodes[0]] : []); },
      last: function () { return collection(nodes.length ? [nodes[nodes.length - 1]] : []); },
      eq: function (i) { return collection(nodes[i] === undefined ? [] : [nodes[i]]); },
      find: function (sel) {
        var found = [];
        for (var i = 0; i < nodes.length; i++) {
          var hits = query(nodes[i], sel);
          for (var h = 0; h < hits.length; h++) found.push(hits[h]);
        }
        return collection(found);
      },
      text: function () {
        var out = '';
        for (var i = 0; i < nodes.length; i++) out += textOf(nodes[i]);
        return out;
      },
      attrs: function () { return nodes.length ? nodes[0].attrs : {}; },
      attr: function (name) {
        return nodes.length ? nodes[0].attrs[String(name).toLowerCase()] : undefined;
      },
      is: function (sel) {
        var groups = parseSelector(sel);
        for (var i = 0; i < nodes.length; i++) {
          for (var g = 0; g < groups.length; g++) {
            if (matchSteps(nodes[i], groups[g], groups[g].length - 1)) return true;
          }
        }
        return false;
      }
    };
    return api;
  }

  globalThis.LoadDoc = function (html) {
    var root = parse(String(html));
    var doc = function (selector) { return collection(query(root, selector)); };
    doc.root = function () { return collection([root]); };
    return doc;
  };
})();

// Seanime payloads declare `class Provider`; expose an instance to callers.
if (typeof Provider === 'undefined') {
  throw new Error('Seanime provider must declare a class named Provider');
}
globalThis.__ANIMESTREAM_SEANIME__ = new Provider();
''';

/// A parsed Seanime `manifest.json`.
class SeanimeManifest {
  final String id;
  final String name;
  final String version;
  final String type;
  final String language;
  final String? description;
  final String? author;
  final String? icon;
  final String? lang;
  final String? manifestUri;
  final Uri payloadUri;

  SeanimeManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.type,
    required this.language,
    required this.payloadUri,
    this.description,
    this.author,
    this.icon,
    this.lang,
    this.manifestUri,
  });

  /// True only for `type: "manga-provider"`, so an anime-only Seanime
  /// extension is never wired to the manga side.
  bool get isManga => type == 'manga-provider';
  bool get isAnime => type == 'anime-provider' || type == 'onlinestream-provider';

  static final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$');

  factory SeanimeManifest.fromMap(Map<String, dynamic> map) {
    String required(String key) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Seanime manifest is missing "$key".');
      }
      return value.trim();
    }

    final id = required('id').toLowerCase();
    if (!_idPattern.hasMatch(id)) {
      throw const FormatException('Seanime manifest id is invalid.');
    }

    final type = required('type');
    if (type != 'manga-provider' && type != 'anime-provider' && type != 'onlinestream-provider') {
      throw FormatException('Unsupported Seanime provider type: $type.');
    }

    // Seanime requires JavaScript; a TypeScript payload would not run here.
    final language = required('language').toLowerCase();
    if (language != 'javascript' && language != 'js') {
      throw FormatException(
        'Only JavaScript Seanime payloads are supported (got "$language").',
      );
    }

    final rawPayload = required('payloadURI');
    final payload = Uri.tryParse(rawPayload);
    if (payload == null ||
        payload.scheme != 'https' ||
        payload.host.isEmpty ||
        payload.userInfo.isNotEmpty) {
      throw const FormatException(
        'Seanime payloadURI must be a public HTTPS URL.',
      );
    }

    final manifestUri = map['manifestURI'];
    final icon = map['icon'];
    final description = map['description'];
    final author = map['author'];
    final lang = map['lang'];

    return SeanimeManifest(
      id: id,
      name: required('name'),
      version: required('version'),
      type: type,
      language: language,
      payloadUri: payload,
      description: description is String ? description : null,
      author: author is String ? author : null,
      icon: icon is String && icon.startsWith('https://') ? icon : null,
      lang: lang is String ? lang : null,
      manifestUri: manifestUri is String ? manifestUri : null,
    );
  }

  /// Hosts to allow. Seanime manifests do not declare `allowedHosts`, so they
  /// are harvested from the payload source and given back for review.
  static Set<String> harvestAllowedHosts(String source) {
    final hosts = <String>{};
    for (final match in RegExp(r'https://([A-Za-z0-9.-]+)').allMatches(source)) {
      final host = match.group(1)!.toLowerCase();
      if (host.length > 253 || host.isEmpty) continue;
      if (!host.contains('.') || host.endsWith('.local') || host.endsWith('.internal')) {
        continue;
      }
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) continue;
      hosts.add(host);
    }
    // Hard cap so a hostile payload cannot balloon the allowlist.
    return hosts.length > 32 ? hosts.take(32).toSet() : hosts;
  }
}

/// Runs a Seanime `provider.js` as a [MangaChapterProvider].
class SeanimeMangaProvider implements MangaChapterProvider {
  SeanimeMangaProvider({
    required this.manifest,
    required JavaScriptRuntime runtime,
    required String code,
  })  : _runtime = runtime,
        _code = code;

  final SeanimeManifest manifest;
  final JavaScriptRuntime _runtime;
  final String _code;

  Future<void>? _loadFuture;
  bool _disposed = false;
  int _sequence = 0;

  @override
  String get providerName => manifest.name;

  @override
  String get providerId => manifest.id;

  Future<void> ensureLoaded() {
    if (_disposed || _runtime.isDisposed) {
      return Future<void>.error(
        StateError('Seanime provider "${manifest.id}" has been disposed.'),
      );
    }
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    // Shim first: it defines the `fetch` and `LoadDoc` globals the payload
    // expects, then instantiates `class Provider`.
    await _runtime.execute(
      JavaScriptExecutionRequest(
        requestId: '${manifest.id}:load:${_sequence++}',
        source: '$seanimeRuntimeShim\n$_code',
      ),
    );
  }

  Future<Object?> _invoke(String method, Object? argument) async {
    await ensureLoaded();
    final response = await _runtime.execute(
      JavaScriptExecutionRequest(
        requestId: '${manifest.id}:$method:${_sequence++}',
        input: <String, Object?>{'argument': argument},
        source: '''
const provider = globalThis.__ANIMESTREAM_SEANIME__;
const method = provider && provider[${jsonEncode(method)}];
if (typeof method !== 'function') {
  throw new Error('Seanime provider does not implement ${method}');
}
return await method.call(provider, input.argument);
''',
      ),
    );
    return response.value;
  }

  /// Seanime exposes manga search; surfaced so the picker can show matches.
  Future<List<MangaSummary>> search(String query) async {
    final result = await _invoke('search', <String, Object?>{'query': query});
    if (result is! List) return const <MangaSummary>[];
    return result.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return MangaSummary(
        id: map['id'].toString(),
        title: map['title'].toString(),
        cover: map['image']?.toString(),
        format: 'MANGA',
      );
    }).toList(growable: false);
  }

  @override
  Future<List<MangaChapter>> getChapters(MangaDetails manga) async {
    // Seanime's findChapters() takes the *provider's* manga id, so the AniList
    // title has to be resolved against this source first.
    final matches = await search(manga.title);
    if (matches.isEmpty) return const <MangaChapter>[];

    final target = _bestMatch(matches, manga);
    final result = await _invoke('findChapters', target.id);
    if (result is! List) return const <MangaChapter>[];

    return result.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return MangaChapter(
        id: map['id'].toString(),
        title: map['title']?.toString(),
        number: double.tryParse(map['chapter']?.toString() ?? ''),
        scanlator: map['scanlator']?.toString(),
      );
    }).toList(growable: false);
  }

  @override
  Future<List<MangaPage>> getPages(MangaChapter chapter) async {
    final result = await _invoke('findChapterPages', chapter.id);
    if (result is! List) return const <MangaPage>[];

    final pages = <MangaPage>[];
    for (var index = 0; index < result.length; index++) {
      final map = Map<String, dynamic>.from(result[index] as Map);
      final url = map['url'];
      if (url is! String || url.isEmpty) continue;

      Map<String, String>? headers;
      final rawHeaders = map['headers'];
      if (rawHeaders is Map) {
        headers = <String, String>{};
        for (final entry in rawHeaders.entries) {
          headers[entry.key.toString()] = entry.value.toString();
        }
      }

      pages.add(
        MangaPage(
          index: map['index'] is int ? map['index'] as int : index,
          imageUrl: url,
          headers: headers,
        ),
      );
    }
    return pages;
  }

  /// Prefers a normalised exact title match, then a prefix match, then the
  /// source's first result -- sources order by relevance.
  MangaSummary _bestMatch(List<MangaSummary> matches, MangaDetails manga) {
    String normalise(String value) => value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();

    final wanted = normalise(manga.title);
    for (final match in matches) {
      if (normalise(match.title) == wanted) return match;
    }
    for (final match in matches) {
      final candidate = normalise(match.title);
      if (candidate.startsWith(wanted) || wanted.startsWith(candidate)) {
        return match;
      }
    }
    return matches.first;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _runtime.dispose();
  }
}
