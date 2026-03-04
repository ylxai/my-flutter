import 'dart:io';
import 'package:native_assets_cli/native_assets_cli.dart';

void main(List<String> args) async {
  await build(args, (config, output) async {
    final rustDir = config.packageRoot.resolve('rust/');
    final profile = config.buildMode == BuildMode.release ? 'release' : 'debug';
    final cargoArgs = profile == 'release'
        ? ['build', '--release']
        : ['build'];

    final result = await Process.run(
      'cargo',
      cargoArgs,
      workingDirectory: rustDir.toFilePath(),
    );

    if (result.exitCode != 0) {
      throw Exception('Cargo build failed:\n${result.stderr}');
    }

    final libName = 'libfilecopy_native.so';
    final libPath = rustDir.resolve('target/$profile/$libName');

    output.addAsset(
      NativeCodeAsset(
        package: config.packageName,
        name: 'src/rust/libfilecopy_native.so',
        linkMode: DynamicLoadingBundled(),
        os: OS.linux,
        architecture: Architecture.x64,
        file: libPath,
      ),
    );
  });
}
