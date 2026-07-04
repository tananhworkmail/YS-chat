import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../theme/app_theme.dart';

enum _AuthMode { login, register, forgot }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _useridController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullnameController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _idSuffixController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _idCardController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _error = '';
  bool _localLoading = false;

  @override
  void dispose() {
    _useridController.dispose();
    _passwordController.dispose();
    _fullnameController.dispose();
    _confirmPasswordController.dispose();
    _idSuffixController.dispose();
    _birthdayController.dispose();
    _idCardController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = '');
    switch (_mode) {
      case _AuthMode.login:
        await _login();
      case _AuthMode.register:
        await _register();
      case _AuthMode.forgot:
        await _forgotPassword();
    }
  }

  Future<void> _login() async {
    final state = context.read<AppState>();
    try {
      await state.login(
          _useridController.text.trim(), _passwordController.text);
    } catch (err) {
      _showError(_friendlyError(err, fallback: 'Dang nhap khong thanh cong'));
    }
  }

  Future<void> _register() async {
    final userid = _useridController.text.trim();
    final fullname = _fullnameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    final idSuffix = _idSuffixController.text.trim();

    if (userid.isEmpty ||
        fullname.isEmpty ||
        password.isEmpty ||
        idSuffix.isEmpty) {
      _showError('Vui long nhap day du thong tin');
      return;
    }
    if (!RegExp(r'^\d{5}$').hasMatch(idSuffix)) {
      _showError('So cuoi CCCD phai gom 5 chu so');
      return;
    }
    if (password != confirm) {
      _showError('Mat khau xac nhan khong khop');
      return;
    }

    await _runLocalAction(() async {
      await context.read<AppState>().apiClient.register(
            userid: userid,
            fullname: fullname,
            password: password,
            idCardSuffix: idSuffix,
          );
      if (!mounted) return;
      _switchMode(_AuthMode.login);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Dang ky thanh cong. Vui long dang nhap.')),
      );
    }, fallback: 'Dang ky khong thanh cong');
  }

  Future<void> _forgotPassword() async {
    final userid = _useridController.text.trim();
    final fullname = _fullnameController.text.trim();
    final birthday = _birthdayController.text.trim();
    final idCard = _idCardController.text.trim();

    if (userid.isEmpty ||
        fullname.isEmpty ||
        birthday.isEmpty ||
        idCard.isEmpty) {
      _showError('Vui long nhap day du thong tin xac minh');
      return;
    }

    await _runLocalAction(() async {
      await context.read<AppState>().apiClient.forgotPassword(
            userid: userid,
            fullname: fullname,
            birthday: birthday,
            idCard: idCard,
          );
      if (!mounted) return;
      _switchMode(_AuthMode.login);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Xac minh thanh cong. Vui long kiem tra mat khau moi.')),
      );
    }, fallback: 'Xac minh khong thanh cong');
  }

  Future<void> _runLocalAction(Future<void> Function() action,
      {required String fallback}) async {
    setState(() => _localLoading = true);
    try {
      await action();
    } catch (err) {
      _showError(_friendlyError(err, fallback: fallback));
    } finally {
      if (mounted) setState(() => _localLoading = false);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: now,
    );
    if (selected == null) return;
    _birthdayController.text =
        '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
  }

  void _switchMode(_AuthMode mode) {
    setState(() {
      _mode = mode;
      _error = '';
      if (mode == _AuthMode.login) {
        _confirmPasswordController.clear();
        _idSuffixController.clear();
        _birthdayController.clear();
        _idCardController.clear();
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _friendlyError(Object err, {required String fallback}) {
    if (err is DioException) {
      final data = err.response?.data;
      if (data is Map && data['error'] != null) return '${data['error']}';
      if (err.type == DioExceptionType.connectionTimeout ||
          err.type == DioExceptionType.receiveTimeout) {
        return 'Ket noi qua thoi gian cho';
      }
      if (err.response == null) return 'Khong ket noi duoc may chu';
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final stateLoading = context.select((AppState state) => state.loading);
    final loading = stateLoading || _localLoading;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffe8fbff), Color(0xfff7fafc), Color(0xffeef7fb)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _AuthBrandHeader(),
                        const SizedBox(height: 22),
                        _AuthModeTabs(mode: _mode, onChanged: _switchMode),
                        const SizedBox(height: 20),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _buildForm(loading),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool loading) {
    return Column(
      key: ValueKey(_mode),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FormHeader(mode: _mode),
        const SizedBox(height: 16),
        TextField(
          controller: _useridController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Ma nhan vien',
            hintText: 'Nhap ma nhan vien',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        if (_mode != _AuthMode.login) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _fullnameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Ho ten',
              hintText: 'Nhap ho ten',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
        ],
        if (_mode == _AuthMode.forgot) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _birthdayController,
            readOnly: true,
            onTap: _pickBirthday,
            decoration: const InputDecoration(
              labelText: 'Ngay sinh',
              hintText: 'YYYY-MM-DD',
              prefixIcon: Icon(Icons.event_outlined),
              suffixIcon: Icon(Icons.calendar_month_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _idCardController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => loading ? null : _submit(),
            decoration: const InputDecoration(
              labelText: 'CCCD',
              hintText: 'Nhap so CCCD',
              prefixIcon: Icon(Icons.verified_user_outlined),
            ),
          ),
        ] else ...[
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: _mode == _AuthMode.login
                ? TextInputAction.done
                : TextInputAction.next,
            onSubmitted: (_) =>
                _mode == _AuthMode.login && !loading ? _submit() : null,
            decoration: InputDecoration(
              labelText: 'Mat khau',
              hintText: 'Nhap mat khau',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Hien mat khau' : 'An mat khau',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
              ),
            ),
          ),
        ],
        if (_mode == _AuthMode.register) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _idSuffixController,
            keyboardType: TextInputType.number,
            maxLength: 5,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              counterText: '',
              labelText: '5 so cuoi CCCD',
              hintText: '12345',
              prefixIcon: Icon(Icons.verified_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => loading ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Xac nhan mat khau',
              hintText: 'Nhap lai mat khau',
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureConfirm ? 'Hien mat khau' : 'An mat khau',
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                icon: Icon(_obscureConfirm
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
              ),
            ),
          ),
        ],
        if (_mode == _AuthMode.login) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _switchMode(_AuthMode.forgot),
              child: const Text('Quen mat khau'),
            ),
          ),
        ],
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xfffff1f2),
              border: Border.all(color: const Color(0xfffecaca)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _error,
              style: const TextStyle(
                  color: Color(0xffb91c1c),
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: loading ? null : _submit,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Icon(
                  _mode == _AuthMode.login ? Icons.login : Icons.arrow_forward),
          label: Text(_submitLabel),
        ),
        const SizedBox(height: 12),
        _SwitchLine(mode: _mode, onChanged: _switchMode),
      ],
    );
  }

  String get _submitLabel {
    switch (_mode) {
      case _AuthMode.login:
        return 'Dang nhap';
      case _AuthMode.register:
        return 'Dang ky';
      case _AuthMode.forgot:
        return 'Xac minh';
    }
  }
}

