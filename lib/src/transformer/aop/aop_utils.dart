import 'dart:convert';

import 'package:kernel/ast.dart';

import 'aop_iteminfo.dart';
import 'aop_mode.dart';

class AopUtils {
  AopUtils();

  static String kAopAnnotationClassCall = 'Call';
  static String kAopAnnotationClassExecute = 'Execute';
  static String kAopAnnotationClassInject = 'Inject';
  static String kImportUriAopAspect = 'package:sa_aspectd_impl/aop/annotation/aspect.dart';
  static String kImportUriAopCall = 'package:sa_aspectd_impl/aop/annotation/call.dart';
  static String kImportUriAopExecute = 'package:sa_aspectd_impl/aop/annotation/execute.dart';
  static String kImportUriAopInject = 'package:sa_aspectd_impl/aop/annotation/inject.dart';
  static String kImportUriPointCut = 'package:sa_aspectd_impl/aop/annotation/pointcut.dart';
  static String kAopUniqueKeySeperator = '#';
  static String kAopAnnotationClassAspect = 'Aspect';
  static String kAopAnnotationImportUri = 'importUri';
  static String kAopAnnotationClsName = 'clsName';
  static String kAopAnnotationMethodName = 'methodName';
  static String kAopAnnotationIsRegex = 'isRegex';
  static String kAopAnnotationLineNum = 'lineNum';
  static String kAopAnnotationClassPointCut = 'PointCut';
  static String kAopAnnotationInstanceMethodPrefix = '-';
  static String kAopAnnotationStaticMethodPrefix = '+';
  static int kPrimaryKeyAopMethod = 0;
  static String kAopStubMethodPrefix = 'aop_stub_';
  static String kAopPointcutProcessName = 'proceed';
  static String kAopPointcutIgnoreVariableDeclaration = '//Aspectd Ignore';
  static Procedure pointCutProceedProcedure;
  static Procedure listGetProcedure;
  static Procedure mapGetProcedure;
  static Component platformStrongComponent;
  static Set<Procedure> manipulatedProcedureSet = {};
  static Field pointCuntTargetField;
  static Field pointCutStubKeyField;
  static Class boolClass;
  static Procedure stringEqualsProcedure;
  static Field pointCutPositionParamsListField;
  static Field pointCutNamedParamsMapField;
  static Field pointCutCuriousField;

  static AopMode getAopModeByNameAndImportUri(String name, String importUri) {
    if (name == kAopAnnotationClassCall && importUri == kImportUriAopCall) {
      return AopMode.Call;
    }
    if (name == kAopAnnotationClassExecute && importUri == kImportUriAopExecute) {
      return AopMode.Execute;
    }
    if (name == kAopAnnotationClassInject && importUri == kImportUriAopInject) {
      return AopMode.Inject;
    }
    return null;
  }

  //Generic Operation
  static void insertLibraryDependency(Library library, Library dependLibrary) {
    for (LibraryDependency dependency in library.dependencies) {
      if (dependency.importedLibraryReference.node == dependLibrary) {
        return;
      }
    }
    library.dependencies.add(LibraryDependency.import(dependLibrary));
  }

  static int getLineStartNumForStatement(Source source, Statement statement) {
    int fileOffset = statement.fileOffset;
    if (fileOffset == -1) {
      if (statement is ExpressionStatement) {
        final ExpressionStatement expressionStatement = statement;
        fileOffset = expressionStatement.expression.fileOffset;
      } else if (statement is AssertStatement) {
        final AssertStatement assertStatement = statement;
        fileOffset = assertStatement.conditionStartOffset;
      } else if (statement is LabeledStatement) {
        fileOffset = statement.body.fileOffset;
      }
    }
    return getLineNumBySourceAndOffset(source, fileOffset);
  }

  static int getLineStartNumForInitializer(Source source, Initializer initializer) {
    int fileOffset = initializer.fileOffset;
    if (fileOffset == -1) {
      if (initializer is AssertInitializer) {
        fileOffset = initializer.statement.conditionStartOffset;
      }
    }
    return getLineNumBySourceAndOffset(source, fileOffset);
  }

