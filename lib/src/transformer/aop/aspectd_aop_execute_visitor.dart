import 'package:kernel/ast.dart';

import 'aop_iteminfo.dart';
import 'aop_utils.dart';
import 'package:kernel/type_algebra.dart';

class AspectdAopExecuteVisitor extends RecursiveVisitor<void> {
  AspectdAopExecuteVisitor(this._aopItemInfoList);
  final List<AopItemInfo> _aopItemInfoList;

  @override
  void visitLibrary(Library library) {
    String importUri = library.importUri.toString();
    bool matches = false;
    int aopItemInfoListLen = _aopItemInfoList.length;
    for (int i = 0; i < aopItemInfoListLen && !matches; i++) {//查询当前的 Library 中的 dart 文件是否有符合 AOP 中定义的 Hook 点
      AopItemInfo aopItemInfo = _aopItemInfoList[i];
      if ((aopItemInfo.isRegex &&
              RegExp(aopItemInfo.importUri).hasMatch(importUri)) ||
          (!aopItemInfo.isRegex && importUri == aopItemInfo.importUri)) {//此处的 importUri 例子：package:testdemo/main_old.dart
        matches = true;
        break;
      }
    }
    if (matches) {//如果查找到
      library.visitChildren(this);//开始访问此 Library 中的元素
    }
  }

  @override
  void visitClass(Class cls) {
    String clsName = cls.name;
    bool matches = false;
    int aopItemInfoListLen = _aopItemInfoList.length;
    for (int i = 0; i < aopItemInfoListLen && !matches; i++) {
      AopItemInfo aopItemInfo = _aopItemInfoList[i];
      if ((aopItemInfo.isRegex &&
              RegExp(aopItemInfo.clsName).hasMatch(clsName)) ||
          (!aopItemInfo.isRegex && clsName == aopItemInfo.clsName)) {//判断当前的类是否在 AOPItem 中找到
        matches = true;
        break;
      }
    }
    if (matches) {
      cls.visitChildren(this);//如果找到对应类，就继续查找其中的方法
    }
  }

  @override
  void visitProcedure(Procedure node) {
    String procedureName = node.name.text;
    AopItemInfo matchedAopItemInfo;
    int aopItemInfoListLen = _aopItemInfoList.length;
    for (int i = 0; i < aopItemInfoListLen && matchedAopItemInfo == null; i++) {
      AopItemInfo aopItemInfo = _aopItemInfoList[i];
      if ((aopItemInfo.isRegex &&
              RegExp(aopItemInfo.methodName).hasMatch(procedureName)) ||
          (!aopItemInfo.isRegex && procedureName == aopItemInfo.methodName)) {//查看类中的所有方法，将其与 AOPItem 进行对比，确认是否是需要处理的方法
        matchedAopItemInfo = aopItemInfo;
        break;
      }
    }
    if (matchedAopItemInfo == null) {
      return;
    }
    if (node.isStatic) {
      if (node.parent is Library) {
        transformStaticMethodProcedure(
            node.parent as Library, matchedAopItemInfo, node);
      } else if (node.parent is Class) {
        transformStaticMethodProcedure(
            node.parent.parent as Library, matchedAopItemInfo, node);
      }
    } else {
      if (node.parent != null) {
        transformInstanceMethodProcedure(
            node.parent.parent as Library, matchedAopItemInfo, node);
      }
    }
  }

