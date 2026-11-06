import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:animestream/core/app/runtimeDatas.dart';
import 'package:animestream/core/manga/apkBridgeConfig.dart';
import 'package:animestream/core/manga/providers/apkBridgeProviders.dart';
import 'package:animestream/ui/models/widgets/clickableItem.dart';
import 'package:animestream/ui/pages/settingPages/common.dart';

class ApkBridgeSetting extends StatefulWidget {
  const ApkBridgeSetting({super.key});

  @override
  State<ApkBridgeSetting> createState() => _ApkBridgeSettingState();
}

class _ApkBridgeSettingState extends State<ApkBridgeSetting> {
  ApkBridgeConfig _config = ApkBridgeConfig();
  bool _loading = true;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ApkBridgeConfig.load();
    if (!mounted) return;
    setState(() {
      _config = config;
      _urlController.text = config.bridgeUrl;
      _loading = false;
    });
  }

  Future<void> _save() async {
    _config.bridgeUrl = _urlController.text.trim().isEmpty
        ? 'http://127.0.0.1:8080'
        : _urlController.text.trim();
    await _config.save();
    await refreshApkBridgeSources();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ApkBridge settings saved.')),
    );
  }

  Future<void> _addApk() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['apk'],
    );
    if (result == null || result.isEmpty) return;
    final picked = result.single;
    final path = picked.path;
    if (path == null) return;
    final name = picked.name.replaceAll('.apk', '');
    _config.entries = <ApkBridgeEntry>[
      ..._config.entries,
      ApkBridgeEntry(name: name, apkPath: path),
    ];
    await _config.save();
    await refreshApkBridgeSources();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _removeEntry(ApkBridgeEntry entry) async {
    _config.entries = _config.entries.where((e) => e != entry).toList();
    await _config.save();
    await refreshApkBridgeSources();
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: appTheme.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: pagePadding(context, bottom: true),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              topRow(context, 'ApkBridge'),
              const SizedBox(height: 12),
              Text(
                'ApkBridge runs Aniyomi/Tachiyomi extensions on an Android device and exposes them over HTTP. Set the bridge URL and add extension APKs below.',
                style: TextStyle(color: appTheme.textSubColor, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _urlController,
                style: TextStyle(color: appTheme.textMainColor),
                decoration: InputDecoration(
                  labelText: 'Bridge URL',
                  hintText: 'http://127.0.0.1:8080',
                  labelStyle: TextStyle(color: appTheme.textSubColor),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Save'),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Extensions', style: _titleStyle()),
                  TextButton.icon(
                    onPressed: _addApk,
                    icon: const Icon(Icons.add),
                    label: const Text('Add APK'),
                  ),
                ],
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _config.entries.length,
                  itemBuilder: (context, index) {
                    final entry = _config.entries[index];
                    return ListTile(
                      title: Text(entry.name, style: TextStyle(color: appTheme.textMainColor)),
                      subtitle: Text(entry.apkPath, style: TextStyle(color: appTheme.textSubColor, fontSize: 11)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeEntry(entry),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _titleStyle() => TextStyle(
        color: appTheme.textMainColor,
        fontFamily: 'Rubik',
        fontWeight: FontWeight.bold,
      );
}