  static int getLineNumBySourceAndOffset(Source source, int fileOffset) {
    final int lineNum = source.lineStarts.length;
    for (int i = 0; i < lineNum; i++) {
      final int lineStart = source.lineStarts[i];
      if (fileOffset >= lineStart && (i == lineNum - 1 || fileOffset < source.lineStarts[i + 1])) {
        return i;
      }
    }
    return -1;
  }

  static VariableDeclaration checkIfSkipableVarDeclaration(Source source, Statement statement) {
    if (statement is VariableDeclaration) {
      final VariableDeclaration variableDeclaration = statement;
      final int lineNum = AopUtils.getLineNumBySourceAndOffset(source, variableDeclaration.fileOffset);
      if (lineNum == -1) {
        return null;
      }
      final int charFrom = source.lineStarts[lineNum];
      int charTo = source.source.length;
      if (lineNum < source.lineStarts.length - 1) {
        charTo = source.lineStarts[lineNum + 1];
      }
      final String sourceString = const Utf8Decoder().convert(source.source);
      final String sourceLine = sourceString.substring(charFrom, charTo);
      if (sourceLine.endsWith(AopUtils.kAopPointcutIgnoreVariableDeclaration)) {
        return variableDeclaration;
      }
    }
    return null;
  }

  static List<String> getPropertyKeyPaths(String propertyDesc) {
    final List<String> tmpItems = propertyDesc.split('.');
    final List<String> items = <String>[];
    for (String item in tmpItems) {
      final int idx1 = item.lastIndexOf('::');
      final int idx2 = item.lastIndexOf('}');
      if (idx1 != -1 && idx2 != -1) {
        items.add(item.substring(idx1 + 2, idx2));
      } else {
        items.add(item);
      }
    }
    return items;
  }

  static Class findClassFromThisWithKeypath(Class thisClass, List<String> keypaths) {
    final int len = keypaths.length;
    Class cls = thisClass;
    for (int i = 0; i < len - 1; i++) {
      final String part = keypaths[i];
      if (part == 'this') {
        continue;
      }
      for (Field field in cls.fields) {
        if (field.name.text == part) {
          final InterfaceType interfaceType = field.type as InterfaceType;
          cls = interfaceType.className.node as Class;
          break;
        }
      }
    }
    return cls;
  }

  static Field findFieldForClassWithName(Class cls, String fieldName) {
    for (Field field in cls.fields) {
      if (field.name.text == fieldName) {
        return field;
      }
    }
    return null;
  }

  static bool isAsyncFunctionNode(FunctionNode functionNode) {
    return functionNode.dartAsyncMarker == AsyncMarker.Async || functionNode.dartAsyncMarker == AsyncMarker.AsyncStar;
  }

  static Node getNodeToVisitRecursively(Object statement) {
    if (statement is FunctionDeclaration) {
      return statement.function;
    }
    if (statement is LabeledStatement) {
      return statement.body;
    }
    if (statement is IfStatement) {
      return statement.then;
    }
    if (statement is ForInStatement) {
      return statement.body;
    }
    if (statement is ForStatement) {
      return statement.body;
    }
    return null;
  }

