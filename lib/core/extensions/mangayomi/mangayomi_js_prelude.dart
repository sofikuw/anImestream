/// JavaScript prelude for MangaYomi extensions.
///
/// These strings are the host-side API that every MangaYomi JavaScript
/// extension expects to exist: `MProvider`, `Client`, `Document`, `Element`,
/// `SharedPreferences`, the logging shim, and the Kotlin-style `String`
/// helpers. They are evaluated once per runtime, before the extension source.
///
/// Kept in one file so the contract is easy to diff against upstream
/// `lib/eval/javascript/*.dart`.
library;

/// `console` plus the `substringAfter` family used by most sources.
const String mangayomiCommonPrelude = r'''
console.log = function (message) {
  if (typeof message === "object") { message = JSON.stringify(message); }
  sendMessage("log", JSON.stringify([String(message)]));
};
console.warn = console.log;
console.error = console.log;
String.prototype.substringAfter = function (pattern) {
  const startIndex = this.indexOf(pattern);
  if (startIndex === -1) return this.substring(0);
  return this.substring(startIndex + pattern.length);
};
String.prototype.substringAfterLast = function (pattern) {
  return this.split(pattern).pop();
};
String.prototype.substringBefore = function (pattern) {
  const endIndex = this.indexOf(pattern);
  if (endIndex === -1) return this.substring(0);
  return this.substring(0, endIndex);
};
String.prototype.substringBeforeLast = function (pattern) {
  const endIndex = this.lastIndexOf(pattern);
  if (endIndex === -1) return this.substring(0);
  return this.substring(0, endIndex);
};
String.prototype.substringBetween = function (left, right) {
  const index = this.indexOf(left);
  if (index === -1) return "";
  const leftIndex = index + left.length;
  const rightIndex = this.indexOf(right, leftIndex);
  if (rightIndex === -1) return "";
  return this.substring(leftIndex, rightIndex);
};
''';

/// HTTP, DOM, and preference classes backed by host channels.
const String mangayomiLibraryPrelude = r'''
class Client {
  constructor(reqcopyWith) { this.reqcopyWith = reqcopyWith; }
  async head(url, headers) {
    return JSON.parse(await sendMessage("http_head", JSON.stringify([null, this.reqcopyWith, url, headers])));
  }
  async get(url, headers) {
    return JSON.parse(await sendMessage("http_get", JSON.stringify([null, this.reqcopyWith, url, headers])));
  }
  async post(url, headers, body) {
    return JSON.parse(await sendMessage("http_post", JSON.stringify([null, this.reqcopyWith, url, headers, body])));
  }
  async put(url, headers, body) {
    return JSON.parse(await sendMessage("http_put", JSON.stringify([null, this.reqcopyWith, url, headers, body])));
  }
  async delete(url, headers, body) {
    return JSON.parse(await sendMessage("http_delete", JSON.stringify([null, this.reqcopyWith, url, headers, body])));
  }
  async patch(url, headers, body) {
    return JSON.parse(await sendMessage("http_patch", JSON.stringify([null, this.reqcopyWith, url, headers, body])));
  }
}

class SharedPreferences {
  get(key) { return sendMessage("get", JSON.stringify([key])); }
  getString(key, defaultValue) { return sendMessage("getString", JSON.stringify([key, defaultValue])); }
  setString(key, defaultValue) { return sendMessage("setString", JSON.stringify([key, defaultValue])); }
}

class Document {
  constructor(html) { this.html = html; }
  getElement(type) {
    const key = sendMessage("get_doc_element", JSON.stringify([this.html, type]));
    return new Element(key);
  }
  get body() { return this.getElement('body'); }
  get documentElement() { return this.getElement('documentElement'); }
  get head() { return this.getElement('head'); }
  get parent() { return this.getElement('parent'); }
  getString(type) { return sendMessage("get_doc_string", JSON.stringify([this.html, type])); }
  get text() { return this.getString('text'); }
  get outerHtml() { return this.getString('outerHtml'); }
  selectFirst(selector) {
    return new Element(sendMessage("doc_select_first", JSON.stringify([this.html, selector])));
  }
  select(selector) {
    return JSON.parse(sendMessage("doc_select", JSON.stringify([this.html, selector])))
      .map((key) => new Element(key));
  }
  xpathFirst(xpath) { return sendMessage("doc_xpath_first", JSON.stringify([this.html, xpath])); }
  xpath(xpath) { return JSON.parse(sendMessage("doc_xpath", JSON.stringify([this.html, xpath]))); }
  getElementsListBy(type, name) {
    name = name || '';
    return JSON.parse(sendMessage("doc_get_elements_by", JSON.stringify([this.html, type, name])))
      .map((key) => new Element(key));
  }
  get children() { return this.getElementsListBy('children'); }
  getElementsByTagName(name) { return this.getElementsListBy('getElementsByTagName', name); }
  getElementsByClassName(name) { return this.getElementsListBy('getElementsByClassName', name); }
  getElementById(id) {
    return new Element(sendMessage("doc_get_element_by_id", JSON.stringify([this.html, id])));
  }
  attr(attr) { return sendMessage("doc_attr", JSON.stringify([this.html, attr])); }
  hasAttr(attr) { return sendMessage("doc_has_attr", JSON.stringify([this.html, attr])); }
}

class Element {
  constructor(key) { this.key = key; }
  getString(type) { return sendMessage("get_element_string", JSON.stringify([type, this.key])); }
  get text() { return this.getString("text"); }
  get outerHtml() { return this.getString("outerHtml"); }
  get innerHtml() { return this.getString("innerHtml"); }
  get className() { return this.getString("className"); }
  get localName() { return this.getString("localName"); }
  get namespaceUri() { return this.getString("namespaceUri"); }
  get getSrc() { return this.getString("getSrc"); }
  get getImg() { return this.getString("getImg"); }
  get getHref() { return this.getString("getHref"); }
  get getDataSrc() { return this.getString("getDataSrc"); }
  getElementSibling(type) {
    return new Element(sendMessage("ele_element_sibling", JSON.stringify([type, this.key])));
  }
  get previousElementSibling() { return this.getElementSibling("previousElementSibling"); }
  get nextElementSibling() { return this.getElementSibling("nextElementSibling"); }
  getElementsListBy(type, name) {
    name = name || '';
    return JSON.parse(sendMessage("ele_get_elements_by", JSON.stringify([type, name, this.key])))
      .map((key) => new Element(key));
  }
  get children() { return this.getElementsListBy('children'); }
  getElementsByTagName(name) { return this.getElementsListBy('getElementsByTagName', name); }
  getElementsByClassName(name) { return this.getElementsListBy('getElementsByClassName', name); }
  xpath(xpath) { return JSON.parse(sendMessage("xpath", JSON.stringify([xpath, this.key]))); }
  xpathFirst(xpath) { return sendMessage("xpathFirst", JSON.stringify([xpath, this.key])); }
  attr(attr) { return sendMessage("ele_attr", JSON.stringify([attr, this.key])); }
  hasAttr(attr) { return sendMessage("ele_has_attr", JSON.stringify([attr, this.key])); }
  selectFirst(selector) {
    return new Element(sendMessage("ele_selectFirst", JSON.stringify([selector, this.key])));
  }
  select(selector) {
    return JSON.parse(sendMessage("ele_select", JSON.stringify([selector, this.key])))
      .map((key) => new Element(key));
  }
}
''';

