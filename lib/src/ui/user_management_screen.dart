import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../state/user_role_controller.dart';

class UserManagementBody extends StatefulWidget {
  const UserManagementBody({required this.roleController, super.key});

  final UserRoleController roleController;

  @override
  State<UserManagementBody> createState() => _UserManagementBodyState();
}

class _UserManagementBodyState extends State<UserManagementBody> {
  late Stream<List<UserProfile>> _profiles = widget.roleController
      .streamAllProfiles();

  void _retry() {
    setState(() {
      _profiles = widget.roleController.streamAllProfiles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final roleController = widget.roleController;
    return StreamBuilder<List<UserProfile>>(
      stream: _profiles,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load users: ${snapshot.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _retry,
                    child: const Text('Try again'),
                  ),
                ],
              ),
            ),
          );
        }
        final profiles = snapshot.data ?? [];
        if (profiles.isEmpty) {
          return const Center(child: Text('No users found.'));
        }
        return ListView.builder(
          itemCount: profiles.length,
          itemBuilder: (context, i) {
            final profile = profiles[i];
            final isOwnProfile = profile.uid == roleController.currentUid;
            return _UserProfileTile(
              key: ValueKey(profile.uid),
              profile: profile,
              isOwnProfile: isOwnProfile,
              onRenamed: isOwnProfile
                  ? null
                  : (newName) =>
                        roleController.updateDisplayName(profile.uid, newName),
              onRolesChanged: isOwnProfile
                  ? null
                  : (newRoles) =>
                        roleController.updateUserRoles(profile.uid, newRoles),
            );
          },
        );
      },
    );
  }
}

class _UserProfileTile extends StatefulWidget {
  const _UserProfileTile({
    required this.profile,
    required this.isOwnProfile,
    required this.onRenamed,
    required this.onRolesChanged,
    super.key,
  });

  final UserProfile profile;
  final bool isOwnProfile;
  final Future<void> Function(String)? onRenamed;
  final Future<void> Function(Set<UserRole>)? onRolesChanged;

  @override
  State<_UserProfileTile> createState() => _UserProfileTileState();
}

class _UserProfileTileState extends State<_UserProfileTile> {
  bool _expanded = false;
  bool _saving = false;
  late Set<UserRole> _pendingRoles;

  @override
  void initState() {
    super.initState();
    _pendingRoles = Set.of(widget.profile.roles);
  }

  @override
  void didUpdateWidget(_UserProfileTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.uid != widget.profile.uid) {
      _expanded = false;
      _pendingRoles = Set.of(widget.profile.roles);
    } else if (!_expanded) {
      _pendingRoles = Set.of(widget.profile.roles);
    }
  }

  Future<void> _rename() async {
    final profile = widget.profile;
    final controller = TextEditingController(text: profile.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change display name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The name ${profile.email ?? profile.uid} is shown as on the '
              'schedule. It reaches their device on their next sign-in.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 64,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Display name'),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (newName == null || newName.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.onRenamed!(newName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to rename: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_pendingRoles.isEmpty) {
      _pendingRoles = {UserRole.viewer};
    }
    setState(() => _saving = true);
    try {
      await widget.onRolesChanged!(_pendingRoles);

      if (mounted) setState(() => _expanded = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save roles: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final subtitleParts = <String>[
      if (profile.email != null) profile.email!,
      'uid: ${profile.uid}',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              profile.displayName.isEmpty ? '(no name)' : profile.displayName,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final part in subtitleParts)
                  Text(part, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  'Roles: ${profile.roles.displayText}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.isOwnProfile)
                  Text(
                    'You cannot edit your own roles.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontStyle: FontStyle.italic),
                  ),
              ],
            ),
            trailing: widget.isOwnProfile
                ? null
                : IconButton(
                    icon: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.edit_rounded,
                    ),
                    tooltip: _expanded ? 'Collapse' : 'Edit roles',
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
            isThreeLine: true,
          ),
          if (_expanded && !widget.isOwnProfile) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Assign roles',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (widget.onRenamed != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving ? null : _rename,
                    icon: const Icon(Icons.badge_rounded),
                    label: const Text('Change name'),
                  ),
                ),
              ),
            for (final role in UserRole.values)
              CheckboxListTile(
                title: Text(role.displayName),
                value: _pendingRoles.contains(role),
                onChanged: _saving
                    ? null
                    : (checked) {
                        setState(() {
                          if (checked == true) {
                            _pendingRoles.add(role);
                          } else {
                            _pendingRoles.remove(role);
                          }
                        });
                      },
                dense: true,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _expanded = false;
                            _pendingRoles = Set.of(profile.roles);
                          }),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