  //根据需要被 hook 的代码的参数，构建最终的 PointCut 的构造方法参数
  static void concatArgumentsForAopMethod(Map<String, String> sourceInfo, Arguments redirectArguments, String stubKey, Expression targetExpression,
      Member member, Arguments invocationArguments) {
    final String stubKeyDefault = '${AopUtils.kAopStubMethodPrefix}${AopUtils.kPrimaryKeyAopMethod}';
    //重定向到AOP的函数体中去
    final Arguments pointCutConstructorArguments = Arguments.empty();
    final List<MapLiteralEntry> sourceInfos = <MapLiteralEntry>[];
    sourceInfo?.forEach((String key, String value) {
      sourceInfos.add(MapLiteralEntry(StringLiteral(key), StringLiteral(value)));
    });
    pointCutConstructorArguments.positional.add(MapLiteral(sourceInfos));
    pointCutConstructorArguments.positional.add(targetExpression);
    String memberName = member?.name.text;
    if (member is Constructor) {
      memberName = AopUtils.nameForConstructor(member);
    }
    pointCutConstructorArguments.positional.add(StringLiteral(memberName));
    pointCutConstructorArguments.positional.add(StringLiteral(stubKey ?? stubKeyDefault));
    pointCutConstructorArguments.positional.add(ListLiteral(invocationArguments.positional));
    final List<MapLiteralEntry> entries = <MapLiteralEntry>[];
    for (NamedExpression namedExpression in invocationArguments.named) {
      entries.add(MapLiteralEntry(StringLiteral(namedExpression.name), namedExpression.value));
    }
    pointCutConstructorArguments.positional.add(MapLiteral(entries));

    final Class pointCutProceedProcedureCls = pointCutProceedProcedure.parent as Class;
    final ConstructorInvocation pointCutConstructorInvocation =
        ConstructorInvocation(pointCutProceedProcedureCls.constructors.first, pointCutConstructorArguments);
    redirectArguments.positional.add(pointCutConstructorInvocation);
  }

  //构建调用原始方法的代理方法的参数，member 就是原始的 Procedure
  static Arguments concatArguments4PointcutStubCall(Member member) {
    final Arguments arguments = Arguments.empty();
    //处理位置参数
    int i = 0;
    for (VariableDeclaration variableDeclaration in member.function.positionalParameters) {
      //此处是将 PointCut 中的 positionalParams 分别转换为不同的类型
      final Arguments getArguments = Arguments.empty();
      getArguments.positional.add(IntLiteral(i));
      //调用 List 中的 i 项，并做类型转换  this.positionalParams[i] as int
      //此处相当于 this.positionalParams
      InstanceGet instanceGet = InstanceGet.byReference(InstanceAccessKind.Instance, ThisExpression(), Name("positionalParams"),
          interfaceTargetReference: pointCutPositionParamsListField.getterReference, resultType: pointCutPositionParamsListField.type);

      //调用 list[i]
      InstanceInvocation mockedInstanceInvocation = InstanceInvocation(
          InstanceAccessKind.Instance,
          instanceGet,
          listGetProcedure.name, //此处的 name 为  []
          getArguments,
          interfaceTarget: listGetProcedure,
          functionType: AopUtils.computeFunctionTypeForFunctionNode(listGetProcedure.function, arguments));
      //转换成原方法中对应位置的类型
      AsExpression asExpression = AsExpression(mockedInstanceInvocation, deepCopyASTNode(variableDeclaration.type, ignoreGenerics: true));
      arguments.positional.add(asExpression);
      i++;
    }
    //处理命名参数
    final List<NamedExpression> namedEntries = <NamedExpression>[];
    for (VariableDeclaration variableDeclaration in member.function.namedParameters) {
      final Arguments getArguments = Arguments.empty();
      getArguments.positional.add(StringLiteral(variableDeclaration.name));

      //调用 this.positionalParams
      InstanceGet instanceGet = InstanceGet.byReference(InstanceAccessKind.Instance, ThisExpression(), Name("namedParams"),
          interfaceTargetReference: pointCutNamedParamsMapField.getterReference, resultType: pointCutNamedParamsMapField.type);

      int a = 10;

      //调用 this.positionalParams["xxx"]
      InstanceInvocation mockedInstanceInvocation = InstanceInvocation(
          InstanceAccessKind.Instance,
          instanceGet,
          mapGetProcedure.name, //此处的 name 为  []
          getArguments,
          interfaceTarget: mapGetProcedure,
          functionType: AopUtils.computeFunctionTypeForFunctionNode(mapGetProcedure.function, arguments));

      final AsExpression asExpression = AsExpression(mockedInstanceInvocation, deepCopyASTNode(variableDeclaration.type, ignoreGenerics: true));
      namedEntries.add(NamedExpression(variableDeclaration.name, asExpression)); //相当于 PointCut   this.namedParams["name"] as String
    }
    if (namedEntries.isNotEmpty) {
      arguments.named.addAll(namedEntries);
    }
    return arguments;
  }

