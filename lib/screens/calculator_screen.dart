import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  String _display = '0';
  double? _firstOperand;
  String? _operator; // '+', '-', '×', '÷', '^'
  bool _isNewEntry = true; // start fresh after operator/equals
  bool _useDegrees = true; // trig mode

  void _inputDigit(String d) {
    setState(() {
      if (_isNewEntry) {
        _display = d == '.' ? '0.' : d;
        _isNewEntry = false;
      } else {
        if (d == '.') {
          if (!_display.contains('.')) _display += '.';
        } else {
          _display = _display == '0' ? d : _display + d;
        }
      }
    });
  }

  void _toggleSign() {
    setState(() {
      if (_display.startsWith('-')) {
        _display = _display.substring(1);
      } else if (_display != '0') {
        _display = '-$_display';
      }
    });
  }

  void _backspace() {
    setState(() {
      if (_isNewEntry) return;
      if (_display.length <= 1 || (_display.length == 2 && _display.startsWith('-'))) {
        _display = '0';
        _isNewEntry = true;
      } else {
        _display = _display.substring(0, _display.length - 1);
      }
    });
  }

  void _clear() {
    setState(() {
      _display = '0';
      _firstOperand = null;
      _operator = null;
      _isNewEntry = true;
    });
  }

  void _setOperator(String op) {
    setState(() {
      _firstOperand = double.tryParse(_display) ?? 0.0;
      _operator = op;
      _isNewEntry = true;
    });
  }

  void _percent() {
    // percentage of current value
    setState(() {
      final v = double.tryParse(_display) ?? 0.0;
      _display = _format(v / 100.0);
    });
  }

  void _equals() {
    setState(() {
      if (_firstOperand == null || _operator == null) return;
      final b = double.tryParse(_display) ?? 0.0;
      double res = 0.0;
      switch (_operator) {
        case '+':
          res = _firstOperand! + b;
          break;
        case '−':
        case '-':
          res = _firstOperand! - b;
          break;
        case '×':
        case '*':
          res = _firstOperand! * b;
          break;
        case '÷':
        case '/':
          res = b == 0 ? double.nan : _firstOperand! / b;
          break;
        case '^':
          res = math.pow(_firstOperand!, b).toDouble();
          break;
        default:
          res = b;
      }
      _display = _format(res);
      _firstOperand = null;
      _operator = null;
      _isNewEntry = true;
    });
  }

  void _applyUnary(String fn) {
    setState(() {
      double v = double.tryParse(_display) ?? 0.0;
      switch (fn) {
        case '√':
          v = v < 0 ? double.nan : math.sqrt(v);
          break;
        case 'x²':
          v = v * v;
          break;
        case '1/x':
          v = v == 0 ? double.nan : 1 / v;
          break;
        case 'sin':
          v = math.sin(_useDegrees ? v * math.pi / 180.0 : v);
          break;
        case 'cos':
          v = math.cos(_useDegrees ? v * math.pi / 180.0 : v);
          break;
        case 'tan':
          v = math.tan(_useDegrees ? v * math.pi / 180.0 : v);
          break;
        case 'log':
          v = v <= 0 ? double.nan : (math.log(v) / math.ln10);
          break;
        case 'ln':
          v = v <= 0 ? double.nan : math.log(v);
          break;
        case 'abs':
          v = v.abs();
          break;
        case 'π':
          v = math.pi;
          break;
        case 'e':
          v = math.e;
          break;
      }
      _display = _format(v);
      _isNewEntry = true;
    });
  }

  String _format(double v) {
    if (v.isNaN || v.isInfinite) return 'Error';
    String s = v.toStringAsFixed(10);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  String _expressionText() {
    if (_firstOperand == null || _operator == null) return '';
    final left = _format(_firstOperand!);
    final right = _isNewEntry ? '' : _display;
    return right.isEmpty ? '$left $_operator' : '$left $_operator $right';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.calculator),
        actions: [
          Row(
            children: [
              Text(_useDegrees ? 'DEG' : 'RAD', style: t.textTheme.labelMedium),
              Switch(
                value: _useDegrees,
                onChanged: (v) => setState(() => _useDegrees = v),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 520;
          final buttonHeight = isWide ? 64.0 : 56.0;
          final displayStyle = t.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          );

          Widget display = Card(
            elevation: 1.5,
            color: t.colorScheme.surface,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: t.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Expression line
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _expressionText().isEmpty ? 0.0 : 0.75,
                    child: Text(
                      _expressionText(),
                      textAlign: TextAlign.right,
                      style: t.textTheme.titleMedium?.copyWith(
                        color: t.colorScheme.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                  // Result line (scrollable for long numbers)
                  SizedBox(height: _expressionText().isEmpty ? 0 : 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Text(
                      _display,
                      textAlign: TextAlign.right,
                      style: displayStyle,
                    ),
                  ),
                ],
              ),
            ),
          );

          List<List<_Btn>> sci = [
            [
              _Btn('sin', onTap: () => _applyUnary('sin')),
              _Btn('cos', onTap: () => _applyUnary('cos')),
              _Btn('tan', onTap: () => _applyUnary('tan')),
              _Btn('√', onTap: () => _applyUnary('√')),
            ],
            [
              _Btn('ln', onTap: () => _applyUnary('ln')),
              _Btn('log', onTap: () => _applyUnary('log')),
              _Btn('x²', onTap: () => _applyUnary('x²')),
              _Btn('1/x', onTap: () => _applyUnary('1/x')),
            ],
            [
              _Btn('π', onTap: () => _applyUnary('π')),
              _Btn('e', onTap: () => _applyUnary('e')),
              _Btn('%', onTap: _percent),
              _Btn('^', color: t.colorScheme.primary, onTap: () => _setOperator('^')),
            ],
          ];

          List<List<_Btn>> basic = [
            [
              _Btn('C', color: t.colorScheme.error, onTap: _clear),
              _Btn('⌫', onTap: _backspace),
              _Btn('%', onTap: _percent),
              _Btn('÷', color: t.colorScheme.primary, onTap: () => _setOperator('÷')),
            ],
            [
              _Btn('7', onTap: () => _inputDigit('7')),
              _Btn('8', onTap: () => _inputDigit('8')),
              _Btn('9', onTap: () => _inputDigit('9')),
              _Btn('×', color: t.colorScheme.primary, onTap: () => _setOperator('×')),
            ],
            [
              _Btn('4', onTap: () => _inputDigit('4')),
              _Btn('5', onTap: () => _inputDigit('5')),
              _Btn('6', onTap: () => _inputDigit('6')),
              _Btn('−', color: t.colorScheme.primary, onTap: () => _setOperator('−')),
            ],
            [
              _Btn('1', onTap: () => _inputDigit('1')),
              _Btn('2', onTap: () => _inputDigit('2')),
              _Btn('3', onTap: () => _inputDigit('3')),
              _Btn('+', color: t.colorScheme.primary, onTap: () => _setOperator('+')),
            ],
            [
              _Btn('±', onTap: _toggleSign),
              _Btn('0', onTap: () => _inputDigit('0')),
              _Btn('.', onTap: () => _inputDigit('.')),
              _Btn('=', color: t.colorScheme.secondary, onTap: _equals),
            ],
          ];

          Widget grid(List<List<_Btn>> rows) => Column(
                children: rows
                    .map((r) => Row(
                          children: r
                              .map((b) => Expanded(child: _CalculatorButton(b: b, height: buttonHeight)))
                              .toList(),
                        ))
                    .toList(),
              );

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  display,
                  const SizedBox(height: 12),
                  if (isWide) grid(sci),
                  if (isWide) const SizedBox(height: 12),
                  grid(basic),
                  if (!isWide) ...[
                    const SizedBox(height: 12),
                    ExpansionTile(
                      title: const Text('Scientific Functions'),
                      children: [Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: grid(sci),
                      )],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Btn {
  final String label;
  final Color? color;
  final VoidCallback onTap;
  _Btn(this.label, {this.color, required this.onTap});
}

class _CalculatorButton extends StatelessWidget {
  final _Btn b;
  final double height;
  const _CalculatorButton({required this.b, required this.height});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isPrimary = b.color != null;
    final bg = isPrimary ? b.color! : t.colorScheme.surfaceVariant;
    final fg = isPrimary ? t.colorScheme.onPrimary : t.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: SizedBox(
        height: height,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            elevation: isPrimary ? 1.0 : 0.0,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: t.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            overlayColor: fg.withOpacity(0.12),
          ),
          onPressed: b.onTap,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              b.label,
              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}