// Transformer/visitor for toString
// If we add any more of these, they really should go into a separate library.

import 'package:args/args.dart';
import 'package:frontend_server/frontend_server.dart' as frontend
    show FrontendCompiler, CompilerInterface, listenAndCompile, argParser, usage, ProgramTransformer;
import 'package:kernel/ast.dart';
import 'package:path/path.dart' as path;
import 'package:vm/incremental_compiler.dart';
import 'package:vm/target/flutter.dart';

import 'aop_iteminfo.dart';
import 'aop_mode.dart';
import 'aop_utils.dart';
import 'aspectd_aop_execute_visitor.dart';
import 'track_widget_custom_location.dart';

/// Replaces [Object.toString] overrides with calls to super for the specified
/// [packageUris].
class AspectdAopTransformer extends FlutterProgramTransformer {
  /// The [packageUris] parameter must not be null, but may be empty.
  AspectdAopTransformer();

  Component platformStrongComponent;
  final List<AopItemInfo> aopItemInfoList = <AopItemInfo>[];
  final List<AopItemInfo> callInfoList = <AopItemInfo>[];
  final List<AopItemInfo> executeInfoList = <AopItemInfo>[];
  final List<AopItemInfo> injectInfoList = <AopItemInfo>[];
  final Map<String, Library> libraryMap = <String, Library>{};
  final Map<Uri, Source> concatUriToSource = <Uri, Source>{};
  final WidgetCreatorTracker tracker = WidgetCreatorTracker();

  @override
  void transform(Component component) {
    print("AspectdAopTransformer====start transform");
    prepareAopItemInfo(component);
    if (executeInfoList.isNotEmpty) {
      print("AspectdAopTransformer====start transform==execute====${executeInfoList.length}");
      component.visitChildren(AspectdAopExecuteVisitor(executeInfoList));
    }
    tracker.transform(component, component.libraries);
  }

  void updateEntryPoint(String url) {
    print("update entry point======$url");
    tracker.updateEntryPoint(url);
  }