  //修改 PointCut proceed 方法中的分支
  static void insertProceedBranch(Procedure procedure, bool shouldReturn) {
    final Block block = pointCutProceedProcedure.function.body as Block; //proceed 方法的内容
    final String methodName = procedure.name.text; //aop_stub0

    InstanceInvocation instanceInvocation = InstanceInvocation(InstanceAccessKind.Instance, ThisExpression(), Name(methodName), Arguments.empty(),
        interfaceTarget: procedure, functionType: AopUtils.computeFunctionTypeForFunctionNode(procedure.function, Arguments.empty()));

    final List<Statement> statements = block.statements;

    EqualsCall equalsCall = EqualsCall(
        InstanceGet.byReference(
            //left
            InstanceAccessKind.Instance, //this.stubkey
            ThisExpression(),
            Name("stubKey"),
            interfaceTargetReference: pointCutStubKeyField.getterReference,
            resultType: pointCutStubKeyField.type),
        StringLiteral(methodName), //right
        functionType: FunctionType([], InterfaceType(boolClass, Nullability.nonNullable), Nullability.nonNullable),
        interfaceTarget: stringEqualsProcedure);

    IfStatement ifStatement = IfStatement(
        equalsCall,
        Block(<Statement>[
          if (shouldReturn) ReturnStatement(instanceInvocation),
          if (!shouldReturn) ExpressionStatement(instanceInvocation),
        ]),
        null);

    statements.insert(statements.length - 1, ifStatement);
  }

  static bool canOperateLibrary(Library library) {
    if (platformStrongComponent != null && platformStrongComponent.libraries.contains(library)) {
      return false;
    }
    return true;
  }

  static Block createProcedureBodyWithExpression(Expression expression, bool shouldReturn) {
    final Block bodyStatements = Block(<Statement>[]);
    if (shouldReturn) {
      bodyStatements.addStatement(ReturnStatement(expression));
    } else {
      bodyStatements.addStatement(ExpressionStatement(expression));
    }
    return bodyStatements;
  }

  // Skip aop operation for those aspectd/aop package.
  static bool checkIfSkipAOP(AopItemInfo aopItemInfo, Library curLibrary) {
    final Library aopLibrary1 = aopItemInfo.aopMember.parent.parent as Library;
    final Library aopLibrary2 = pointCutProceedProcedure.parent.parent as Library;
    if (curLibrary == aopLibrary1 || curLibrary == aopLibrary2) {
      return true;
    }
    return false;
  }

  static bool checkIfClassEnableAspectd(List<Expression> annotations) {
    bool enabled = false;
    for (Expression annotation in annotations) {
      //Release Mode
      if (annotation is ConstantExpression) {
        final ConstantExpression constantExpression = annotation;
        final Constant constant = constantExpression.constant;
        if (constant is InstanceConstant) {
          final InstanceConstant instanceConstant = constant;
          final Class instanceClass = instanceConstant.classReference.node as Class;
          if (instanceClass.name == AopUtils.kAopAnnotationClassAspect &&
              AopUtils.kImportUriAopAspect == (instanceClass.parent as Library)?.importUri.toString()) {
            enabled = true;
            break;
          }
        }
      }
      //Debug Mode
      else if (annotation is ConstructorInvocation) {
        final ConstructorInvocation constructorInvocation = annotation;
        final Class cls = constructorInvocation.targetReference.node?.parent as Class;
        if (cls == null) {
          continue;
        }
        final Library library = cls.parent as Library;
        if (cls.name == AopUtils.kAopAnnotationClassAspect && library.importUri.toString() == AopUtils.kImportUriAopAspect) {
          enabled = true;
          break;
        }
      }
    }
    return enabled;
  }