/// The base class extension authors subclass as `DefaultExtension`.
const String mangayomiProviderPrelude = r'''
class MProvider {
  get source() { return globalThis.__MG_SOURCE__ || {}; }
  get supportsLatest() { throw new Error("supportsLatest not implemented"); }
  getHeaders(url) { throw new Error("getHeaders not implemented"); }
  async getPopular(page) { throw new Error("getPopular not implemented"); }
  async getLatestUpdates(page) { throw new Error("getLatestUpdates not implemented"); }
  async search(query, page, filters) { throw new Error("search not implemented"); }
  async getDetail(url) { throw new Error("getDetail not implemented"); }
  async getPageList(url) { throw new Error("getPageList not implemented"); }
  async getVideoList(url) { throw new Error("getVideoList not implemented"); }
  async getHtmlContent(name, url) { throw new Error("getHtmlContent not implemented"); }
  async cleanHtmlContent(html) { throw new Error("cleanHtmlContent not implemented"); }
  getFilterList() { throw new Error("getFilterList not implemented"); }
  getSourcePreferences() { throw new Error("getSourcePreferences not implemented"); }
}
''';

/// Host capabilities some sources call directly. Anything unimplemented throws
/// a named error instead of returning a silently wrong value.
const String mangayomiHostHelpersPrelude = r'''
function cryptoHandler(text, iv, secretKeyString, encrypt) {
  return sendMessage("cryptoHandler", JSON.stringify([text, iv, secretKeyString, encrypt]));
}
function encryptAESCryptoJS(plainText, passphrase) {
  return sendMessage("encryptAESCryptoJS", JSON.stringify([plainText, passphrase]));
}
function decryptAESCryptoJS(encryptedText, passphrase) {
  return sendMessage("decryptAESCryptoJS", JSON.stringify([encryptedText, passphrase]));
}
function decryptAESGCM(encryptedText, passphrase, salt, tagHex) {
  return sendMessage("decryptAESGCM", JSON.stringify([encryptedText, passphrase, salt, tagHex]));
}
function parseDates(list, format, locale) {
  return sendMessage("parseDates", JSON.stringify([list, format, locale]));
}
function deobfuscateJsPassword(inputString) {
  return sendMessage("deobfuscateJsPassword", JSON.stringify([inputString]));
}
function unpackJsAndCombine(scriptBlock) {
  return sendMessage("unpackJsAndCombine", JSON.stringify([scriptBlock]));
}
function unpackJs(packedJS) {
  return sendMessage("unpackJs", JSON.stringify([packedJS]));
}
async function evaluateJavascriptViaWebview(url, headers, scripts, time = 30) {
  return await sendMessage("evaluateJavascriptViaWebview", JSON.stringify([url, headers, scripts, time]));
}
async function createHlsProxyUrl(url, headers = {}) {
  return await sendMessage("createHlsProxyUrl", JSON.stringify([url, headers]));
}
async function parseEpub(bookName, url, headers) {
  return JSON.parse(await sendMessage("parseEpub", JSON.stringify([bookName, url, headers])));
}
async function parseEpubChapter(bookName, url, headers, chapterTitle) {
  return await sendMessage("parseEpubChapter", JSON.stringify([bookName, url, headers, chapterTitle]));
}
''';
