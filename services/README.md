# services / test 目录说明

- `services/`：预留后端服务源码（RPC 代理、桥对接服务），
  落地时可将 `lib/core/network/*_rpc.dart` 的代理逻辑迁移至此。
- `test/`：Flutter 单元测试目录（`flutter test` 使用），
  首批用例建议：`Amount` 精度换算、`QrScanner.parse` 协议解析、
  `Derivation` 地址前缀、`PaymentService` 资产与金额校验。