  static Map<String, String> calcSourceInfo(Map<Uri, Source> uriToSource, Library library, int fileOffset) {
    final Map<String, String> sourceInfo = <String, String>{};
    String importUri = library.importUri.toString();
    final int idx = importUri.lastIndexOf('/');
    if (idx != -1) {
      importUri = importUri.substring(0, idx);
    }
    final Uri fileUri = library.fileUri;
    final Source source = uriToSource[fileUri];
    int lineNum;
    int lineOffSet;
    final int lineStartCnt = source.lineStarts.length;
    for (int i = 0; i < lineStartCnt; i++) {
      final int lineStartIdx = source.lineStarts[i];
      if (lineStartIdx <= fileOffset && (i == lineStartCnt - 1 || source.lineStarts[i + 1] > fileOffset)) {
        lineNum = i;
        lineOffSet = fileOffset - lineStartIdx;
        break;
      }
    }
    sourceInfo.putIfAbsent('library', () => importUri);
    sourceInfo.putIfAbsent('file', () => fileUri.toString());
    sourceInfo.putIfAbsent('lineNum', () => '${lineNum + 1}');
    sourceInfo.putIfAbsent('lineOffset', () => '$lineOffSet');
    return sourceInfo;
  }

  //创建 stub 方法，例如对于 _incrementCounter 方法，会创建一个 _incrementCounter_aop_stub_0 方法，此方法会将 _incrementCounter 中的方法体内容转移到这个代理方法中
  static Procedure createStubProcedure(
      Name methodName,
      AopItemInfo aopItemInfo,
      //示例：此处的 aopMember 值s为 SensorsAnalyticsAOP._incrementCounterTest 对应的 Procedure
      Procedure referProcedure,
      Statement bodyStatements,
      bool shouldReturn) {
    //referProcdure 为 _MyHomePageState._incrementCounter。bodyStatements 为原方法的方法体内容
    final FunctionNode functionNode = FunctionNode(bodyStatements, //构建代理方法
        typeParameters: deepCopyASTNodes<TypeParameter>(referProcedure.function.typeParameters),
        positionalParameters: referProcedure.function.positionalParameters,
        namedParameters: referProcedure.function.namedParameters,
        requiredParameterCount: referProcedure.function.requiredParameterCount,
        returnType: shouldReturn //根据原方法的情况构建返回值
            ? deepCopyASTNode(referProcedure.function.returnType)
            : const VoidType(),
        asyncMarker: referProcedure.function.asyncMarker,
        dartAsyncMarker: referProcedure.function.dartAsyncMarker);
    final Procedure procedure = Procedure(
      Name(methodName.text, methodName.library),
      ProcedureKind.Method,
      functionNode,
      isStatic: referProcedure.isStatic,
      fileUri: referProcedure.fileUri,
      stubKind: referProcedure.stubKind,
      stubTarget: referProcedure.stubTarget,
    );

    procedure.fileOffset = referProcedure.fileOffset;
    procedure.fileEndOffset = referProcedure.fileEndOffset;
    procedure.fileStartOffset = referProcedure.fileStartOffset;
    manipulatedProcedureSet.add(procedure);
    return procedure;
  }

  static Constructor createStubConstructor(
      Name methodName, AopItemInfo aopItemInfo, Constructor referConstructor, Statement bodyStatements, bool shouldReturn) {
    final FunctionNode functionNode = FunctionNode(bodyStatements,
        typeParameters: deepCopyASTNodes<TypeParameter>(referConstructor.function.typeParameters),
        positionalParameters: referConstructor.function.positionalParameters,
        namedParameters: referConstructor.function.namedParameters,
        requiredParameterCount: referConstructor.function.requiredParameterCount,
        returnType: shouldReturn ? deepCopyASTNode(referConstructor.function.returnType) : const VoidType(),
        asyncMarker: referConstructor.function.asyncMarker,
        dartAsyncMarker: referConstructor.function.dartAsyncMarker);
    final Constructor constructor = Constructor(functionNode,
        name: Name(methodName.text, methodName.library),
        isConst: referConstructor.isConst,
        isExternal: referConstructor.isExternal,
        isSynthetic: referConstructor.isSynthetic,
        initializers: deepCopyASTNodes(referConstructor.initializers),
        transformerFlags: referConstructor.transformerFlags,
        fileUri: referConstructor.fileUri,
        reference: Reference()..node = referConstructor.reference.node);

    constructor.fileOffset = referConstructor.fileOffset;
    constructor.fileEndOffset = referConstructor.fileEndOffset;
    constructor.startFileOffset = referConstructor.startFileOffset;
    return constructor;
  }

