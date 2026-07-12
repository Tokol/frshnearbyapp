import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/app_localizations.dart';

const _green = Color(0xFF2F6B45);
const _ink = Color(0xFF183326);
const _muted = Color(0xFF647267);
const _line = Color(0xFFE2E8DD);
const _gold = Color(0xFFE9CD7A);

enum _Role { consumer, producer }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _pageController = PageController();
  final _profileKey = GlobalKey<FormState>();
  int _page = 0;
  _Role _role = _Role.consumer;
  bool _photoAdded = false;

  bool get _showApple =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  void _goTo(int page) {
    setState(() => _page = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _socialSignIn() {
    // Backend account lookup connects here: existing users enter the app;
    // new users continue through the short profile flow.
    _goTo(1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SvgPicture.asset(
              'assets/images/auth_farm.svg',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      if (_page > 0)
                        IconButton.filledTonal(
                          onPressed: () => _goTo(_page - 1),
                          icon: const Icon(Icons.arrow_back_rounded),
                        )
                      else
                        const SizedBox(width: 48),
                      const Spacer(),
                      Image.asset(
                        'assets/images/logo_transparent.png',
                        width: 112,
                      ),
                      const Spacer(),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                const Spacer(),
                Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_page > 0 && _page < 4)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                          child: Row(
                            children: List.generate(
                              3,
                              (index) => Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  height: 4,
                                  margin: EdgeInsets.only(
                                    right: index == 2 ? 0 : 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: index < _page ? _green : _line,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        height: _page == 0 ? 430 : 500,
                        child: PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            _SocialPage(
                              showApple: _showApple,
                              onSocial: _socialSignIn,
                            ),
                            _ProfilePage(
                              formKey: _profileKey,
                              photoAdded: _photoAdded,
                              onPhoto:
                                  () => setState(
                                    () => _photoAdded = !_photoAdded,
                                  ),
                              onContinue: () {
                                if (_profileKey.currentState?.validate() ??
                                    false) {
                                  _goTo(2);
                                }
                              },
                            ),
                            _RolePage(
                              role: _role,
                              onRole: (role) => setState(() => _role = role),
                              onContinue: () => _goTo(3),
                            ),
                            _ReviewPage(
                              producer: _role == _Role.producer,
                              onFinish: () => _goTo(4),
                            ),
                            _CompletePage(onDone: () => _goTo(0)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialPage extends StatelessWidget {
  const _SocialPage({required this.showApple, required this.onSocial});
  final bool showApple;
  final VoidCallback onSocial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _PagePadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            l10n.authSimpleTitle,
            textAlign: TextAlign.center,
            style: _titleStyle(context),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.authSimpleSubtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 15),
          ),
          const SizedBox(height: 24),
          _SocialButton(
            icon: 'G',
            label: l10n.authContinueGoogle,
            onPressed: onSocial,
          ),
          if (showApple) ...[
            const SizedBox(height: 10),
            _SocialButton(
              icon: '●',
              label: l10n.authContinueApple,
              onPressed: onSocial,
            ),
          ],
          const SizedBox(height: 10),
          _SocialButton(
            icon: 'f',
            label: l10n.authContinueFacebook,
            onPressed: onSocial,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.authSocialHint,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({
    required this.formKey,
    required this.photoAdded,
    required this.onPhoto,
    required this.onContinue,
  });
  final GlobalKey<FormState> formKey;
  final bool photoAdded;
  final VoidCallback onPhoto;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _PagePadding(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.authConfirmDetails, style: _titleStyle(context)),
            const SizedBox(height: 4),
            Text(
              l10n.authConfirmDetailsHint,
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 14),
            Center(
              child: InkWell(
                onTap: onPhoto,
                borderRadius: BorderRadius.circular(999),
                child: CircleAvatar(
                  radius: 34,
                  backgroundColor: const Color(0xFFDCEBDD),
                  child: Icon(
                    photoAdded
                        ? Icons.check_rounded
                        : Icons.add_a_photo_outlined,
                    color: _green,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.authPhotoOptional,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextFormField(
              decoration: InputDecoration(labelText: l10n.authFullName),
              validator:
                  (value) =>
                      value == null || value.trim().isEmpty
                          ? l10n.authNameError
                          : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(labelText: l10n.authGender),
                    items:
                        [
                              l10n.authGenderWoman,
                              l10n.authGenderMan,
                              l10n.authGenderOther,
                            ]
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: l10n.authPhone),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: l10n.authEmail),
            ),
            const Spacer(),
            _PrimaryButton(label: l10n.actionContinue, onPressed: onContinue),
          ],
        ),
      ),
    );
  }
}

class _RolePage extends StatelessWidget {
  const _RolePage({
    required this.role,
    required this.onRole,
    required this.onContinue,
  });
  final _Role role;
  final ValueChanged<_Role> onRole;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _PagePadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.authRoleTitleNew, style: _titleStyle(context)),
          const SizedBox(height: 6),
          Text(
            l10n.authRoleHint,
            style: const TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4E9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _RoleToggle(
                    selected: role == _Role.consumer,
                    icon: Icons.shopping_basket_outlined,
                    label: l10n.authConsumer,
                    onTap: () => onRole(_Role.consumer),
                  ),
                ),
                Expanded(
                  child: _RoleToggle(
                    selected: role == _Role.producer,
                    icon: Icons.agriculture_outlined,
                    label: l10n.authProducer,
                    onTap: () => onRole(_Role.producer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8F1),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const Icon(Icons.eco_outlined, color: _green, size: 32),
                const SizedBox(height: 8),
                Text(
                  role == _Role.consumer
                      ? l10n.authConsumerMessage
                      : l10n.authProducerMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.4, color: _ink),
                ),
              ],
            ),
          ),
          const Spacer(),
          _PrimaryButton(label: l10n.actionContinue, onPressed: onContinue),
        ],
      ),
    );
  }
}

