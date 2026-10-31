import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/user_role.dart';
import '../theme/pit_palette.dart';

class TourStep {
  const TourStep({
    required this.icon,
    required this.title,
    required this.body,
    this.tabIndex,
  });

  final IconData icon;
  final String title;
  final String body;

  final int? tabIndex;
}

const Map<int, TourStep> _kTourStepsByTabIndex = {
  AppTabs.now: TourStep(
    icon: Icons.home_outlined,
    tabIndex: AppTabs.now,
    title: 'Now',
    body:
        'Your next pit shift, overdue loans, and packing progress at a '
        'glance. Find a tool from here, or press / on a keyboard.',
  ),
  AppTabs.inventory: TourStep(
    icon: Icons.inventory_2_outlined,
    tabIndex: AppTabs.inventory,
    title: 'Inventory',
    body:
        'Every tool and consumable, and where it lives in the lab and the '
        'pit. Search by name to find a tool fast.',
  ),
  AppTabs.packing: TourStep(
    icon: Icons.local_shipping_outlined,
    tabIndex: AppTabs.packing,
    title: 'Packing',
    body:
        'Load-in and load-out for an event. Each item moves through '
        'Packing, Staging, Loading, and Ready, with photos of what went '
        'in each container.',
  ),
  AppTabs.borrowed: TourStep(
    icon: Icons.handshake_outlined,
    tabIndex: AppTabs.borrowed,
    title: 'Borrowed',
    body:
        'Tools lent out of the lab: which team has each one and when it '
        'should come back. Overdue loans show a count on this tab.',
  ),
  AppTabs.maps: TourStep(
    icon: Icons.map_outlined,
    tabIndex: AppTabs.maps,
    title: 'Maps',
    body:
        'Lab, pit, and vehicle diagrams with storage locations pinned. Tap '
        'a pin for its details.',
  ),
  AppTabs.schedule: TourStep(
    icon: Icons.event_note_outlined,
    tabIndex: AppTabs.schedule,
    title: 'Schedule',
    body:
        'Pit shifts for the event, so the pit is always staffed. Check here '
        'to see when you are on.',
  ),
  AppTabs.docs: TourStep(
    icon: Icons.menu_book_outlined,
    tabIndex: AppTabs.docs,
    title: 'Docs',
    body:
        'Reference docs for the app, filtered to your role: how it is '
        'built and released, and what data lives where.',
  ),
  AppTabs.users: TourStep(
    icon: Icons.manage_accounts_outlined,
    tabIndex: AppTabs.users,
    title: 'Users',
    body:
        'Set roles for teammates. New accounts start with the pit role, so '
        'check here to grant admin or developer access.',
  ),
  AppTabs.usage: TourStep(
    icon: Icons.insights_outlined,
    tabIndex: AppTabs.usage,
    title: 'Usage',
    body:
        'What is actually getting used across the team, for deciding what '
        'to work on next.',
  ),
  AppTabs.robotLogs: TourStep(
    icon: Icons.sd_storage_outlined,
    tabIndex: AppTabs.robotLogs,
    title: 'Robot logs',
    body:
        'Pull match logs and Limelight rewinds off the robot and send them '
        'to the log site in one click.',
  ),
  AppTabs.settings: TourStep(
    icon: Icons.settings_outlined,
    tabIndex: AppTabs.settings,
    title: 'Settings',
    body:
        'Appearance, problem reports, and app details live here. You can '
        'replay this tour from Settings any time.',
  ),
};

List<TourStep> buildTourSteps(List<int> orderedTabIndices) {
  return <TourStep>[
    const TourStep(
      icon: Icons.waving_hand_outlined,
      title: 'Welcome to Spectrum Pit',
      body:
          'Find any tool, pack the trailer in a known order, track what '
          'leaves the lab, and keep the pit staffed. Here is where each '
          'part lives.',
    ),
    for (final tabIndex in orderedTabIndices) ?_kTourStepsByTabIndex[tabIndex],
  ];
}

class WelcomeTourOverlay extends StatefulWidget {
  const WelcomeTourOverlay({
    required this.steps,
    required this.onDone,
    this.navKey,
    this.onStepChanged,
    super.key,
  });

  final List<TourStep> steps;

  final GlobalKey? navKey;

  final VoidCallback onDone;

  final ValueChanged<TourStep>? onStepChanged;

