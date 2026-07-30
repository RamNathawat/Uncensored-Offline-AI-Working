import 'dart:mirrors';
import 'package:llamadart/llamadart.dart';

void main() {
  var cm = reflectClass(GenerationParams);
  for (var decl in cm.declarations.values) {
    if (decl is VariableMirror) {
      print(MirrorSystem.getName(decl.simpleName));
    }
  }
}
