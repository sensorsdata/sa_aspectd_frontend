# aspectd_frontend

frontend_server.dart.snapshot 打包工程

# 打包方式

dart  --deterministic  --packages=rebased_package_config.json  --snapshot=frontend_server.dart.snapshot  --snapshot-kind=kernel   starter.dart
