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
        usage,
        ProgramTransformer,
        ToStringTransformer;
import 'package:path/path.dart' as path;
import 'package:vm/incremental_compiler.dart';
import 'package:vm/target/flutter.dart';
import 'package:path/path.dart';
import 'package:aspectd/src/transformer/aop/aop_transformer.dart';


/// Wrapper around [FrontendCompiler] that adds [widgetCreatorTracker] kernel
/// transformation to the compilation.
class _FlutterFrontendCompiler implements frontend.CompilerInterface {
  final frontend.CompilerInterface _compiler;

  final AspectdAopTransformer aspectdAopTransformer = AspectdAopTransformer();
  _FlutterFrontendCompiler(StringSink output,
      {bool unsafePackageSerialization,
      bool useDebuggerModuleNames,
      bool emitDebugMetadata,
      frontend.ProgramTransformer transformer})
      : _compiler = frontend.FrontendCompiler(output,
            transformer: transformer,
            useDebuggerModuleNames: useDebuggerModuleNames,
            emitDebugMetadata: emitDebugMetadata,
            unsafePackageSerialization: unsafePackageSerialization);

  @override
  Future<bool> compile(String filename, ArgResults options,
      {IncrementalCompiler generator}) async {
    List<FlutterProgramTransformer> transformers =
        FlutterTarget.flutterProgramTransformers;
    if (!transformers.contains(aspectdAopTransformer)) {
      transformers.add(aspectdAopTransformer);
    }
    return _compiler.compile(filename, options, generator: generator);
  }

  @override
  Future<Null> recompileDelta({String entryPoint}) async {
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
  Future<Null> compileExpression(
      String expression,
      List<String> definitions,
      List<String> typeDefinitions,
      String libraryUri,
      String klass,
      bool isStatic) {
    return _compiler.compileExpression(
        expression, definitions, typeDefinitions, libraryUri, klass, isStatic);
  }

  @override
  Future<Null> compileExpressionToJs(
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

///根据 args 配置，获取其中的值
void resetPackageConfig(List<String> args) {
  try {
    if(args==null || args.isEmpty){
      return;
    }
    //获取 packages，然后解析其中的内容，并判断是否存在 aspectd_impl 目录
    //  /Users/zhangwei/Documents/work/flutter_workspace/flutter_deer_autotrack/flutter_deer/.dart_tool/package_config.json
    String packagesOption = '';
    int index = 0;
    for (index = 0; index < args.length; index++) {
      if (args[index].endsWith('package_config.json')) {
        packagesOption = args[index];
        break;
      }
    }
    if (packagesOption.endsWith('package_config.json')) {
      File packageFile = File(packagesOption);
      final bool aspectdImplExists = _checkAspectImplExists(packageFile);
      if(!aspectdImplExists){
        return;
      }
      bool exists = packageFile.existsSync();
      if (exists) {
        const JsonCodec json = JsonCodec();
        final _jsonUtf8Decoder = json.fuse(utf8).decoder;
        dynamic jsonObject =
        _jsonUtf8Decoder.convert(packageFile.readAsBytesSync());
        List packagesList = jsonObject['packages'];
        var aspectdMap = <String, String>{
          'name': 'aspectd',
          'rootUri': '../../flutter_aspectd',
          'packageUri': 'lib/',
          'languageVersion': '2.12'
        };
        var aspectImplMap = <String, String>{
          'name': 'aspectd_impl',
          'rootUri': '../../aspectd_impl',
          'packageUri': 'lib/',
          'languageVersion': '2.12'
        };
        packagesList.add(aspectdMap);
        packagesList.add(aspectImplMap);
        List<int> outputData = json.fuse(utf8).encode(jsonObject);
        File packageFileNew =
        File(packagesOption.replaceAll('.json', '2.json'));
        if (packageFileNew.existsSync()) {
          packageFileNew.deleteSync();
        }
        packageFileNew.createSync();
        packageFileNew.writeAsBytesSync(outputData);
        args.insert(index, packageFileNew.path);
        args.removeAt(index + 1);
      }
    }
  } catch (error) {
    print('can not handle aspectd: $error');
  }
}

bool _checkAspectImplExists(File packageConfigFile){
  //获取项目的同级目录
  Directory projectDirectory = packageConfigFile.parent.parent;
  Directory directory = projectDirectory.parent;
  List<FileSystemEntity> fileEntities = directory.listSync();
  int state = 0;
  bool isInConfigFile = false;
  for(int index=0;index<fileEntities.length;index++){
    final FileSystemEntity file = fileEntities[index];
    if(file is Directory){
      String fileName = basename(file.path);
      if(fileName == 'flutter_aspectd' || fileName == 'aspectd_impl'){
        state++;
      }
      if(fileName == 'aspectd_impl'){
        isInConfigFile = _checkMultiProjectFile(file, projectDirectory);
      }
    }
  }
  return state == 2 && isInConfigFile;
}

bool _checkMultiProjectFile(Directory dir, Directory projectDirectory){
  final List<FileSystemEntity> fileEntities = dir.listSync();
  final String projectDirectoryName = basename(projectDirectory.path);

  for(int index=0;index<fileEntities.length;index++){
    final FileSystemEntity file = fileEntities[index];

    if(file is File){
      final String fileName = basename(file.path);
      if(fileName == 'multiproject.config'){
        final List<String> projects = file.readAsLinesSync();
        if(projects !=null && projects.isNotEmpty){
          for(String projectName in projects){
            if(projectName == projectDirectoryName){
              return true;
            }
          }
        }
      }
    }
  }
  return false;
}

/// Entry point for this module, that creates `_FrontendCompiler` instance and
/// processes user input.
/// `compiler` is an optional parameter so it can be replaced with mocked
/// version for testing.
Future<int> starter(
  List<String> args, {
  frontend.CompilerInterface compiler,
  Stream<List<int>> input,
  StringSink output,
  frontend.ProgramTransformer transformer,
}) async {
  ArgResults options;
  frontend.argParser.addMultiOption(
    'delete-tostring-package-uri',
    help: 'Replaces implementations of `toString` with `super.toString()` for '
          'specified package',
    valueHelp: 'dart:ui',
    defaultsTo: const <String>[],
  );

  //重新包装一下 args list
  final List<String> newList = <String>[];
  newList.addAll(args);
  args = newList;
  resetPackageConfig(args);

  try {
    options = frontend.argParser.parse(args);
  } catch (error) {
    print('ERROR: $error\n');
    print(frontend.usage);
    return 1;
  }

  final Set<String> deleteToStringPackageUris = (options['delete-tostring-package-uri'] as List<String>).toSet();

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
        compiler ??= _FlutterFrontendCompiler(
          output,
          transformer: frontend.ToStringTransformer(null, deleteToStringPackageUris),
        );

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
      transformer: frontend.ToStringTransformer(transformer, deleteToStringPackageUris),
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