  static dynamic deepCopyASTNode(dynamic node, {bool isReturnType = false, bool ignoreGenerics = false}) {
    if (node is TypeParameter) {
      if (ignoreGenerics) return TypeParameter(node.name, node.bound, node.defaultType);
    }
    if (node is VariableDeclaration) {
      return VariableDeclaration(
        node.name,
        initializer: node.initializer,
        type: deepCopyASTNode(node.type),
        flags: node.flags,
        isFinal: node.isFinal,
        isConst: node.isConst,
        isInitializingFormal: node.isInitializingFormal,
        isCovariantByDeclaration: node.isCovariantByDeclaration,
        isLate: node.isLate,
        isRequired: node.isRequired,
        isLowered: node.isLowered,
      );
    }
    if (node is TypeParameterType) {
      if (isReturnType || ignoreGenerics) {
        return const DynamicType();
      }
      return TypeParameterType(deepCopyASTNode(node.parameter), node.nullability, deepCopyASTNode(node.promotedBound));
    }
    if (node is FunctionType) {
      return FunctionType(deepCopyASTNodes(node.positionalParameters), deepCopyASTNode(node.returnType, isReturnType: true), Nullability.legacy,
          namedParameters: deepCopyASTNodes(node.namedParameters),
          typeParameters: deepCopyASTNodes(node.typeParameters),
          requiredParameterCount: node.requiredParameterCount);
    }
    if (node is TypedefType) {
      return TypedefType(node.typedefNode, Nullability.legacy, deepCopyASTNodes(node.typeArguments, ignoreGeneric: ignoreGenerics));
    }
    return node;
  }

  static dynamic deepCopyASTNode2(dynamic node, {bool isReturnType = false, bool ignoreGenerics = false}) {
    if (node is TypeParameter) {
      if (ignoreGenerics) return TypeParameter(node.name, node.bound, pointCuntTargetField.type);
    }
    if (node is VariableDeclaration) {
      return VariableDeclaration(
        node.name,
        initializer: node.initializer,
        type: deepCopyASTNode2(node.type),
        flags: node.flags,
        isFinal: node.isFinal,
        isConst: node.isConst,
        isInitializingFormal: node.isInitializingFormal,
        isCovariantByDeclaration: node.isCovariantByDeclaration,
        isLate: node.isLate,
        isRequired: node.isRequired,
        isLowered: node.isLowered,
      );
    }
    if (node is TypeParameterType) {
      if (isReturnType || ignoreGenerics) {
        return pointCuntTargetField.type;
      }
      return TypeParameterType(deepCopyASTNode2(node.parameter), node.nullability, deepCopyASTNode2(node.promotedBound));
    }
    if (node is FunctionType) {
      return FunctionType(deepCopyASTNode2(node.positionalParameters), deepCopyASTNode2(node.returnType, isReturnType: true), Nullability.nonNullable,
          namedParameters: deepCopyASTNode2(node.namedParameters),
          typeParameters: deepCopyASTNode2(node.typeParameters),
          requiredParameterCount: node.requiredParameterCount);
    }
    if (node is TypedefType) {
      return TypedefType(node.typedefNode, Nullability.nonNullable, [pointCuntTargetField.type]);
    }
    return node;
  }

  static List<T> deepCopyASTNodes2<T>(List<T> nodes, {bool ignoreGeneric = false}) {
    final List<T> newNodes = <T>[];
    for (T node in nodes) {
      final dynamic newNode = deepCopyASTNode2(node, ignoreGenerics: ignoreGeneric);
      if (newNode != null) {
        newNodes.add(newNode);
      }
    }
    return newNodes;
  }

