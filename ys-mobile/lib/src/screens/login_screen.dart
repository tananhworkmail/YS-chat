import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_state.dart';
import '../l10n/app_localizations.dart';
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
    final loginFailed = context.l10n.t('loginFailed');
    try {
      await state.login(
          _useridController.text.trim(), _passwordController.text);
    } catch (err) {
      _showError(_friendlyError(err, fallback: loginFailed));
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
      _showError(context.l10n.t('requiredFields'));
      return;
    }
    if (!RegExp(r'^\d{5}$').hasMatch(idSuffix)) {
      _showError(context.l10n.t('idSuffixInvalid'));
      return;
    }
    if (password != confirm) {
      _showError(context.l10n.t('passwordMismatch'));
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
        SnackBar(content: Text(context.l10n.t('registerSuccess'))),
      );
    }, fallback: context.l10n.t('registerFailed'));
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
      _showError(context.l10n.t('requiredVerifyFields'));
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
        SnackBar(content: Text(context.l10n.t('verifySuccess'))),
      );
    }, fallback: context.l10n.t('verifyFailed'));
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
      if (data is Map && data['error'] != null) {
        final errorCode = '${data['error']}';
        return context.l10n.apiError(errorCode) ?? errorCode;
      }
      if (err.type == DioExceptionType.connectionTimeout ||
          err.type == DioExceptionType.receiveTimeout) {
        return context.l10n.t('connectionTimeout');
      }
      if (err.response == null) return context.l10n.t('serverUnreachable');
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
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 72, 18, 18),
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
              const Positioned(
                top: 12,
                right: 14,
                child: _AuthLanguageMenu(),
              ),
            ],
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
          decoration: InputDecoration(
            labelText: context.l10n.t('employeeId'),
            hintText: context.l10n.t('enterEmployeeId'),
            prefixIcon: const Icon(Icons.person_outline),
          ),
        ),
        if (_mode != _AuthMode.login) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _fullnameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.t('fullName'),
              hintText: context.l10n.t('enterFullName'),
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
        ],
        if (_mode == _AuthMode.forgot) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _birthdayController,
            readOnly: true,
            onTap: _pickBirthday,
            decoration: InputDecoration(
              labelText: context.l10n.t('birthday'),
              hintText: 'YYYY-MM-DD',
              prefixIcon: const Icon(Icons.event_outlined),
              suffixIcon: const Icon(Icons.calendar_month_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _idCardController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => loading ? null : _submit(),
            decoration: InputDecoration(
              labelText: context.l10n.t('idCard'),
              hintText: context.l10n.t('enterIdCard'),
              prefixIcon: const Icon(Icons.verified_user_outlined),
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
              labelText: context.l10n.t('password'),
              hintText: context.l10n.t('enterPassword'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _obscurePassword
                    ? context.l10n.t('showPassword')
                    : context.l10n.t('hidePassword'),
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
            decoration: InputDecoration(
              counterText: '',
              labelText: context.l10n.t('idSuffix'),
              hintText: '12345',
              prefixIcon: const Icon(Icons.verified_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirm,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => loading ? null : _submit(),
            decoration: InputDecoration(
              labelText: context.l10n.t('confirmPassword'),
              hintText: context.l10n.t('enterConfirmPassword'),
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              suffixIcon: IconButton(
                tooltip: _obscureConfirm
                    ? context.l10n.t('showPassword')
                    : context.l10n.t('hidePassword'),
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
              child: Text(context.l10n.t('forgotPassword')),
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
        return context.l10n.t('login');
      case _AuthMode.register:
        return context.l10n.t('register');
      case _AuthMode.forgot:
        return context.l10n.t('verify');
    }
  }
}

class _AuthLanguageMenu extends StatelessWidget {
  const _AuthLanguageMenu();

  @override
  Widget build(BuildContext context) {
    final languageCode = context.select(
      (AppState state) => state.languageCode,
    );

    return PopupMenuButton<String>(
      tooltip: context.l10n.t('language'),
      initialValue: languageCode,
      onSelected: (code) => context.read<AppState>().setLanguage(code),
      itemBuilder: (context) => const ['vi', 'en', 'zh']
          .map(
            (code) => PopupMenuItem(
              value: code,
              child: Text(AppLocalizations.languageName(code)),
            ),
          )
          .toList(),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
          boxShadow: [
            BoxShadow(
              color: const Color(0xff0f172a).withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, color: AppColors.brandDark, size: 19),
            const SizedBox(width: 7),
            Text(
              languageCode.toUpperCase(),
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, color: AppColors.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

class _AuthBrandHeader extends StatelessWidget {
  const _AuthBrandHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const BrandLogo(size: 64, padding: 9),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'YS Chat',
                style: TextStyle(
                    color: AppColors.brand,
                    fontSize: 24,
                    height: 1.15,
                    fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.t('internalTagline'),
                style: const TextStyle(
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
              label: context.l10n.t('login'),
              active: mode == _AuthMode.login,
              onTap: () => onChanged(_AuthMode.login)),
          _TabButton(
              label: context.l10n.t('register'),
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
            _AuthMode.login => context.l10n.t('login'),
            _AuthMode.register => context.l10n.t('createAccount'),
            _AuthMode.forgot => context.l10n.t('recoverPassword'),
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
            _AuthMode.login => context.l10n.t('loginSubtitle'),
            _AuthMode.register => context.l10n.t('registerSubtitle'),
            _AuthMode.forgot => context.l10n.t('forgotSubtitle'),
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
          Text(context.l10n.t('noAccount'),
              style: const TextStyle(color: AppColors.muted)),
          TextButton(
              onPressed: () => onChanged(_AuthMode.register),
              child: Text(context.l10n.t('registerNow'))),
        ],
      );
    }
    return Center(
      child: TextButton(
        onPressed: () => onChanged(_AuthMode.login),
        child: Text(mode == _AuthMode.register
            ? context.l10n.t('haveAccountLogin')
            : context.l10n.t('backToLogin')),
      ),
    );
  }
}