  //查找需要执行 AOP 的类
  void prepareAopItemInfo(Component program) {
    final List<Library> libraries = program.libraries;

    if (libraries.isEmpty) {
      return;
    }

    _resolveAopProcedures(libraries);
    Procedure pointCutProceedProcedure;
    Procedure listGetProcedure;
    Procedure mapGetProcedure;
    //Search the PointCut class first
    final List<Library> concatLibraries = <Library>[
      ...libraries,
      ...platformStrongComponent != null ? platformStrongComponent.libraries : <Library>[]
    ];
    concatUriToSource
      ..addAll(program.uriToSource)
      ..addAll(platformStrongComponent != null ? platformStrongComponent.uriToSource : <Uri, Source>{});
    for (Library library in concatLibraries) {
      libraryMap.putIfAbsent(library.importUri.toString(), () => library);
      if (pointCutProceedProcedure != null && listGetProcedure != null && mapGetProcedure != null) {
        continue;
      }
      final Uri importUri = library.importUri;
      for (Class cls in library.classes) {
        final String clsName = cls.name;
        if (clsName == AopUtils.kAopAnnotationClassPointCut && importUri.toString() == AopUtils.kImportUriPointCut) {
          for (Procedure procedure in cls.procedures) {
            if (procedure.name.text == AopUtils.kAopPointcutProcessName) {
              pointCutProceedProcedure = procedure; //获取到 PointCut 的 proceed 方法对应的 Procedure 对象
            }
          }
          //获取到 PointCut.target 字段
          if (pointCutProceedProcedure != null) {
            cls.fields.forEach((field) {
              if (field.name.text == 'target') {
                AopUtils.pointCuntTargetField = field;
              }
              if (field.name.text == 'stubKey') {
                AopUtils.pointCutStubKeyField = field;
              }
              if (field.name.text == 'positionalParams') {
                AopUtils.pointCutPositionParamsListField = field;
              }
              if (field.name.text == 'namedParams') {
                AopUtils.pointCutNamedParamsMapField = field;
              }
            });
          }
        }
        if (clsName == 'List' && importUri.toString() == 'dart:core') {
          for (Procedure procedure in cls.procedures) {
            if (procedure.name.text == '[]') {
              listGetProcedure = procedure;
            }
          }
        }
        if (clsName == 'bool' && importUri.toString() == 'dart:core') {
          AopUtils.boolClass = cls;
        }
        if (clsName == 'String' && importUri.toString() == 'dart:core') {
          for (Procedure procedure in cls.procedures) {
            if (procedure.name.text == '==') {
              AopUtils.stringEqualsProcedure = procedure;
            }
          }
        }

        if (clsName == 'Map' && importUri.toString() == 'dart:core') {
          for (Procedure procedure in cls.procedures) {
            if (procedure.name.text == '[]') {
              mapGetProcedure = procedure;
            }
          }
        }
      }
    }
    for (AopItemInfo aopItemInfo in aopItemInfoList) {
      if (aopItemInfo.mode == AopMode.Call) {
        callInfoList.add(aopItemInfo);
      } else if (aopItemInfo.mode == AopMode.Execute) {
        executeInfoList.add(aopItemInfo);
      } else if (aopItemInfo.mode == AopMode.Inject) {
        injectInfoList.add(aopItemInfo);
      }
    }

    AopUtils.pointCutProceedProcedure = pointCutProceedProcedure;
    AopUtils.listGetProcedure = listGetProcedure;
    AopUtils.mapGetProcedure = mapGetProcedure;
    AopUtils.platformStrongComponent = platformStrongComponent;
    // Aop call transformer
    if (callInfoList.isNotEmpty) {
      // final AopCallImplTransformer aopCallImplTransformer =
      // AopCallImplTransformer(
      //   callInfoList,
      //   libraryMap,
      //   concatUriToSource,
      // );

      for (Library library in libraries) {
        // aopCallImplTransformer.visitLibrary(library);
      }
    }
    // Aop execute transformer
    if (executeInfoList.isNotEmpty) {
      // AopExecuteImplTransformer(executeInfoList, libraryMap)..aopTransform();
    }
    // Aop inject transformer
    if (injectInfoList.isNotEmpty) {
      // AopInjectImplTransformer(injectInfoList, libraryMap, concatUriToSource)
      //   ..aopTransform();
    }
  }

  //查找 AOP 实现类，例如 SensorsAnayliticsAOP 这个类，然后查找这个类中的所有方法
  void _resolveAopProcedures(Iterable<Library> libraries) {
    for (Library library in libraries) {
      final List<Class> classes = library.classes;
      for (Class cls in classes) {
        final bool aspectdEnabled = AopUtils.checkIfClassEnableAspectd(cls.annotations);
        if (!aspectdEnabled) {
          continue;
        }
        for (Member member in cls.members) {
          //这里的 members 是指类的所有方法、字段等，例如 SensorsAnayliticsAOP 类中定义的 _incrementCounterTest 方法
          if (!(member is Member)) {
            continue;
          }
          final AopItemInfo aopItemInfo = _processAopMember(member); //此处需要注意 aopMember 字段，例如 _incrementCounterTest 方法对应的 Prodedure 对象
          if (aopItemInfo != null) {
            aopItemInfoList.add(aopItemInfo);
          }
        }
      }
    }
  }

