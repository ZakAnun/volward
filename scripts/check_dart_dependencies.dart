#!/usr/bin/env dart
// Architecture dependency and strongly connected component checker.
//
// Scans every Dart file under apps/volward/lib, resolves local import, export,
// part, and `part of` edges, reports unresolved local paths, and computes the
// graph's strongly connected components after collapsing each `part of` file
// into its owner library (the same model the baseline acceptance record used).
//
// Usage:
//   dart scripts/check_dart_dependencies.dart --root <repo> --check \
//       --accepted-cycles <json>
//   dart scripts/check_dart_dependencies.dart --root <repo>
//
// Without --check the current SCCs are printed as JSON (a sorted array of
// sorted arrays of lib-relative paths, e.g. "ai/ai_coverage_coordinator.dart").
// With --check the SCCs must exactly match the accepted-cycles file.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final opts = _parseArgs(args);
  final rootPath = opts['root'] ?? '.';
  final rootAbs = Directory(rootPath).absolute.path;
  final libDir = Directory(_normalize('$rootAbs/apps/volward/lib'));
  final acceptedPath = opts['accepted-cycles'];
  final check = opts.containsKey('check');

  if (!libDir.existsSync()) {
    stderr.writeln('error: Dart lib directory not found: ${libDir.path}');
    exitCode = 2;
    return;
  }

  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => f.path)
      .toList()
    ..sort();

  final edges = <String, List<String>>{};
  final partOwners = <String, String>{};
  final errors = <String>[];
  for (final path in files) {
    edges[path] = <String>[];
  }

  for (final path in files) {
    final content = File(path).readAsStringSync();
    _parseFile(path, content, libDir.path, edges, partOwners, errors);
  }

  String ownerOf(String path) {
    var current = path;
    final seen = <String>{};
    while (partOwners.containsKey(current)) {
      if (!seen.add(current)) {
        return current;
      }
      current = partOwners[current]!;
    }
    return current;
  }

  final collapsed = <String, Set<String>>{};
  for (final path in files) {
    collapsed.putIfAbsent(ownerOf(path), () => <String>{});
  }
  for (final path in files) {
    final owner = ownerOf(path);
    for (final dep in edges[path] ?? const <String>[]) {
      collapsed[owner]!.add(ownerOf(dep));
    }
  }

  for (final error in errors) {
    stderr.writeln('unresolved local import: $error');
  }

  final cycles = <List<String>>[];
  for (final component in _tarjan(collapsed)) {
    if (component.length > 1) {
      cycles.add(component.toList()..sort());
    } else {
      final only = component.single;
      if (collapsed[only]!.contains(only)) {
        cycles.add([only]);
      }
    }
  }
  cycles.sort((a, b) => a.join('\u0000').compareTo(b.join('\u0000')));

  String rel(String path) =>
      path.substring(libDir.path.length + 1).replaceAll('\\', '/');
  final normalized = cycles.map((c) => c.map(rel).toList()).toList();

  if (!check) {
    stdout.writeln(jsonEncode(normalized));
  } else {
    if (acceptedPath == null) {
      stderr.writeln('error: --check requires --accepted-cycles <json>');
      exitCode = 2;
      return;
    }
    final accepted = _loadAccepted(acceptedPath);
    final mismatch = jsonEncode(normalized) != jsonEncode(accepted);
    if (errors.isNotEmpty || mismatch) {
      if (mismatch) {
        stderr.writeln('SCC mismatch');
        stderr.writeln('  actual:   ${jsonEncode(normalized)}');
        stderr.writeln('  accepted: ${jsonEncode(accepted)}');
      }
      exitCode = 1;
      return;
    }
    stdout.writeln(
      'dart dependencies: OK '
      '(${normalized.length} cycle(s), ${collapsed.length} libraries)',
    );
  }

  if (errors.isNotEmpty) {
    exitCode = 1;
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final opts = <String, String>{};
  var i = 0;
  while (i < args.length) {
    final arg = args[i];
    if (arg == '--check') {
      opts['check'] = 'true';
      i += 1;
    } else if (arg == '--root' || arg == '--accepted-cycles') {
      if (i + 1 >= args.length) {
        stderr.writeln('error: $arg requires a value');
        exitCode = 2;
        return opts;
      }
      opts[arg.substring(2)] = args[i + 1];
      i += 2;
    } else {
      stderr.writeln('error: unknown argument: $arg');
      exitCode = 2;
      i += 1;
    }
  }
  return opts;
}