  void transformStaticMethodProcedure(Library originalLibrary,
      AopItemInfo aopItemInfo, Procedure originalProcedure) {
    if (AopUtils.manipulatedProcedureSet.contains(originalProcedure)) {
      return;
    }
    final FunctionNode functionNode = originalProcedure.function;
    final Statement body = functionNode.body;
    final bool shouldReturn =
        !(originalProcedure.function.returnType is VoidType);

    final String stubKey =
        '${AopUtils.kAopStubMethodPrefix}${AopUtils.kPrimaryKeyAopMethod}';
    AopUtils.kPrimaryKeyAopMethod++;

    //目标新建stub函数，方便完成目标->aopstub->目标stub链路
    final Procedure originalStubProcedure = AopUtils.createStubProcedure(
        Name(originalProcedure.name.text + '_' + stubKey,
            originalProcedure.name.library),
        aopItemInfo,
        originalProcedure,
        body,
        shouldReturn);
    final Node parent = originalProcedure.parent;
    String parentIdentifier;
    if (parent is Library) {
      parent.procedures.add(originalStubProcedure);
      parentIdentifier = parent.importUri.toString();
    } else if (parent is Class) {
      parent.procedures.add(originalStubProcedure);
      parentIdentifier = parent.name;
    }
    functionNode.body = createPointcutCallFromOriginal(
        originalLibrary,
        aopItemInfo,
        stubKey,
        StringLiteral(parentIdentifier),
        originalProcedure,
        AopUtils.argumentsFromFunctionNode(functionNode),
        shouldReturn);

    //Pointcut类中新增stub，并且添加调用
    final Library pointcutLibrary =
        AopUtils.pointCutProceedProcedure.parent.parent as Library;
    final Class pointcutClass = AopUtils.pointCutProceedProcedure.parent as Class;
    AopUtils.insertLibraryDependency(pointcutLibrary, originalLibrary);

    final StaticInvocation staticInvocation = StaticInvocation(
        originalStubProcedure,
        AopUtils.concatArguments4PointcutStubCall(originalProcedure),
        isConst: originalStubProcedure.isConst);

    final Procedure stubProcedureNew = AopUtils.createStubProcedure(
        Name(stubKey, AopUtils.pointCutProceedProcedure.name.library),
        aopItemInfo,
        AopUtils.pointCutProceedProcedure,
        AopUtils.createProcedureBodyWithExpression(
            staticInvocation, shouldReturn),
        shouldReturn);
    pointcutClass.procedures.add(stubProcedureNew);
    AopUtils.insertProceedBranch(stubProcedureNew, shouldReturn);
  }
  //例如现在开始处理 _MyHomePageState 的 _incrementCounter 方法，步骤是：
  //1.创建原方法的代理方法，并将原方法中的方法体内容转移到代理方法中
  //2.在原方法中调用 AOP 类中的方法，并构建 PointCut，new SensorsAnalyticsAOP()._incrementCounterTest(PointCut)
  //3.在 PointCut 类中创建 aop_stub_0 方法，此方法体为：(this.target as _MyHomePageState)._incrementCounter_aop_stub_0()
  //4.修改 PointCut proceed 方法，在其中添加 if 判断
  void transformInstanceMethodProcedure(Library originalLibrary,
      AopItemInfo aopItemInfo, Procedure originalProcedure) {
    if (AopUtils.manipulatedProcedureSet.contains(originalProcedure)) {//如果已经处理完过，就直接返回
      return;
    }
    final FunctionNode functionNode = originalProcedure.function;//FunctionNode 中定义了方法的参数和、body、返回值类型等
    final Class originalClass = originalProcedure.parent as Class;
    final Statement body = functionNode.body;
    if (body == null) {
      return;
    }
    final bool shouldReturn =
        !(originalProcedure.function.returnType is VoidType);

    final String stubKey =
        '${AopUtils.kAopStubMethodPrefix}${AopUtils.kPrimaryKeyAopMethod}';//例如：aop_stub_0
    AopUtils.kPrimaryKeyAopMethod++;

    //原始方法中的方法体内容转移到 proxy 方法中，创建元方法对应的代理方法，例如 _incrementCounter_aop_stub_0
    final Procedure originalStubProcedure = AopUtils.createStubProcedure(
        Name(originalProcedure.name.text + '_' + stubKey,
            originalProcedure.name.library),
        aopItemInfo,
        originalProcedure,
        body,
        shouldReturn);
    originalClass.procedures.add(originalStubProcedure);
    functionNode.body = createPointcutCallFromOriginal(//将原方法_incrementCounter中的内容，使用 new SensorsAnalyticsAOP()._incrementCounterTest(PointCut) 这样的方法体替换掉
        originalLibrary,
        aopItemInfo,
        stubKey,
        ThisExpression(),
        originalProcedure,
        AopUtils.argumentsFromFunctionNode(functionNode),
        shouldReturn);

    //Pointcut类中新增stub，并且添加调用
    final Library pointcutLibrary =
        AopUtils.pointCutProceedProcedure.parent.parent as Library;
    final Class pointcutClass = AopUtils.pointCutProceedProcedure.parent as Class;
    AopUtils.insertLibraryDependency(pointcutLibrary, originalLibrary);//pointcut.dart 中依赖 main_old.dart，

    InstanceGet instanceGet = InstanceGet.byReference(InstanceAccessKind.Instance,
        ThisExpression(),
        Name("target"),
        interfaceTargetReference: AopUtils.pointCuntTargetField.getterReference,
        resultType: AopUtils.pointCuntTargetField.type);
    AsExpression asExpression = AsExpression(instanceGet, InterfaceType(originalClass, Nullability.nonNullable));

    Arguments arguments = AopUtils.concatArguments4PointcutStubCall(originalProcedure);// originalProcedure 中包含了需要的各种参数信息
    InstanceInvocation mockedInstanceInvocation = InstanceInvocation(//mockedInvocation 相当于 (this.target as _MyHomePageState)._incrementCounter_aop_stub_0()
        InstanceAccessKind.Instance,
        asExpression,
        originalStubProcedure.name,
        arguments,
        interfaceTarget: originalStubProcedure,
        functionType: AopUtils.computeFunctionTypeForFunctionNode(functionNode, arguments));

    //在 PointCut 中创建 aop_stub_0 方法，此方法体为 (this.target as _MyHomePageState)._incrementCounter_aop_stub_0()
    final Procedure stubProcedureNew = AopUtils.createStubProcedure(
        Name(stubKey, AopUtils.pointCutProceedProcedure.name.library),//创建 aop_stub_0
        aopItemInfo,
        AopUtils.pointCutProceedProcedure,
        AopUtils.createProcedureBodyWithExpression(
            mockedInstanceInvocation, shouldReturn),
        shouldReturn);
    pointcutClass.procedures.add(stubProcedureNew);//添加到 PointCut 类中
    AopUtils.insertProceedBranch(stubProcedureNew, shouldReturn);
  }
  //创建 new SensorsAnalyticsAOP()._incrementCounterTest(PointCut) 这样的方法体
  Block createPointcutCallFromOriginal(
      Library library,
      AopItemInfo aopItemInfo,
      String stubKey,
      Expression targetExpression,
      Member member,
      Arguments arguments,
      bool shouldReturn) {
    AopUtils.insertLibraryDependency(//当前的 Library 中添加依赖，例如 testdemo/main_old.dart 中添加，sa_aspectd_impl/sensorsdata_aop_impl.dart
        library, aopItemInfo.aopMember.parent.parent as Library);
    final Arguments redirectArguments = Arguments.empty();//AOP 代码的参数，例如 AOP._hookClick(PointCut) 方法的参数
    AopUtils.concatArgumentsForAopMethod(
        null, redirectArguments, stubKey, targetExpression, member, arguments);
    Expression callExpression;
    if (aopItemInfo.aopMember is Procedure) {
      final Procedure procedure = aopItemInfo.aopMember as Procedure;
      if (procedure.isStatic) {
        callExpression =
            StaticInvocation(aopItemInfo.aopMember as Procedure, redirectArguments);
      } else {
        final Class aopItemMemberCls = aopItemInfo.aopMember.parent as Class;//获取到 SensorsAnalyticsAOP 这个 Class
        final ConstructorInvocation redirectConstructorInvocation =
            ConstructorInvocation.byReference(
                aopItemMemberCls.constructors.first.reference,//SensorsAnalyticsAOP. 构造方法对应的 reference
                Arguments(<Expression>[]));//无参构造方法

        callExpression = InstanceInvocation(
            InstanceAccessKind.Instance,
            redirectConstructorInvocation,
            aopItemInfo.aopMember.name,
            redirectArguments,
            interfaceTarget: aopItemInfo.aopMember as Procedure,
            functionType: AopUtils.computeFunctionTypeForFunctionNode((aopItemInfo.aopMember as Procedure).function, arguments));

        // callExpression = MethodInvocation(redirectConstructorInvocation,//相当于 new SensorsAnalyticsAOP()._incrementCounterTest(PointCut)
        //     aopItemInfo.aopMember!.name!, redirectArguments);//此处的 redirectArguments 示例：Arguments((new PointCut(<dynamic, dynamic>{}, this, "_incrementCounter", "aop_stub_0", <dynamic>[], <dynamic, dynamic>{})))
      }
    }
    return AopUtils.createProcedureBodyWithExpression(
        callExpression, shouldReturn);
  }

  @override
  void defaultMember(Member node) {}
}
