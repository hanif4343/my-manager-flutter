import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../widgets/app_theme.dart';

class PinScreen extends StatefulWidget {
  final bool isSetup; // true = set new PIN, false = verify
  final VoidCallback? onSuccess;
  const PinScreen({super.key, this.isSetup = false, this.onSuccess});
  @override State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  String _entered = '';
  String _firstPin = '';
  bool _isConfirm = false;
  String _error = '';

  void _onKey(String key) {
    if (_entered.length >= 4) return;
    setState(() { _entered += key; _error = ''; });
    if (_entered.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), _check);
    }
  }

  void _onDelete() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _check() async {
    if (widget.isSetup) {
      if (!_isConfirm) {
        setState(() { _firstPin = _entered; _entered = ''; _isConfirm = true; });
      } else {
        if (_entered == _firstPin) {
          await SettingsService.setPin(_entered);
          widget.onSuccess?.call();
          if (mounted) Navigator.pop(context);
        } else {
          setState(() { _entered = ''; _firstPin = ''; _isConfirm = false;
            _error = 'PIN মিলেনি! আবার চেষ্টা করো।'; });
        }
      }
    } else {
      if (_entered == SettingsService.pin) {
        widget.onSuccess?.call();
        if (mounted) Navigator.pop(context);
      } else {
        setState(() { _entered = ''; _error = 'ভুল PIN!'; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isSetup
        ? (_isConfirm ? 'PIN নিশ্চিত করো' : 'নতুন PIN সেট করো')
        : 'PIN দিয়ে খোলো';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 60),
          const Text('🔐', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(
              color: AppTheme.textPrimary, fontSize: 22,
              fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('My Manager', style: const TextStyle(
              color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 40),

          // PIN dots
          Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _entered.length
                      ? AppTheme.accent : AppTheme.bg3,
                  border: Border.all(
                      color: i < _entered.length
                          ? AppTheme.accent : AppTheme.border, width: 2),
                ),
              ))),

          const SizedBox(height: 16),
          if (_error.isNotEmpty)
            Text(_error, style: const TextStyle(
                color: AppTheme.red, fontSize: 13)),

          const SizedBox(height: 40),

          // Numpad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(children: [
              for (var row in [['1','2','3'],['4','5','6'],['7','8','9'],['','0','⌫']])
                Row(children: row.map((k) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: k.isEmpty
                        ? const SizedBox()
                        : GestureDetector(
                            onTap: () => k == '⌫' ? _onDelete() : _onKey(k),
                            child: Container(
                              height: 64,
                              decoration: BoxDecoration(
                                color: k == '⌫' ? AppTheme.bg3 : AppTheme.bg2,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Center(child: k == '⌫'
                                  ? const Icon(Icons.backspace_outlined,
                                      color: AppTheme.textSecondary, size: 22)
                                  : Text(k, style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 24, fontWeight: FontWeight.w600))),
                            ),
                          ),
                  ),
                )).toList()),
            ]),
          ),

          if (!widget.isSetup) ...[
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('বাতিল',
                  style: TextStyle(color: AppTheme.textSecondary)),
            ),
          ],
        ]),
      ),
    );
  }
}