void _parseFile(
  String path,
  String content,
  String libDir,
  Map<String, List<String>> edges,
  Map<String, String> partOwners,
  List<String> errors,
) {
  final source = _stripComments(content);
  final importExport = RegExp(
    r'''(?:^|\n)[ \t]*(import|export)\s+(['"])([^'"]+)\2''',
    multiLine: true,
  );
  final part = RegExp(
    r'''(?:^|\n)[ \t]*part\s+(['"])([^'"]+)\1''',
    multiLine: true,
  );
  final partOf = RegExp(
    r'''(?:^|\n)[ \t]*part\s+of\s+(['"])([^'"]+)\1''',
    multiLine: true,
  );

  for (final match in partOf.allMatches(source)) {
    final uri = match.group(2)!;
    final target = _resolve(uri, path, libDir);
    if (target != null) {
      if (!File(target).existsSync()) {
        errors.add('$path -> part of $uri');
      } else {
        partOwners[path] = target;
      }
    }
  }

  for (final match in part.allMatches(source)) {
    final uri = match.group(2)!;
    final target = _resolve(uri, path, libDir);
    if (target != null) {
      if (!File(target).existsSync()) {
        errors.add('$path -> part $uri');
      } else {
        partOwners[target] = path;
      }
    }
  }

  for (final match in importExport.allMatches(source)) {
    final uri = match.group(3)!;
    final resolved = _resolve(uri, path, libDir);
    if (resolved != null) {
      if (!File(resolved).existsSync()) {
        errors.add('$path -> $uri');
      } else {
        edges[path]!.add(resolved);
      }
    }
  }
}

String _stripComments(String source) {
  final result = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final char = source[index];
    if (char == "'" || char == '"') {
      final triple = source.startsWith('$char$char$char', index);
      final delimiter = triple ? '$char$char$char' : char;
      result.write(delimiter);
      index += delimiter.length;
      while (index < source.length) {
        if (source.startsWith(delimiter, index)) {
          result.write(delimiter);
          index += delimiter.length;
          break;
        }
        final next = source[index];
        result.write(next);
        index += 1;
        if (next == '\\' && index < source.length) {
          result.write(source[index]);
          index += 1;
        }
      }
      continue;
    }

    if (char == '/' && index + 1 < source.length) {
      final next = source[index + 1];
      if (next == '/') {
        index += 2;
        while (index < source.length && source[index] != '\n') {
          index += 1;
        }
        continue;
      }
      if (next == '*') {
        index += 2;
        while (index + 1 < source.length &&
            !(source[index] == '*' && source[index + 1] == '/')) {
          if (source[index] == '\n') {
            result.write('\n');
          }
          index += 1;
        }
        if (index + 1 < source.length) {
          index += 2;
        }
        continue;
      }
    }

    result.write(char);
    index += 1;
  }
  return result.toString();
}

String? _resolve(String uri, String fromPath, String libDir) {
  if (uri.startsWith('dart:')) {
    return null;
  }
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    if (rest.startsWith('volward/')) {
      return '$libDir/${rest.substring('volward/'.length)}';
    }
    return null;
  }

  final dir = File(fromPath).parent.path;
  final target = _normalize('$dir/$uri'.replaceAll('\\', '/'));
  if (!target.startsWith('$libDir/')) {
    return null;
  }
  return target;
}

String _normalize(String path) {
  final isAbsolute = path.startsWith('/');
  final parts = <String>[];
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (parts.isNotEmpty) {
        parts.removeLast();
      }
    } else {
      parts.add(segment);
    }
  }
  return (isAbsolute ? '/' : '') + parts.join('/');
}

List<Set<String>> _tarjan(Map<String, Set<String>> graph) {
  final index = <String, int>{};
  final lowlink = <String, int>{};
  final onStack = <String, bool>{};
  final stack = <String>[];
  final result = <Set<String>>[];
  var counter = 0;

  void strongconnect(String v) {
    index[v] = counter;
    lowlink[v] = counter;
    counter += 1;
    stack.add(v);
    onStack[v] = true;

    for (final w in graph[v] ?? const <String>{}) {
      if (!index.containsKey(w)) {
        strongconnect(w);
        if (lowlink[w]! < lowlink[v]!) {
          lowlink[v] = lowlink[w]!;
        }
      } else if (onStack[w] == true) {
        if (index[w]! < lowlink[v]!) {
          lowlink[v] = index[w]!;
        }
      }
    }

    if (lowlink[v] == index[v]) {
      final component = <String>{};
      while (true) {
        final w = stack.removeLast();
        onStack[w] = false;
        component.add(w);
        if (w == v) {
          break;
        }
      }
      result.add(component);
    }
  }

  for (final v in graph.keys) {
    if (!index.containsKey(v)) {
      strongconnect(v);
    }
  }
  return result;
}

List<List<String>> _loadAccepted(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('error: accepted-cycles file not found: $path');
    exitCode = 2;
    return const [];
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! List) {
    stderr.writeln('error: accepted-cycles must be a JSON array: $path');
    exitCode = 2;
    return const [];
  }
  return decoded
      .map(
        (cycle) =>
            (cycle as List).map((entry) => entry.toString()).toList()..sort(),
      )
      .toList()
    ..sort((a, b) => a.join('\u0000').compareTo(b.join('\u0000')));
}