class _AuthBrandHeader extends StatelessWidget {
  const _AuthBrandHeader();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        BrandLogo(size: 64, padding: 9),
        SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YS Chat',
                style: TextStyle(
                    color: AppColors.brand,
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4),
              Text(
                'Ket noi noi bo nhanh va bao mat',
                style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AuthModeTabs extends StatelessWidget {
  const _AuthModeTabs({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xfff0f4fa),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _TabButton(
              label: 'Dang nhap',
              active: mode == _AuthMode.login,
              onTap: () => onChanged(_AuthMode.login)),
          _TabButton(
              label: 'Dang ky',
              active: mode == _AuthMode.register,
              onTap: () => onChanged(_AuthMode.register)),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton(
      {required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active
                ? [
                    BoxShadow(
                        color: const Color(0xff0f172a).withValues(alpha: 0.08),
                        blurRadius: 12)
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.brandDark : AppColors.muted,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  const _FormHeader({required this.mode});

  final _AuthMode mode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          switch (mode) {
            _AuthMode.login => 'Dang nhap',
            _AuthMode.register => 'Tao tai khoan moi',
            _AuthMode.forgot => 'Khoi phuc mat khau',
          },
          style: const TextStyle(
              color: AppColors.ink,
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(
          switch (mode) {
            _AuthMode.login => 'Su dung tai khoan noi bo cua ban',
            _AuthMode.register => 'Nhap thong tin nhan vien de kich hoat',
            _AuthMode.forgot => 'Xac minh thong tin de nhan mat khau moi',
          },
          style: const TextStyle(
              color: AppColors.muted,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _SwitchLine extends StatelessWidget {
  const _SwitchLine({required this.mode, required this.onChanged});

  final _AuthMode mode;
  final ValueChanged<_AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    if (mode == _AuthMode.login) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Chua co tai khoan?',
              style: TextStyle(color: AppColors.muted)),
          TextButton(
              onPressed: () => onChanged(_AuthMode.register),
              child: const Text('Dang ky ngay')),
        ],
      );
    }
    return Center(
      child: TextButton(
        onPressed: () => onChanged(_AuthMode.login),
        child: Text(mode == _AuthMode.register
            ? 'Da co tai khoan? Dang nhap'
            : 'Quay lai dang nhap'),
      ),
    );
  }
}
