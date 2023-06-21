// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' hide FileSystemEntity;
import 'dart:io';

import 'package:args/args.dart';
import 'package:frontend_server/frontend_server.dart' as frontend show FrontendCompiler, CompilerInterface, listenAndCompile, argParser, usage;
import 'package:path/path.dart' as path;
import 'package:vm/incremental_compiler.dart';
import 'package:vm/target/flutter.dart';
import 'package:path/path.dart';
import '../src/transformer/aop/aop_transformer.dart';
import 'package:yaml/yaml.dart';

/// frontend.FrontendCompiler 的 wrapper 类
class _FlutterFrontendCompiler implements frontend.CompilerInterface {
  final frontend.CompilerInterface _compiler;
  final AspectdAopTransformer aspectdAopTransformer = AspectdAopTransformer();

  _FlutterFrontendCompiler(StringSink? output, {bool? unsafePackageSerialization, bool useDebuggerModuleNames=false, bool emitDebugMetadata=false})
      : _compiler = frontend.FrontendCompiler(output,
            useDebuggerModuleNames: useDebuggerModuleNames,
            emitDebugMetadata: emitDebugMetadata,
            unsafePackageSerialization: unsafePackageSerialization);

  @override
  Future<bool> compile(String filename, ArgResults options, {IncrementalCompiler? generator}) async {
    List<FlutterProgramTransformer> transformers = FlutterTarget.flutterProgramTransformers;
    if (!transformers.contains(aspectdAopTransformer)) {
      transformers.add(aspectdAopTransformer);
      if(options.rest.isNotEmpty) {
        aspectdAopTransformer.addEntryPoint(options.rest[0]);
      }
      _updateEntryPoints(options);
    }
    return _compiler.compile(filename, options, generator: generator);
  }

  @override
  Future<void> recompileDelta({String? entryPoint}) async {
    List<FlutterProgramTransformer> transformers = FlutterTarget.flutterProgramTransformers;
    transformers.clear();
    return _compiler.recompileDelta(entryPoint: entryPoint);
  }

  @override
  void acceptLastDelta() {
    _compiler.acceptLastDelta();
  }

  @override
  Future<void> rejectLastDelta() async {
    return _compiler.rejectLastDelta();
  }

  @override
  void invalidate(Uri uri) {
    _compiler.invalidate(uri);
  }

  @override
  Future<void> compileExpression(String expression, List<String> definitions, List<String> definitionTypes, List<String> typeDefinitions,
      List<String> typeBounds, List<String> typeDefaults, String libraryUri, String? klass, String? method, bool isStatic) {
    return _compiler.compileExpression(
        expression, definitions, definitionTypes, typeDefinitions, typeBounds, typeDefaults, libraryUri, klass, method, isStatic);
  }

  @override
  Future<void> compileExpressionToJs(
      // ignore: prefer_void_to_null
      String libraryUri,
      int line,
      int column,
      Map<String, String> jsModules,
      Map<String, String> jsFrameValues,
      String moduleName,
      String expression) {
    return _compiler.compileExpressionToJs(libraryUri, line, column, jsModules, jsFrameValues, moduleName, expression);
  }

  @override
  void reportError(String msg) {
    _compiler.reportError(msg);
  }

  @override
  void resetIncrementalCompiler() {
    _compiler.resetIncrementalCompiler();
  }

  ///用于更新 track widget 入口
  void _updateEntryPoints(ArgResults options) {
    String packagesFilePath = options["packages"];
    File packageFile = File(packagesFilePath);
    Directory projectDirectory = packageFile.parent.parent;
    List<FileSystemEntity>? fileEntities = projectDirectory.listSync();
    if (fileEntities != null) {
      try {
        fileEntities.firstWhere((fileEntity) {
          if (fileEntity is File) {
            if (basename(fileEntity.path) == "sensorsdata_aop_config.yaml") {
              String fileContent = fileEntity.readAsStringSync();
              Map map = loadYaml(fileContent);
              if (map.containsKey("entry_points")) {
                YamlList values = map["entry_points"];
                values.nodes.forEach((element) {
                  YamlNode node = element;
                  aspectdAopTransformer.addEntryPoint(node.value);
                });
              }
              return true;
            }
          }
          return false;
        });
      } catch (e) {
        //just not found
      }
    }
  }

  @override
  Future<bool> setNativeAssets(String nativeAssets) {
    return _compiler.setNativeAssets(nativeAssets);
  }
}

/// Entry point for this module, that creates `FrontendCompiler` instance and
/// processes user input.
/// `compiler` is an optional parameter so it can be replaced with mocked
/// version for testing.
Future<int> starter(
  List<String> args, {
  frontend.CompilerInterface? compiler,
  Stream<List<int>>? input,
  StringSink? output,
}) async {
  ArgResults options;
  try {
    options = frontend.argParser.parse(args);
  } catch (error) {
    print('ERROR: $error\n');
    print(frontend.usage);
    return 1;
  }

  if (options['train'] as bool) {
    if (!options.rest.isNotEmpty) {
      throw Exception('Must specify input.dart');
    }

    final String input = options.rest[0];
    final String sdkRoot = options['sdk-root'] as String;
    final Directory temp = Directory.systemTemp.createTempSync('train_frontend_server');
    try {
      for (int i = 0; i < 3; i++) {
        final String outputTrainingDill = path.join(temp.path, 'app.dill');
        options = frontend.argParser.parse(<String>[
          '--incremental',
          '--sdk-root=$sdkRoot',
          '--output-dill=$outputTrainingDill',
          '--target=flutter',
          '--track-widget-creation',
          '--enable-asserts',
        ]);
        compiler ??= _FlutterFrontendCompiler(output);

        await compiler.compile(input, options);
        compiler.acceptLastDelta();
        await compiler.recompileDelta();
        compiler.acceptLastDelta();
        compiler.resetIncrementalCompiler();
        await compiler.recompileDelta();
        compiler.acceptLastDelta();
        await compiler.recompileDelta();
        compiler.acceptLastDelta();
      }
      return 0;
    } finally {
      temp.deleteSync(recursive: true);
    }
  }

  compiler ??= _FlutterFrontendCompiler(output,
      useDebuggerModuleNames: options['debugger-module-names'] as bool,
      emitDebugMetadata: options['experimental-emit-debug-metadata'] as bool,
      unsafePackageSerialization: options['unsafe-package-serialization'] as bool);

  if (options.rest.isNotEmpty) {
    return await compiler.compile(options.rest[0], options) ? 0 : 254;
  }

  final Completer<int> completer = Completer<int>();
  frontend.listenAndCompile(compiler, input ?? stdin, options, completer);
  return completer.future;
}
