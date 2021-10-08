import 'package:kernel/ast.dart';
import 'package:front_end/src/fasta/kernel/internal_ast.dart';
import 'package:vm/target/flutter.dart';

class MyTransformer extends FlutterProgramTransformer {
  Procedure? testPageProcedure;
  Class? stateClazz;
  DartType? intType;

  @override
  void transform(Component component) {
    final List<Library> libraries = component.libraries;
    if (libraries.isEmpty) {
      return;
    }
    _prepare(component);

    //第二遍正式开始处理
    for (Library library in libraries) {
      if (library.importUri.toString() == 'package:testdemo/main_old.dart') {
        List<Class> classList = library.classes;
        for (Class clazz in classList) {
          if (clazz.name == 'PointCutMock') {
            _doTransform(clazz);
          }
        }
        break;
      }
    }
  }

  void _prepare(Component component) {
    // final List<Library> libraries = component.libraries;
    // if (libraries.isEmpty) {
    //   return;
    // }
    // //做一些前期准备工作，用于获取一些值
    // for (Library library in libraries) {
    //   if (library.importUri.toString() == 'package:testdemo/main_old.dart') {
    //     List<Class> classList = library.classes;
    //     for (Class clazz in classList) {
    //       if (clazz.name == '_MyHomePageState') {
    //         List<Procedure> procedureList = clazz.procedures;
    //         for (Procedure procedure in procedureList) {
    //           if (procedure.name.text == 'testTypeParams') {
    //             testPageProcedure = procedure;
    //             stateClazz = clazz;
    //
    //             stateClazz!.fields.forEach((element) {
    //               if(element.name.text == '_counter'){
    //                 intType = element.type;
    //               }
    //             });
    //           }
    //         }
    //       }
    //     }
    //     break;
    //   }
    // }
  }

  void _doTransform(Class clazz) {
    // List<Procedure> procedureList = clazz.procedures;
    // Field? targetField;
    //
    // List<Field> fields = clazz.fields;
    // fields.forEach((field) {
    //   if(field.name.text == 'target'){
    //     targetField = field;
    //   }
    // });
    //
    // for (Procedure procedure in procedureList) {
    //   if (procedure.name.text == 'proceed') {
    //     Block bodyBlock = procedure.function.body as Block;
    //
    //     InstanceGet instanceGet = InstanceGet.byReference(InstanceAccessKind.Instance,
    //         ThisExpression(),
    //         Name("target"),
    //         interfaceTargetReference: targetField!.getterReference,
    //         resultType: targetField!.getterType);
    //     AsExpression asExpression = AsExpression(instanceGet, InterfaceType(stateClazz!, Nullability.nonNullable));
    //
    //     Arguments arguments = Arguments.empty();
    //     arguments.positional.add(IntJudgment(101, "101"));
    //
    //     ArgumentsImpl argumentsImpl = ArgumentsImpl(<Expression>[IntJudgment(101, "101")], types:<DartType>[intType!], named:<NamedExpression>[]);
    //     InstanceInvocation mockedInstanceInvocation = InstanceInvocation(
    //         InstanceAccessKind.Instance,
    //         asExpression,
    //         testPageProcedure!.name,
    //         argumentsImpl,
    //         interfaceTarget: testPageProcedure!,
    //         functionType: computeFunctionTypeForFunctionNode(testPageProcedure!.function, argumentsImpl));
    //     mockedInstanceInvocation.parent = bodyBlock;
    //
    //     ExpressionStatement statement = new ExpressionStatement(mockedInstanceInvocation);
    //     bodyBlock.statements.add(statement);
    //     print("====addd====");
    //   }
    // }
  }

  static FunctionType computeFunctionTypeForFunctionNode(FunctionNode functionNode, Arguments arguments) {
    final List<DartType> positionDartType = [];
    arguments.types.forEach((element) {
      positionDartType.add(element);
    });

    List<VariableDeclaration> namedParams = functionNode.namedParameters;
    final List<NamedType> namedDartType = [];
    namedParams.forEach((element) {
      namedDartType.add(NamedType(element.name!, element.type));
    });
    FunctionType functionType = new FunctionType(
        positionDartType,
        functionNode.returnType,
        Nullability.nonNullable,
        namedParameters: namedDartType,
        typeParameters: [],
        requiredParameterCount: functionNode.requiredParameterCount
    );
    return functionType;
  }
}