  AopItemInfo _processAopMember(Member member) {
    for (Expression annotation in member.annotations) {
      //Release mode
      if (annotation is ConstantExpression) {
        final ConstantExpression constantExpression = annotation;
        final Constant constant = constantExpression.constant;
        if (constant is InstanceConstant) {
          final InstanceConstant instanceConstant = constant;
          final Class instanceClass = instanceConstant.classReference.node as Class;
          final AopMode aopMode =
              AopUtils.getAopModeByNameAndImportUri(instanceClass.name, (instanceClass.parent as Library)?.importUri.toString());
          if (aopMode == null) {
            continue;
          }
          String importUri;
          String clsName;
          String methodName;
          bool isRegex = false;
          int lineNum;
          instanceConstant.fieldValues.forEach((Reference reference, Constant constant) {
            if (constant is StringConstant) {
              final String value = constant.value;
              if ((reference.node as Field)?.name.toString() == AopUtils.kAopAnnotationImportUri) {
                importUri = value;
              } else if ((reference.node as Field)?.name.toString() == AopUtils.kAopAnnotationClsName) {
                clsName = value;
              } else if ((reference.node as Field)?.name.toString() == AopUtils.kAopAnnotationMethodName) {
                methodName = value;
              }
            }
            if (constant is IntConstant) {
              final int value = constant.value;
              if ((reference.node as Field)?.name.toString() == AopUtils.kAopAnnotationLineNum) {
                lineNum = value - 1;
              }
            }
            if (constant is BoolConstant) {
              final bool value = constant.value;
              if ((reference.node as Field)?.name?.toString() == AopUtils.kAopAnnotationIsRegex) {
                isRegex = value;
              }
            }
          });
          bool isStatic = false;
          if (methodName.startsWith(AopUtils.kAopAnnotationInstanceMethodPrefix)) {
            methodName = methodName.substring(AopUtils.kAopAnnotationInstanceMethodPrefix.length);
          } else if (methodName.startsWith(AopUtils.kAopAnnotationStaticMethodPrefix)) {
            methodName = methodName.substring(AopUtils.kAopAnnotationStaticMethodPrefix.length);
            isStatic = true;
          }
          member.annotations.clear();
          return AopItemInfo(
              importUri: importUri,
              clsName: clsName,
              methodName: methodName,
              isStatic: isStatic,
              aopMember: member,
              mode: aopMode,
              isRegex: isRegex,
              lineNum: lineNum);
        }
      }
      //Debug Mode
      else if (annotation is ConstructorInvocation) {
        final ConstructorInvocation constructorInvocation = annotation;
        final Class cls = constructorInvocation.targetReference.node?.parent as Class;
        final Library clsParentLib = cls?.parent as Library;
        final AopMode aopMode = AopUtils.getAopModeByNameAndImportUri(cls?.name, clsParentLib?.importUri.toString());
        if (aopMode == null) {
          continue;
        }
        final StringLiteral stringLiteral0 = constructorInvocation.arguments.positional[0] as StringLiteral;
        final String importUri = stringLiteral0.value;
        final StringLiteral stringLiteral1 = constructorInvocation.arguments.positional[1] as StringLiteral;
        final String clsName = stringLiteral1.value;
        final StringLiteral stringLiteral2 = constructorInvocation.arguments.positional[2] as StringLiteral;
        String methodName = stringLiteral2.value;
        bool isRegex = false;
        int lineNum;
        for (NamedExpression namedExpression in constructorInvocation.arguments.named) {
          if (namedExpression.name == AopUtils.kAopAnnotationLineNum) {
            final IntLiteral intLiteral = namedExpression.value as IntLiteral;
            lineNum = intLiteral.value - 1;
          }
          if (namedExpression.name == AopUtils.kAopAnnotationIsRegex) {
            final BoolLiteral boolLiteral = namedExpression.value as BoolLiteral;
            isRegex = boolLiteral.value;
          }
        }

        bool isStatic = false;
        if (methodName.startsWith(AopUtils.kAopAnnotationInstanceMethodPrefix)) {
          methodName = methodName.substring(AopUtils.kAopAnnotationInstanceMethodPrefix.length);
        } else if (methodName.startsWith(AopUtils.kAopAnnotationStaticMethodPrefix)) {
          methodName = methodName.substring(AopUtils.kAopAnnotationStaticMethodPrefix.length);
          isStatic = true;
        }
        member.annotations.clear();
        return AopItemInfo(
            importUri: importUri,
            clsName: clsName,
            methodName: methodName,
            isStatic: isStatic,
            aopMember: member,
            mode: aopMode,
            isRegex: isRegex,
            lineNum: lineNum);
      }
    }
    return null;
  }
}
