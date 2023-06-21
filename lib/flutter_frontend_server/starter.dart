// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

library frontend_server;

import 'dart:io';

import 'server.dart';

Future<void> main(List<String> args) async {

  // List<String> newArgs = [];
  // newArgs.add("--sdk-root");
  // newArgs.add("/Users/zhangwei/Documents/tools/flutter/bin/cache/artifacts/engine/common/flutter_patched_sdk/");
  // newArgs.add("--target=flutter");
  // newArgs.add("--no-print-incremental-dependencies");
  // newArgs.add("-DFLUTTER_WEB_AUTO_DETECT=true");
  // newArgs.add("-DFLUTTER_WEB_CANVASKIT_URL=https://www.gstatic.com/flutter-canvaskit/d44b5a94c976fbb65815374f61ab5392a220b084/");
  // newArgs.add("-Ddart.vm.profile=false");
  // newArgs.add("-Ddart.vm.product=false");
  // newArgs.add("--enable-asserts");
  // newArgs.add("--track-widget-creation");
  // newArgs.add("--no-link-platform");
  // newArgs.add("--packages");
  // newArgs.add("/Users/zhangwei/Documents/work/flutter_workspace/testflutter/testdemo/.dart_tool/package_config.json ");
  // newArgs.add("--output-dill");
  // newArgs.add("/Users/zhangwei/Documents/work/flutter_workspace/testflutter/testdemo/.dart_tool/flutter_build/08f7d1ff72b507c6760d835cb621dc3f/app.dill");
  // newArgs.add("--depfile");
  // newArgs.add("/Users/zhangwei/Documents/work/flutter_workspace/testflutter/testdemo/.dart_tool/flutter_build/08f7d1ff72b507c6760d835cb621dc3f/kernel_snapshot.d");
  // newArgs.add("--incremental");
  // newArgs.add("--initialize-from-dill");
  // newArgs.add("/Users/zhangwei/Documents/work/flutter_workspace/testflutter/testdemo/.dart_tool/flutter_build/08f7d1ff72b507c6760d835cb621dc3f/app.dill");
  // // newArgs.add("--source");
  // // newArgs.add("package:sa_aspectd_impl/aspectd_impl.dart");
  // newArgs.add("--verbosity=error");
  // newArgs.add("package:testdemo/main.dart");

  final int exitCode = await starter(args);
  if (exitCode != 0) {
    exit(exitCode);
  }
}