  static Arguments concatArguments4PointcutStubCall2(Member member) {
    final Arguments arguments = Arguments.empty();
    // int i = 0;
    // for (VariableDeclaration variableDeclaration
    // in member.function!.positionalParameters) {//此处是将 PointCut 中的 positionalParams 分别转换为不同的类型
    //   final Arguments getArguments = Arguments.empty();
    //   getArguments.positional.add(IntLiteral(i));
    //   final MethodInvocation methodInvocation = MethodInvocation(//示例：相当于调用 PointCut 的  this.positionalParams[i] as int
    //       PropertyGet(ThisExpression(), Name('positionalParams')),
    //       listGetProcedure!.name!,
    //       getArguments);
    //   final AsExpression asExpression = AsExpression(methodInvocation,
    //       deepCopyASTNode2(variableDeclaration.type, ignoreGenerics: true));
    //   arguments.positional.add(asExpression);
    //   i++;
    // }
    // final List<NamedExpression> namedEntries = <NamedExpression>[];
    // for (VariableDeclaration variableDeclaration
    // in member.function!.namedParameters) {
    //   final Arguments getArguments = Arguments.empty();
    //   getArguments.positional.add(StringLiteral(variableDeclaration.name!));
    //   final MethodInvocation methodInvocation = MethodInvocation(
    //       PropertyGet(ThisExpression(), Name('namedParams')),
    //       mapGetProcedure!.name!,
    //       getArguments);
    //   final AsExpression asExpression = AsExpression(methodInvocation,
    //       deepCopyASTNode2(variableDeclaration.type, ignoreGenerics: true));
    //   namedEntries.add(NamedExpression(variableDeclaration.name!, asExpression));//相当于 PointCut   this.namedParams["name"] as String
    // }
    // if (namedEntries.isNotEmpty) {
    //   arguments.named.addAll(namedEntries);
    // }
    return arguments;
  }

  static FunctionType computeFunctionTypeForFunctionNode(FunctionNode functionNode, Arguments arguments) {
    final List<DartType> positionDartType = [];
    arguments.positional.forEach((element) {
      if (element is AsExpression) {
        positionDartType.add(element.type);
      }
    });

    final List<NamedType> namedDartType = [];
    arguments.named.forEach((element) {
      Expression value = element.value;
      if (value is AsExpression) {
        namedDartType.add(NamedType(element.name, value.type));
      }
    });
    FunctionType functionType = new FunctionType(
        positionDartType, deepCopyASTNode(functionNode.returnType, isReturnType: true, ignoreGenerics: true), Nullability.nonNullable,
        namedParameters: namedDartType, typeParameters: [], requiredParameterCount: functionNode.requiredParameterCount);
    return functionType;
  }

  static List<T> deepCopyASTNodes<T>(List<T> nodes, {bool ignoreGeneric = false}) {
    final List<T> newNodes = <T>[];
    for (T node in nodes) {
      final dynamic newNode = deepCopyASTNode(node, ignoreGenerics: ignoreGeneric);
      if (newNode != null) {
        newNodes.add(newNode);
      }
    }
    return newNodes;
  }

  static Arguments argumentsFromFunctionNode(FunctionNode functionNode) {
    final List<Expression> positional = <Expression>[];
    final List<NamedExpression> named = <NamedExpression>[];
    for (VariableDeclaration variableDeclaration in functionNode.positionalParameters) {
      positional.add(VariableGet(variableDeclaration));
    }
    for (VariableDeclaration variableDeclaration in functionNode.namedParameters) {
      named.add(NamedExpression(variableDeclaration.name, VariableGet(variableDeclaration)));
    }
    return Arguments(positional, named: named);
  }

  static String nameForConstructor(Constructor constructor) {
    final Class constructorCls = constructor.parent as Class;
    String constructorName = '${constructorCls.name}';
    if (constructor.name.text.isNotEmpty) {
      constructorName += '.${constructor.name.text}';
    }
    return constructorName;
  }
}
