import './grammar.dart' show grammar;
import 'dart:convert';

Object? tryParseValue(String? v) {
  print('toIntIfInt: $v, length: ${v?.length}');
  return v != null ? int.tryParse(v) ?? v : null;
}

void attachProperties(Iterable<RegExpMatch> match,
    Map<String, dynamic> location, names, rawName) {
  if ((rawName != null && rawName.length > 0) &&
      (names == null || names.length == 0)) {
    match.forEach((m) {
      assert(rawName != null);
      location[rawName] =
          m.groupCount == 0 ? m.input.trim() : m.group(1)?.trim();
    });
  } else {
    match.forEach((m) {
      for (var i = 0; i < m.groupCount; i++) {
        assert(names[i] != null);
        location[names[i].toString()] = m.group(i + 1)?.trim();
      }
    });
  }
}

void parseReg(
    Map<String, dynamic> obj, Map<String, dynamic> location, String content) {
  var needsBlank = obj['name'] != null && obj['names'] != null;
  if (obj['push'] != null && location[obj['push']] == null) {
    assert(obj['push'] != null);
    location[obj['push']] = [];
  } else if (needsBlank && location[obj['name']] == null) {
    assert(obj['name'] != null);
    location[obj['name']] = createMap();
  }

  var keyLocation = obj['push'] != null
      ? createMap()
      : // blank object that will be pushed
      needsBlank
          ? location[obj['name']]
          : location; // otherwise, named location or root

  if (obj['reg'] is RegExp) {
    attachProperties(
        obj['reg'].allMatches(content), keyLocation, obj['names'], obj['name']);
  } else {
    attachProperties(RegExp(obj['reg']).allMatches(content), keyLocation,
        obj['names'], obj['name']);
  }

  if (obj['push'] != null) {
    location[obj['push']].add(keyLocation);
  }
}

Map<String, dynamic> parse(String sdp) {
  Map<String, dynamic> session = Map<String, dynamic>();
  final medias = [];

  var location =
      session; // points at where properties go under (one of the above)

  LineSplitter().convert(sdp).forEach((l) {
    if (l != '') {
      var type = l[0];
      var content = l.substring(2);
      if (type == 'm') {
        Map<String, dynamic> media = createMap();
        media['rtp'] = [];
        media['fmtp'] = [];
        location = media; // point at latest media line
        medias.add(media);
      }
      if (grammar[type] != null) {
        for (var j = 0; j < grammar[type]!.length; j += 1) {
          var obj = grammar[type]![j];
          if (obj['reg'] == null) {
            if (obj['name'] != null) {
              location[obj['name'] as String] = content;
            } else {
              print("trying to add null key");
            }
            continue;
          }

          if (obj['reg'] is RegExp) {
            if ((obj['reg'] as RegExp).hasMatch(content)) {
              parseReg(obj, location, content);
              return;
            }
          } else if (RegExp(obj['reg'] as String).hasMatch(content)) {
            parseReg(obj, location, content);
            return;
          }
        }
        if (location['invalid'] == null) {
          location['invalid'] = [];
        }
        Map tmp = createMap();
        tmp['value'] = content;
        location['invalid'].add(tmp);
      } else {
        print("ERROR unknown grammer type " + type);
      }
    }
  });

  // parse lines we understand
  session['media'] = medias; // link it up
  return session;
}

Map<dynamic, dynamic> parseParams(String str) {
  Map<dynamic, dynamic> params = createMap();
  str.split(new RegExp(r';').pattern).forEach((line) {
    // only split at the first '=' as there may be an '=' in the value as well
    int idx = line.indexOf("=");
    String key;
    String value = "";
    if (idx == -1) {
      key = line;
    } else {
      key = line.substring(0, idx).trim();
      value = line.substring(idx + 1, line.length).trim();
    }

    params[key] = tryParseValue(value);
  });
  return params;
}

List<String> parsePayloads(String str) {
  return str.split(' ');
}

List<dynamic> parseRemoteCandidates(String str) {
  var candidates = [];
  List<String> parts = [];
  str.split(' ').forEach((dynamic v) {
    dynamic value = tryParseValue(v);
    if (value != null) {
      parts.add(value);
    }
  });
  for (var i = 0; i < parts.length; i += 3) {
    candidates
        .add({'component': parts[i], 'ip': parts[i + 1], 'port': parts[i + 2]});
  }
  return candidates;
}

List<Map<String, dynamic>> parseImageAttributes(String str) {
  List<Map<String, dynamic>> attributes = [];
  str.split(' ').forEach((item) {
    Map<String, dynamic> params = createMap();
    item.substring(1, item.length - 1).split(',').forEach((attr) {
      List<String> kv = attr.split(new RegExp(r'=').pattern);
      params[kv[0]] = tryParseValue(kv[1]);
    });
    attributes.add(params);
  });
  return attributes;
}

Map<String, dynamic> createMap() {
  return Map();
}

List<dynamic> parseSimulcastStreamList(String str) {
  List<dynamic> attributes = [];
  str.split(';').forEach((stream) {
    List scids = [];
    stream.split(',').forEach((format) {
      var scid, paused = false;
      if (format[0] != '~') {
        scid = tryParseValue(format);
      } else {
        scid = tryParseValue(format.substring(1, format.length));
        paused = true;
      }
      Map<String, dynamic> data = createMap();
      data['scid'] = scid;
      data['paused'] = paused;
      scids.add(data);
    });
    attributes.add(scids);
  });
  return attributes;
}