  @override
  State<WelcomeTourOverlay> createState() => _WelcomeTourOverlayState();
}

class _WelcomeTourOverlayState extends State<WelcomeTourOverlay> {
  final PageController _pageController = PageController();
  int _page = 0;

  Rect? _navRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _notifyStepChangedFor(_page);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _notifyStepChangedFor(int page) {
    if (page < 0 || page >= widget.steps.length) return;
    widget.onStepChanged?.call(widget.steps[page]);
  }

  int get _currentPage => _pageController.hasClients
      ? (_pageController.page ?? _page.toDouble()).round()
      : _page;

  void _goTo(int target) {
    _notifyStepChangedFor(target);
    if (MediaQuery.of(context).disableAnimations) {
      _pageController.jumpToPage(target);
      return;
    }
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    final currentPage = _currentPage;
    if (currentPage >= widget.steps.length - 1) {
      widget.onDone();
      return;
    }
    _goTo(currentPage + 1);
  }

  void _previous() {
    final currentPage = _currentPage;
    if (currentPage <= 0) return;
    _goTo(currentPage - 1);
  }

  TourStep? get _currentStep =>
      (_page < 0 || _page >= widget.steps.length) ? null : widget.steps[_page];

  void _measureNav() {
    if (!mounted) return;
    final box = widget.navKey?.currentContext?.findRenderObject();
    final rect = box is RenderBox && box.hasSize && !box.size.isEmpty
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    if (rect != _navRect) setState(() => _navRect = rect);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isLast = _page >= widget.steps.length - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureNav());

    final nav = _navRect;
    final size = MediaQuery.sizeOf(context);
    final navIsBottomBar = nav != null && nav.width >= size.width;
    final navIsRail = nav != null && !navIsBottomBar;
    var cardInsets = EdgeInsets.zero;
    if (nav != null) {
      cardInsets = navIsBottomBar
          ? EdgeInsets.only(bottom: size.height - nav.top)
          : EdgeInsets.only(left: nav.right);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDone,
            child: CustomPaint(
              painter: _SpotlightPainter(
                scrim: colorScheme.scrim.withValues(alpha: 0.4),
                hole: _currentStep?.tabIndex == null ? null : nav,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            left: !navIsRail,
            bottom: !navIsBottomBar,
            child: Padding(
              padding: const EdgeInsets.all(16) + cardInsets,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Material(
                  color: PitPalette.surfaceOf(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.all(
                      Radius.circular(PitPalette.radiusLg),
                    ),
                    side: BorderSide(color: PitPalette.outlineOf(context)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: math.min(
                            MediaQuery.textScalerOf(context).scale(150),
                            size.height * 0.4,
                          ),
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: widget.steps.length,
                            onPageChanged: (page) {
                              setState(() => _page = page);
                              _notifyStepChangedFor(page);
                            },
                            itemBuilder: (context, index) =>
                                _StepContent(step: widget.steps[index]),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _StepDots(
                                count: widget.steps.length,
                                page: _page,
                              ),
                            ),
                            if (_page > 0)
                              TextButton(
                                onPressed: _previous,
                                child: const Text('Back'),
                              ),
                            if (!isLast)
                              TextButton(
                                onPressed: widget.onDone,
                                child: const Text('Skip'),
                              ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _next,
                              child: Text(isLast ? 'Done' : 'Next'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.count, required this.page});

  final int count;
  final int page;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Step ${page + 1} of $count',
      child: ExcludeSemantics(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: i == page ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == page
                          ? PitPalette.accentOf(context)
                          : PitPalette.outlineOf(context),
                      borderRadius: const BorderRadius.all(Radius.circular(3)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({required this.step});

  final TourStep step;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(step.icon, size: 22, color: PitPalette.inkOf(context)),
            const SizedBox(width: 10),
            Expanded(child: Text(step.title, style: textTheme.titleMedium)),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: Text(
              step.body,
              style: textTheme.bodyMedium?.copyWith(
                color: PitPalette.inkMutedOf(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({required this.scrim, this.hole});

  final Color scrim;
  final Rect? hole;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(bounds, Paint()..color = scrim);
    final target = hole;
    if (target != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          target,
          const Radius.circular(PitPalette.radiusSm),
        ),
        Paint()..blendMode = BlendMode.clear,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.hole != hole || oldDelegate.scrim != scrim;
}
