import 'package:math_expressions/math_expressions.dart';

class FormulaEngine {
  static double evaluate(String formula, Map<String, double> values) {
    try {
      Parser p = Parser();
      Expression exp = p.parse(formula);

      ContextModel cm = ContextModel();
      values.forEach((key, value) {
        // Replace spaces in column names for math_expressions compatibility if needed
        // For now, we assume simple identifiers or use a replacement strategy
        cm.bindVariable(Variable(key), Number(value));
      });

      return exp.evaluate(EvaluationType.REAL, cm);
    } catch (e) {
      print('Formula Evaluation Error: $e');
      return 0.0;
    }
  }

  /// Extracts variable names from a formula to identify dependencies
  static List<String> extractVariables(String formula) {
    // This is a simplified regex, real excel formulas might need better parsing
    final regex = RegExp(r'[a-zA-Z_][a-zA-Z0-9_]*');
    return regex.allMatches(formula).map((m) => m.group(0)!).toList();
  }
}
