// ignore_for_file: invalid_use_of_visible_for_testing_member

// ignore: implementation_imports
import 'package:analyzer/src/manifest/manifest_validator.dart';

abstract class Node {
  Element? parent;

  final List<Node> nodes = [];
}

class Element extends Node {
  String? name;

  Map<String, String> attributes = {};

  List<Element> get children => nodes.whereType<Element>().toList();

  Element.tag(this.name);

  // This is for compatibility with the package:html DOM API.
  String? get localName => name;

  void append(Node child) {
    child.parent = this;
    nodes.add(child);
  }

  List<String> get classes {
    final classes = attributes['class'];
    if (classes != null) {
      return classes.split(' ').toList();
    } else {
      return const [];
    }
  }
}

class Text extends Node {
  static final RegExp tagRegex = RegExp(r'<[^>]+>');

  final String text;

  Text(this.text);

  @override
  List<Node> get nodes => const [];

  String get textRemoveTags {
    return text.replaceAll(tagRegex, '');
  }
}

class Document extends Element {
  static const Set<String> selfClosing = {
    'br',
    'link',
    'meta',
  };

  Document() : super.tag(null);

  String get outerHtml {
    var buf = StringBuffer();

    buf.write('<!DOCTYPE html>');

    void emitChild(Node node) {
      if (node is Element) {
        buf.write('<${node.name}');
        for (var attr in node.attributes.keys) {
          buf.write(' $attr="${node.attributes[attr]}"');
        }
        if (node.nodes.length == 1 &&
            node.nodes.first is Text &&
            !(node.nodes.first as Text).text.contains('\n')) {
          buf.write('>');
          var text = node.nodes.first as Text;
          buf.write(text.text);
          buf.write('</${node.name}>');
        } else {
          buf.write('>');
          for (var child in node.nodes) {
            emitChild(child);
          }
          if (!selfClosing.contains(node.name)) {
            buf.write('</${node.name}>');
          }
        }
      } else if (node is Text) {
        buf.write(node.text);
      } else {
        throw 'unknown node type: $node';
      }
    }

    for (var child in nodes) {
      emitChild(child);
    }

    return buf.toString();
  }
}

Document parse(String htmlContents, Uri uri) {
  Element createElement(XmlElement xmlElement) {
    // element
    var element = Element.tag(xmlElement.name);

    // attributes
    for (var key in xmlElement.attributes.keys) {
      element.attributes[key] = xmlElement.attributes[key]!.value;
    }

    // From the immediate children, determine where the text between the tags is
    // report any such non empty text as Text nodes.
    var text = xmlElement.sourceSpan?.text ?? '';

    if (!text.endsWith('/>')) {
      var indices = <int>[];
      var offset = xmlElement.sourceSpan!.start.offset;

      indices.add(text.indexOf('>') + 1);
      for (var child in xmlElement.children) {
        var childSpan = child.sourceSpan!;
        indices.add(childSpan.start.offset - offset);
        indices.add(childSpan.end.offset - offset);
      }
      indices.add(text.lastIndexOf('<'));

      var textNodes = <Text>[];
      for (var index = 0; index < indices.length; index += 2) {
        var start = indices[index];
        var end = indices[index + 1];
        textNodes.add(Text(text.substring(start, end)));
      }

      element.append(textNodes.removeAt(0));

      for (var child in xmlElement.children) {
        element.append(createElement(child));
        element.append(textNodes.removeAt(0));
      }

      element.nodes.removeWhere((node) => node is Text && node.text.isEmpty);
    }

    return element;
  }

  var parser = ManifestParser.general(htmlContents, uri: uri);
  var result = parser.parseXmlTag();

  while (result.parseResult != ParseTagResult.eof.parseResult) {
    if (result.element != null) {
      var document = Document();
      document.append(createElement(result.element!));
      return document;
    }

    result = parser.parseXmlTag();
  }

  throw 'parse error - element not found';
}
