// TxTrackerNotifier 单元测试（Fake RPC，不触网）。
//
// 覆盖：
// - 转出登记后展示 0/6，达到 6 确认自动消失；
// - 转入经区块扫描（1–5 确认）与 mempool（0 确认）发现；
// - 6 确认及以上的转入不展示。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rcpu_wallet/core/network/native_rpc.dart';
import 'package:rcpu_wallet/features/payment/tx_tracker.dart';

class _FakeRpc extends NativeRpcClient {
  int confs = 0;
  int tip = 1000;
  List<ScannedVout> blockVouts = const [];
  List<ScannedVout> mempoolVouts = const [];
  String? script = '0014abc';

  @override
  Future<int?> getConfirmations(String txid) async => confs;

  @override
  Future<int> getBlockHeight() async => tip;

  @override
  String? scriptHexForAddress(String address) => script;

  @override
  Future<List<ScannedVout>> getBlockVouts(int height) async =>
      height == tip ? blockVouts : const [];

  @override
  Future<List<ScannedVout>> getMempoolVouts({int cap = 200}) async =>
      mempoolVouts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recordOutgoing 展示 0/6，达到 6 确认后自动消失', () async {
    final rpc = _FakeRpc();
    final tracker = TxTrackerNotifier(rpc);

    await tracker.recordOutgoing(txid: 'aa', amount: '1.5', address: 'rcpu1x');
    expect(tracker.state.length, 1);
    expect(tracker.state.single.direction, 'out');
    expect(tracker.state.single.confirmations, 0);

    rpc.confs = 6;
    await tracker.refresh('rcpu1x');
    expect(tracker.state, isEmpty);
  });

  test('区块扫描发现转入（1 确认），高度推进到 6 确认后消失', () async {
    final rpc = _FakeRpc()
      ..blockVouts = const [
        ScannedVout(txid: 'bb', scriptHex: '0014abc', amountMicro: 250000000),
        // 非本人脚本的输出被忽略。
        ScannedVout(txid: 'bb', scriptHex: '0014fff', amountMicro: 1),
      ];
    final tracker = TxTrackerNotifier(rpc);

    await tracker.refresh('rcpu1x');
    expect(tracker.state.length, 1);
    expect(tracker.state.single.direction, 'in');
    expect(tracker.state.single.amount, '2.5');
    expect(tracker.state.single.confirmations, 1);

    // 高度推进 5 块后该交易 6 确认，且已不在最近 5 块扫描窗口内。
    rpc.tip = 1005;
    rpc.blockVouts = const [];
    await tracker.refresh('rcpu1x');
    expect(tracker.state, isEmpty);
  });

  test('mempool 发现 0 确认转入，同交易多输出合并金额', () async {
    final rpc = _FakeRpc()
      ..mempoolVouts = const [
        ScannedVout(txid: 'cc', scriptHex: '0014abc', amountMicro: 100000000),
        ScannedVout(txid: 'cc', scriptHex: '0014abc', amountMicro: 50000000),
      ];
    final tracker = TxTrackerNotifier(rpc);

    await tracker.refresh('rcpu1x');
    expect(tracker.state.length, 1);
    expect(tracker.state.single.direction, 'in');
    expect(tracker.state.single.confirmations, 0);
    expect(tracker.state.single.amount, '1.5');
  });
}
