// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8

import 'dart:async';
import 'dart:convert';
import 'dart:io' hide FileSystemEntity;
import 'dart:io';

import 'package:args/args.dart';
import 'package:frontend_server/frontend_server.dart' as frontend
    show
    FrontendCompiler,
    CompilerInterface,
    listenAndCompile,
    argParser,
    usage;
import 'package:path/path.dart' as path;
import 'package:vm/incremental_compiler.dart';
import 'package:vm/target/flutter.dart';
import 'package:path/path.dart';
import '../src/transformer/aop/aop_transformer.dart';

/// flutter engine 已删除此类，此处保留此类是为了做 adapter
class _FlutterFrontendCompiler implements frontend.CompilerInterface {
  final frontend.CompilerInterface _compiler;
  final AspectdAopTransformer aspectdAopTransformer = AspectdAopTransformer();

  _FlutterFrontendCompiler(StringSink output,
      {bool unsafePackageSerialization,
        bool useDebuggerModuleNames,
        bool emitDebugMetadata})
      : _compiler = frontend.FrontendCompiler(output,
      useDebuggerModuleNames: useDebuggerModuleNames,
      emitDebugMetadata: emitDebugMetadata,
      unsafePackageSerialization: unsafePackageSerialization);

  @override
  Future<bool> compile(String filename, ArgResults options,
      {IncrementalCompiler generator}) async {
    List<FlutterProgramTransformer> transformers =
        FlutterTarget.flutterProgramTransformers;
    print("====11111===compile==server.dart");
    if (!transformers.contains(aspectdAopTransformer)) {
      print("====2222===compile==server.dart");
      transformers.add(aspectdAopTransformer);
      if(options.rest.isNotEmpty){
        aspectdAopTransformer.updateEntryPoint(options.rest[0]);
      }
    }
    //FlutterTarget.flutterProgramTransformers.add(MyTransformer());
    return _compiler.compile(filename, options, generator: generator);
  }

  @override
  Future<Null> recompileDelta({String entryPoint}) async {
    List<FlutterProgramTransformer> transformers =
        FlutterTarget.flutterProgramTransformers;
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
  Future<Null> compileExpression(String expression, List<String> definitions, List<String> definitionTypes, List<String> typeDefinitions, List<String> typeBounds, List<String> typeDefaults, String libraryUri, String klass, String method, bool isStatic) {
      return _compiler.compileExpression(expression, definitions, definitionTypes, typeDefinitions, typeBounds, typeDefaults, libraryUri, klass, method, isStatic);
  }

  @override
  Future<Null> compileExpressionToJs( // ignore: prefer_void_to_null
      String libraryUri,
      int line,
      int column,
      Map<String, String> jsModules,
      Map<String, String> jsFrameValues,
      String moduleName,
      String expression) {
    return _compiler.compileExpressionToJs(libraryUri, line, column, jsModules,
        jsFrameValues, moduleName, expression);
  }

  @override
  void reportError(String msg) {
    _compiler.reportError(msg);
  }

  @override
  void resetIncrementalCompiler() {
    _compiler.resetIncrementalCompiler();
  }
}

/// Entry point for this module, that creates `FrontendCompiler` instance and
/// processes user input.
/// `compiler` is an optional parameter so it can be replaced with mocked
/// version for testing.
Future<int> starter(
    List<String> args, {
      frontend.CompilerInterface compiler,
      Stream<List<int>> input,
      StringSink output,
    }) async {
  ArgResults options;
  print("starter args==============");
  print(args.join("   "));
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
    final Directory temp =
    Directory.systemTemp.createTempSync('train_frontend_server');
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
      unsafePackageSerialization:
      options['unsafe-package-serialization'] as bool);

  if (options.rest.isNotEmpty) {
    return await compiler.compile(options.rest[0], options) ? 0 : 254;
  }

  final Completer<int> completer = Completer<int>();
  frontend.listenAndCompile(compiler, input ?? stdin, options, completer);
  return completer.future;
}