class _ReviewPage extends StatelessWidget {
  const _ReviewPage({required this.producer, required this.onFinish});
  final bool producer;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _PagePadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.authAlmostDone, style: _titleStyle(context)),
          const SizedBox(height: 8),
          Text(l10n.authAlmostDoneHint, style: const TextStyle(color: _muted)),
          const SizedBox(height: 28),
          _SummaryRow(
            icon: Icons.person_outline,
            label: l10n.authDetailsConfirmed,
          ),
          _SummaryRow(
            icon:
                producer
                    ? Icons.agriculture_outlined
                    : Icons.shopping_basket_outlined,
            label: producer ? l10n.authProducer : l10n.authConsumer,
          ),
          _SummaryRow(
            icon: Icons.verified_user_outlined,
            label: l10n.authAdminReview,
          ),
          const Spacer(),
          _PrimaryButton(label: l10n.authFinishSetup, onPressed: onFinish),
        ],
      ),
    );
  }
}

class _CompletePage extends StatelessWidget {
  const _CompletePage({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return _PagePadding(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Color(0xFFDCEBDD),
            child: Icon(Icons.check_rounded, color: _green, size: 42),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.authWelcomeReady,
            textAlign: TextAlign.center,
            style: _titleStyle(context),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.authVerificationPending,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 28),
          _PrimaryButton(label: l10n.authEnterApp, onPressed: onDone),
        ],
      ),
    );
  }
}

class _PagePadding extends StatelessWidget {
  const _PagePadding({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 18), child: child);
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final String icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(50),
      foregroundColor: _ink,
      side: const BorderSide(color: _line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            icon,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 28),
      ],
    ),
  );
}

class _RoleToggle extends StatelessWidget {
  const _RoleToggle({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: selected ? _gold : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: _ink),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(50),
      backgroundColor: _green,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    ),
    child: Text(label),
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8F1),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: _green),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

TextStyle _titleStyle(BuildContext context) => Theme.of(context)
    .textTheme
    .titleLarge!
    .copyWith(fontWeight: FontWeight.w900, color: _ink, height: 1.15);
